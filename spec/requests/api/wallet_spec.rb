# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe 'Wallet' do
  let(:driver) { create(:user, name: 'Dawit Driver') }
  let(:rider) { create(:user, name: 'Rahel Rider') }
  let(:admin) { create(:user, admin: true) }
  let(:trip) { create(:itinerary, user: driver, num_people: 3, price_per_seat: 200) }
  let(:initiate_url) { 'https://paybridge.sandbox.afropays.co/api/v1/TelebirrUssd/direct/transaction-initiate' }

  before do
    allow(AfroPayClient).to receive(:key).and_return('sandbox-key')
    PlatformSetting.current.update!(fee_percent: 10, fee_charged_to: 'passenger')
  end

  def fund(user, amount)
    Wallet.for(user).move!('adjustment', available: amount, memo: 'test')
  end

  def balance(user)
    wallet = Wallet.for(user).reload
    [wallet.available.to_f, wallet.held.to_f]
  end

  def book(method: 'wallet')
    post "/api/v1/itineraries/#{trip.id}/bookings", params: { booking: { seats: 1, payment_method: method } }, headers: api_headers(rider)
    Booking.find_by(id: json.dig('booking', 'id'))
  end

  describe 'top-up by phone prompt' do
    before { stub_request(:post, initiate_url).to_return(body: { isSuccess: true, statusCode: 0, data: { refrence: 'TXN1', paymentUrl: 'https://x' } }.to_json) }

    def start(amount: 500)
      post '/api/v1/wallet/topup', params: { amount:, provider: 'telebirr', phone: '0911 22 33 44' }, headers: api_headers(rider)
      WalletTopup.find_by(id: json.dig('topup', 'id'))
    end

    def callback(topup, **changes)
      body = { Amount: topup.amount.to_f, Currency: 'ETB', Phone: topup.phone, Refrence: 'TXN1', MerchantOrderId: topup.merchant_order_id, PaymentMethod: 'TELEBIRR', Status: 'SUCCESS', ProviderReference: 'TB1' }.merge(changes)
      post "/api/v1/payments/afropay/#{topup.callback_token}", params: body, as: :json
    end

    it 'asks Afro Pay to prompt the phone, and credits nothing yet' do
      topup = start
      expect(response).to have_http_status(:created), response.body
      expect(json['topup']).to include('status' => 'pending', 'amount' => 500.0)
      expect(WebMock).to have_requested(:post, initiate_url).with(headers: { 'X-Api-Key' => 'sandbox-key' },
                                                                  body: hash_including('phone' => '251911223344', 'amount' => 500.0, 'MerchantOrderId' => topup.merchant_order_id))
      expect(balance(rider)).to eq [0.0, 0.0]
    end

    it 'credits the wallet once when Afro Pay reports success, however often it calls back' do
      topup = start
      3.times { callback(topup) }
      expect(response).to have_http_status(:ok)
      expect(balance(rider)).to eq [500.0, 0.0]
      expect(rider.notifications.where(kind: 'wallet_topup').count).to eq 1

      get "/api/v1/wallet/topups/#{topup.id}", headers: api_headers(rider)
      expect(json['topup']).to include('status' => 'success', 'final' => true)
      expect(json['wallet']['available']).to eq 500.0
    end

    it 'credits nothing for a failed or cancelled payment, a wrong amount, a wrong order or a guessed address' do
      topup = start
      callback(topup, Status: 'FAILED')
      callback(topup, Amount: 5000)
      callback(topup, MerchantOrderId: 'SOMEONE-ELSE')
      post '/api/v1/payments/afropay/guessed-token', params: { Status: 'SUCCESS', Amount: 500 }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(balance(rider)).to eq [0.0, 0.0]

      callback(topup, Status: 'CANCELED')
      callback(topup) # a late "success" after a final state changes nothing
      expect(balance(rider)).to eq [0.0, 0.0]
    end

    it 'refuses amounts outside the limits, bad numbers, and says so when Afro Pay is down' do
      start(amount: 1)
      expect(response).to have_http_status(:unprocessable_entity)
      post '/api/v1/wallet/topup', params: { amount: 100, provider: 'telebirr', phone: '123' }, headers: api_headers(rider)
      expect(json['error']['code']).to eq 'invalid_phone'

      stub_request(:post, initiate_url).to_return(status: 400, body: { isSuccess: false, message: 'Duplicate OrderId' }.to_json)
      start
      expect(response).to have_http_status(:bad_gateway)
      expect(WalletTopup.last.status).to eq 'failed'
    end
  end

  describe 'paying for a seat' do
    it 'sets the money aside when the seat is requested, and refuses when the wallet is short' do
      fund(rider, 100)
      expect(book).to be_nil
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']['message']).to include('Add money')

      fund(rider, 400)
      booking = book
      expect(json['booking']['payment']).to include('method' => 'wallet', 'state' => 'held', 'held' => 220.0)
      expect(balance(rider)).to eq [280.0, 220.0]
      expect(booking.payment_state).to eq 'held'
    end

    it 'gives it back when the driver declines or the trip is cancelled' do
      fund(rider, 500)
      booking = book
      patch "/api/v1/bookings/#{booking.id}/decline", headers: api_headers(driver)
      expect(balance(rider)).to eq [500.0, 0.0]
      expect(booking.reload.payment_state).to eq 'refunded'

      other = create(:itinerary, user: driver, num_people: 2, price_per_seat: 100)
      post "/api/v1/itineraries/#{other.id}/bookings", params: { booking: { seats: 1, payment_method: 'wallet' } }, headers: api_headers(rider)
      Booking.last.confirm!
      patch "/api/v1/itineraries/#{other.id}/cancel", headers: api_headers(driver)
      expect(balance(rider)).to eq [500.0, 0.0]
    end

    it 'pays the driver and the platform when the passenger confirms the ride' do
      fund(rider, 500)
      booking = book
      booking.confirm!
      patch "/api/v1/bookings/#{booking.id}/complete", headers: api_headers(rider)
      expect(response).to have_http_status(:unprocessable_entity) # the ride has not left yet

      travel_to(trip.leave_date + 1.hour) do
        patch "/api/v1/bookings/#{booking.id}/complete", headers: api_headers(rider)
        expect(response).to have_http_status(:ok), response.body
        expect(json['booking']['payment']['state']).to eq 'released'
      end
      expect(balance(rider)).to eq [280.0, 0.0]
      expect(balance(driver)).to eq [200.0, 0.0]
      expect(Wallet.platform.available.to_f).to eq 20.0
      expect(driver.notifications.pluck(:kind)).to include('payment_received')
    end

    it 'pays automatically a day after the ride, the next time bookings are opened' do
      fund(rider, 500)
      booking = book
      booking.confirm!
      travel_to(trip.leave_date + 10.hours) do
        get '/api/v1/bookings', headers: api_headers(driver)
        expect(balance(driver)).to eq [0.0, 0.0] # too soon
      end
      travel_to(trip.leave_date + 28.hours) do
        get '/api/v1/bookings', headers: api_headers(driver)
        expect(balance(driver)).to eq [200.0, 0.0]
      end
      expect(booking.reload.payment_state).to eq 'released'
    end

    it 'splits the money when a passenger cancels a confirmed seat late' do
      fund(rider, 500)
      booking = book
      booking.confirm!
      travel_to(trip.leave_date - 1.hour) do
        patch "/api/v1/bookings/#{booking.id}/cancel", headers: api_headers(rider)
      end
      expect(balance(rider)).to eq [300.0, 0.0] # the fare stays with the driver, the fee comes back
      expect(balance(driver)).to eq [200.0, 0.0]
    end

    it 'leaves cash bookings alone' do
      booking = book(method: 'cash')
      expect(booking.payment_state).to eq 'none'
      expect(balance(rider)).to eq [0.0, 0.0]
    end

    it 'never lets the totals drift: everything in equals everything held' do
      fund(rider, 1000)
      booking = book
      booking.confirm!
      travel_to(trip.leave_date + 1.hour) { booking.confirm_completed! }
      total = Wallet.sum(:available) + Wallet.sum(:held)
      expect(total.to_f).to eq 1000.0
      Wallet.find_each { |wallet| expect(wallet.entries.sum(:available_change)).to eq wallet.available }
    end
  end

  describe 'withdrawals' do
    it 'lets a driver ask for money out, and sets it aside until an admin sends it' do
      fund(driver, 800)
      post '/api/v1/wallet/withdraw', params: { amount: 500, method_name: 'Telebirr', account_number: '0911223344', account_name: 'Dawit' }, headers: api_headers(driver)
      expect(response).to have_http_status(:created), response.body
      expect(json['wallet']).to eq('available' => 300.0, 'held' => 500.0)

      sign_in admin
      get '/admin/wallets'
      expect(response.body).to include('Dawit Driver', '0911223344')
      patch "/admin/withdrawals/#{WalletWithdrawal.last.id}/pay", params: { note: 'TB ref 123' }
      expect(balance(driver)).to eq [300.0, 0.0]
      expect(driver.notifications.pluck(:kind)).to include('withdrawal_paid')
    end

    it 'returns the money when an admin rejects, and cannot be handled twice' do
      fund(driver, 800)
      withdrawal = WalletWithdrawal.request!(user: driver, amount: 500, method_name: 'Telebirr', account_number: '0911223344')
      sign_in admin
      patch "/admin/withdrawals/#{withdrawal.id}/reject", params: { note: 'Wrong number' }
      expect(balance(driver)).to eq [800.0, 0.0]
      patch "/admin/withdrawals/#{withdrawal.id}/pay"
      expect(balance(driver)).to eq [800.0, 0.0]
    end

    it 'refuses more than the balance, less than the minimum, and non-admins' do
      fund(driver, 300)
      post '/api/v1/wallet/withdraw', params: { amount: 500, method_name: 'Telebirr', account_number: '0911223344' }, headers: api_headers(driver)
      expect(response).to have_http_status(:unprocessable_entity)
      post '/api/v1/wallet/withdraw', params: { amount: 20, method_name: 'Telebirr', account_number: '0911223344' }, headers: api_headers(driver)
      expect(response).to have_http_status(:unprocessable_entity)

      withdrawal = WalletWithdrawal.request!(user: driver, amount: 200, method_name: 'Telebirr', account_number: '0911223344')
      sign_in rider
      patch "/admin/withdrawals/#{withdrawal.id}/pay"
      expect(withdrawal.reload).to be_requested
    end
  end

  it 'shows the balance and history, and tells the app the wallet is on' do
    fund(rider, 250)
    get '/api/v1/wallet', headers: api_headers(rider)
    expect(json['wallet']).to eq('available' => 250.0, 'held' => 0.0)
    expect(json['entries'].first).to include('kind' => 'adjustment', 'available_change' => 250.0)
    get '/api/v1/config'
    expect(json['wallet']).to include('enabled' => true, 'providers' => %w[telebirr cbe_birr mpesa awash_birr])
  end
end
