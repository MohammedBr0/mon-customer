# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Payment methods and identity verification' do
  let(:driver) { create(:user, name: 'Dawit Driver') }
  let(:rider) { create(:user, name: 'Rahel Rider') }
  let(:admin) { create(:user, admin: true) }
  let(:cash) { PaymentMethod.create!(name: 'Cash') }
  let(:telebirr) { PaymentMethod.create!(name: 'Telebirr', name_am: 'ቴሌብር', account_label: 'Telebirr number') }
  let(:photo) { Rack::Test::UploadedFile.new(StringIO.new("\xFF\xD8\xFF fake jpeg".b), 'image/jpeg', true, original_filename: 'id.jpg') }

  describe 'payment methods' do
    before { cash && telebirr }

    it 'offers the admin\'s active methods to the app' do
      PaymentMethod.create!(name: 'Old method', active: false)
      get '/api/v1/config'
      expect(json['payment_methods'].pluck('name')).to eq %w[Cash Telebirr]
      expect(json['payment_methods'].last).to include('account_label' => 'Telebirr number', 'needs_account' => true)
    end

    it 'lets a driver choose what they accept, with the account to pay into' do
      put '/api/v1/me/payment_methods', params: { methods: [{ id: cash.id }, { id: telebirr.id, account_name: 'Dawit', account_number: '0911223344' }] }, headers: api_headers(driver), as: :json
      expect(response).to have_http_status(:ok), response.body
      expect(json['user']['payment_methods']).to eq [{ 'id' => cash.id, 'name' => 'Cash', 'account_name' => nil, 'account_number' => nil },
                                                      { 'id' => telebirr.id, 'name' => 'Telebirr', 'account_name' => 'Dawit', 'account_number' => '0911223344' }]

      put '/api/v1/me/payment_methods', params: { methods: [{ id: cash.id }] }, headers: api_headers(driver), as: :json
      expect(driver.driver_payment_methods.count).to eq 1
    end

    it 'needs the account number when the method has one' do
      put '/api/v1/me/payment_methods', params: { methods: [{ id: telebirr.id }] }, headers: api_headers(driver), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(driver.driver_payment_methods).to be_empty
    end

    it 'shows passengers the methods, and the account only once their seat is confirmed' do
      DriverPaymentMethod.replace_for(driver, [{ id: telebirr.id, account_number: '0911223344' }])
      trip = create(:itinerary, user: driver, num_people: 3)

      get "/api/v1/itineraries/#{trip.id}", headers: api_headers(rider)
      expect(json['itinerary']['payment_methods']).to eq [{ 'id' => telebirr.id, 'name' => 'Telebirr' }]
      expect(response.body).not_to include('0911223344')

      create(:booking, itinerary: trip, passenger: rider).confirm!
      get "/api/v1/itineraries/#{trip.id}", headers: api_headers(rider)
      expect(json['itinerary']['payment_methods'].first).to include('account_number' => '0911223344')
    end

    it 'is managed by super admins only' do
      sign_in admin
      post '/admin/payment_methods', params: { payment_method: { name: 'Awash Birr', account_label: 'Awash number', active: '1' } }
      expect(PaymentMethod.find_by(name: 'Awash Birr')).to be_present
      get '/admin/payment_methods'
      expect(response.body).to include('Awash Birr')

      sign_out admin
      sign_in rider
      post '/admin/payment_methods', params: { payment_method: { name: 'Sneaky' } }
      expect(PaymentMethod.find_by(name: 'Sneaky')).to be_nil
    end
  end

  describe 'identity verification' do
    def send_document(kind, user: driver, file: photo, number: 'ET-12345')
      post '/api/v1/me/identity', params: { kind:, number:, image: file }, headers: api_headers(user)
    end

    it 'takes a photo of each document and waits for staff' do
      send_document('driver_license')
      expect(response).to have_http_status(:created), response.body
      statuses = json['user']['identity'].to_h { |doc| [doc['kind'], doc['status']] }
      expect(statuses).to eq('driver_license' => 'pending', 'national_id' => 'missing')
      expect(response.body).not_to include('fake jpeg')
      expect(driver.reload).not_to be_verified
    end

    it 'refuses files that are not photos, unknown kinds and missing numbers' do
      send_document('driver_license', file: Rack::Test::UploadedFile.new(StringIO.new('%PDF'), 'application/pdf', true, original_filename: 'x.pdf'))
      expect(response).to have_http_status(:unprocessable_entity)
      send_document('passport')
      expect(response).to have_http_status(:unprocessable_entity)
      send_document('national_id', number: '')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(IdentityDocument.count).to eq 0
    end

    it 'verifies the person when staff approve both documents, and tells them' do
      send_document('driver_license')
      send_document('national_id')
      sign_in admin
      get '/admin/identity_documents'
      expect(response.body).to include('Dawit Driver')

      license, national = driver.identity_documents.order(:kind).to_a
      get "/admin/identity_documents/#{license.id}/image"
      expect(response.media_type).to eq 'image/jpeg'
      expect(response.headers['Cache-Control']).to include('no-store')

      patch "/admin/identity_documents/#{license.id}/approve"
      expect(driver.reload).not_to be_verified
      patch "/admin/identity_documents/#{national.id}/approve"
      expect(driver.reload).to be_verified
      expect(driver.notifications.pluck(:kind)).to eq %w[identity_approved identity_approved]
      expect(driver.notifications.last.body).to include('National ID')
    end

    it 'takes the badge away when a document is rejected or replaced' do
      send_document('driver_license')
      send_document('national_id')
      driver.identity_documents.each { |doc| doc.approve!(by: admin) }
      expect(driver.reload).to be_verified

      sign_in admin
      patch "/admin/identity_documents/#{driver.identity_documents.first.id}/reject", params: { reason: 'Photo is blurred' }
      expect(driver.reload).not_to be_verified
      expect(driver.notifications.last.body).to include('Photo is blurred')

      sign_out admin
      send_document('driver_license')
      expect(driver.identity_documents.find_by(kind: 'driver_license')).to be_pending
    end

    it 'keeps the pictures away from everyone but staff' do
      send_document('national_id')
      document = driver.identity_documents.first
      sign_in rider
      get "/admin/identity_documents/#{document.id}/image"
      expect(response).to redirect_to(root_path)
    end
  end
end
