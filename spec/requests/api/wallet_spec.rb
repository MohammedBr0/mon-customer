# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe 'Wallet' do
  let(:driver) { create(:user, name: 'Dawit Driver') }
  let(:rider) { create(:user, name: 'Rahel Rider') }
  let(:admin) { create(:user, admin: true) }
  let(:trip) { create(:itinerary, user: driver, num_people: 3, price_per_seat: 200) }
  let(:chapa) { 'https://api.chapa.co/v1' }

  before do
    allow(ChapaClient).to receive(:key).and_return('CHASECK_TEST-x')
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

  describe 'top-up through Chapa' do
    before do
      stub_request(:post, "#{chapa}/transaction/initialize").to_return(body: { status: 'success', data: { checkout_url: 'https://checkout.chapa.co/checkout/payment/abc' } }.to_json)
    end

    def start(amount: 500)
      post '/api/v1/wallet/topup', params: { amount: }, headers: api_headers(rider)
      WalletTopup.find_by(id: json.dig('topup', 'id'))
    end

    def chapa_says(topup, status:, amount: topup.amount.to_f, currency: 'ETB')
      stub_request(:get, "#{chapa}/transaction/verify/#{topup.merchant_order_id}")
        .to_return(body: { status: 'success', data: { status:, amount:, currency:, method: 'telebirr', reference: 'CH1', tx_ref: topup.merchant_order_id } }.to_json)
    end

    it 'opens a payment at Chapa and gives the app its checkout page, crediting nothing yet' do
      topup = start
      expect(response).to have_http_status(:created), response.body
      expect(json['topup']).to include('status' => 'pending', 'amount' => 500.0, 'checkout_url' => 'https://checkout.chapa.co/checkout/payment/abc')
      expect(WebMock).to have_requested(:post, "#{chapa}/transaction/initialize")
        .with(headers: { 'Authorization' => 'Bearer CHASECK_TEST-x' }, body: hash_including('amount' => '500.00', 'currency' => 'ETB', 'tx_ref' => topup.merchant_order_id))
      expect(topup.merchant_order_id.length).to be <= 50
      expect(balance(rider)).to eq [0.0, 0.0]
    end

    it 'credits the wallet once Chapa itself confirms the payment, however often it is asked' do
      topup = start
      chapa_says(topup, status: 'success')
      3.times { get "/api/v1/wallet/topups/#{topup.id}", headers: api_headers(rider) }
      expect(json['topup']).to include('status' => 'success', 'final' => true)
      expect(json['wallet']['available']).to eq 500.0
      post '/api/v1/payments/chapa', params: { tx_ref: topup.merchant_order_id, status: 'success' }, as: :json
      get '/api/v1/payments/chapa/callback', params: { trx_ref: topup.merchant_order_id, status: 'success' }
      expect(balance(rider)).to eq [500.0, 0.0]
      expect(rider.notifications.where(kind: 'wallet_topup').count).to eq 1
    end

    it 'texts a confirmation with Chapa\'s receipt once, and a failed text never blocks the money' do
      allow(AfroMessageClient).to receive(:token).and_return('afro')
      sms = stub_request(:get, %r{https://api.afromessage.com/api/send}).to_return(body: { acknowledge: 'success', response: {} }.to_json)
      rider.update!(phone: '0911223344')
      topup = start
      chapa_says(topup, status: 'success')
      2.times { get "/api/v1/wallet/topups/#{topup.id}", headers: api_headers(rider) }
      expect(sms).to have_been_requested.once
      expect(WebMock).to have_requested(:get, %r{api.afromessage.com/api/send})
        .with(query: hash_including('to' => '+251911223344', 'message' => '500 Br added to your Arifway wallet. Ref CH1. Receipt: https://chapa.link/payment-receipt/CH1'))

      stub_request(:get, %r{https://api.afromessage.com/api/send}).to_return(status: 500, body: 'down')
      second = start(amount: 200)
      chapa_says(second, status: 'success')
      get "/api/v1/wallet/topups/#{second.id}", headers: api_headers(rider)
      expect(balance(rider)).to eq [700.0, 0.0]
    end

    it 'never credits on a callback alone: Chapa must confirm the same amount in birr' do
      topup = start
      chapa_says(topup, status: 'pending')
      post '/api/v1/payments/chapa', params: { tx_ref: topup.merchant_order_id, status: 'success', amount: 500 }, as: :json
      expect(response).to have_http_status(:ok)
      expect(balance(rider)).to eq [0.0, 0.0]

      chapa_says(topup, status: 'success', amount: 5)
      get "/api/v1/wallet/topups/#{topup.id}", headers: api_headers(rider)
      chapa_says(topup, status: 'success', currency: 'USD')
      get "/api/v1/wallet/topups/#{topup.id}", headers: api_headers(rider)
      expect(balance(rider)).to eq [0.0, 0.0]

      chapa_says(topup, status: 'failed')
      get "/api/v1/wallet/topups/#{topup.id}", headers: api_headers(rider)
      expect(json['topup']).to include('status' => 'failed', 'final' => true)
    end

    it 'checks the signature of webhooks when a secret is set' do
      topup = start
      chapa_says(topup, status: 'success')
      allow(ChapaClient).to receive(:webhook_secret).and_return('whsec')
      body = { tx_ref: topup.merchant_order_id }.to_json

      post '/api/v1/payments/chapa', params: body, headers: { 'Content-Type' => 'application/json', 'x-chapa-signature' => 'forged' }
      expect(response).to have_http_status(:unauthorized)
      expect(balance(rider)).to eq [0.0, 0.0]

      post '/api/v1/payments/chapa', params: body, headers: { 'Content-Type' => 'application/json', 'x-chapa-signature' => OpenSSL::HMAC.hexdigest('SHA256', 'whsec', body) }
      expect(response).to have_http_status(:ok)
      expect(balance(rider)).to eq [500.0, 0.0]
    end

    it 'refuses amounts outside the limits, and says so when Chapa is down' do
      start(amount: 1)
      expect(response).to have_http_status(:unprocessable_entity)

      stub_request(:post, "#{chapa}/transaction/initialize").to_return(status: 400, body: { status: 'failed', message: { amount: ['The amount is invalid'] } }.to_json)
      start
      expect(response).to have_http_status(:bad_gateway)
      expect(json['error']['message']).to include('The amount is invalid')
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
    let(:transfer_url) { "#{chapa}/transfers" }

    def ask(amount: 500, bank_code: 855)
      post '/api/v1/wallet/withdraw', params: { amount:, method_name: 'telebirr', account_number: '0911223344', account_name: 'Dawit', bank_code: }, headers: api_headers(driver)
      WalletWithdrawal.find_by(id: json.dig('withdrawal', 'id'))
    end

    it 'lists the banks and wallets Chapa can pay out to' do
      stub_request(:get, "#{chapa}/banks").to_return(body: { status: 'success', data: [
        { id: 855, name: 'telebirr', acct_length: 10, is_mobilemoney: 1, can_process_payouts: 1, is_active: 1 },
        { id: 1, name: 'Closed Bank', acct_length: 13, is_mobilemoney: 0, can_process_payouts: 0, is_active: 1 }
      ] }.to_json)
      get '/api/v1/wallet/banks', headers: api_headers(driver)
      expect(json['banks']).to eq [{ 'id' => 855, 'name' => 'telebirr', 'account_length' => 10, 'mobile' => true }]
    end

    it 'sets the money aside when a driver asks, and sends it through Chapa when an admin approves' do
      fund(driver, 800)
      withdrawal = ask
      expect(response).to have_http_status(:created), response.body
      expect(json['wallet']).to eq('available' => 300.0, 'held' => 500.0)
      expect(withdrawal).to be_requested

      stub_request(:post, transfer_url).to_return(body: { status: 'success', message: 'Transfer queued', data: 'ref' }.to_json)
      sign_in admin
      get '/admin/wallets'
      expect(response.body).to include('Dawit Driver', '0911223344', 'Send with Chapa')
      patch "/admin/withdrawals/#{withdrawal.id}/send_out"
      expect(withdrawal.reload).to be_sending
      expect(WebMock).to have_requested(:post, transfer_url).with(body: hash_including('amount' => '500.00', 'account_number' => '0911223344', 'bank_code' => 855, 'reference' => withdrawal.transfer_reference))
      expect(balance(driver)).to eq [300.0, 500.0] # still set aside until Chapa confirms

      stub_request(:get, "#{chapa}/transfers/verify/#{withdrawal.transfer_reference}").to_return(body: { status: 'success', data: { status: 'success' } }.to_json)
      patch "/admin/withdrawals/#{withdrawal.id}/check"
      expect(withdrawal.reload).to be_paid
      expect(balance(driver)).to eq [300.0, 0.0]
      expect(driver.notifications.pluck(:kind)).to include('withdrawal_paid')
    end

    it 'keeps the money safe when Chapa refuses or the transfer fails' do
      fund(driver, 800)
      withdrawal = ask
      stub_request(:post, transfer_url).to_return(status: 400, body: { status: 'failed', message: 'Insufficient Balance' }.to_json)
      withdrawal.send_with_chapa!(by: admin)
      expect(withdrawal.reload).to be_requested
      expect(withdrawal.note).to include('Insufficient Balance')

      stub_request(:post, transfer_url).to_return(body: { status: 'success', data: 'ref' }.to_json)
      withdrawal.send_with_chapa!(by: admin)
      stub_request(:get, "#{chapa}/transfers/verify/#{withdrawal.transfer_reference}").to_return(body: { status: 'success', data: { status: 'failed/cancelled' } }.to_json)
      post '/api/v1/payments/chapa', params: { reference: withdrawal.transfer_reference }, as: :json
      expect(withdrawal.reload).to be_requested
      expect(balance(driver)).to eq [300.0, 500.0]
    end

    it 'sends small withdrawals straight away when the admins allow it' do
      PlatformSetting.current.update!(auto_payout_limit: 1000)
      stub_request(:post, transfer_url).to_return(body: { status: 'success', data: 'ref' }.to_json)
      fund(driver, 800)
      expect(ask).to be_sending
      fund(driver, 5000)
      expect(ask(amount: 2000)).to be_requested # above the limit: waits for an admin
    end

    it 'returns the money when an admin rejects, and cannot be handled twice' do
      fund(driver, 800)
      withdrawal = ask
      sign_in admin
      patch "/admin/withdrawals/#{withdrawal.id}/reject", params: { note: 'Wrong number' }
      expect(balance(driver)).to eq [800.0, 0.0]
      patch "/admin/withdrawals/#{withdrawal.id}/pay"
      expect(balance(driver)).to eq [800.0, 0.0]
    end

    it 'refuses more than the balance, less than the minimum, and non-admins' do
      fund(driver, 300)
      ask(amount: 500)
      expect(response).to have_http_status(:unprocessable_entity)
      ask(amount: 20)
      expect(response).to have_http_status(:unprocessable_entity)

      withdrawal = ask(amount: 200)
      sign_in rider
      patch "/admin/withdrawals/#{withdrawal.id}/pay"
      patch "/admin/withdrawals/#{withdrawal.id}/send_out"
      expect(withdrawal.reload).to be_requested
    end
  end

  it 'shows the balance and history, and tells the app the wallet is on' do
    fund(rider, 250)
    get '/api/v1/wallet', headers: api_headers(rider)
    expect(json['wallet']).to eq('available' => 250.0, 'held' => 0.0)
    expect(json['entries'].first).to include('kind' => 'adjustment', 'available_change' => 250.0)
    get '/api/v1/config'
    expect(json['wallet']).to include('enabled' => true, 'min_topup' => 10.0)
  end
end
