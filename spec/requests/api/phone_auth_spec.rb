# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API phone registration and driver/passenger mode' do
  let(:issuer) { APP_CONFIG.neon_auth.issuer }
  let(:stand_in) { 'p251911223344@phone.icare.invalid' }
  let(:neon_user) { { 'id' => 'neon-phone-1', 'email' => stand_in, 'name' => 'Abebe Bikila', 'image' => nil } }

  def stub_neon(path, status: 200, body: {})
    stub_request(:post, "#{issuer}#{path}").to_return(status:, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe PhoneLogin do
    it 'accepts the ways Ethiopians write a mobile number' do
      ['0911 22 33 44', '911223344', '251911223344', '+251 911 223 344', '0911-223-344'].each do |written|
        expect(described_class.normalize(written)).to eq '+251911223344'
      end
      expect(described_class.normalize('0711223344')).to eq '+251711223344'
    end

    it 'rejects numbers that are not Ethiopian mobiles' do
      ['0811223344', '091122334', '+15551234567', 'abc', ''].each { |written| expect(described_class.normalize(written)).to be_nil }
    end

    it 'maps a typed login to the address the sign-in service knows' do
      expect(described_class.login_email('0911 22 33 44')).to eq 'p251911223344@phone.icare.invalid'
      expect(described_class.login_email(' Abebe@Example.com ')).to eq 'abebe@example.com'
      expect(described_class.login_email('hello')).to be_nil
    end
  end

  it 'registers with a phone number and the chosen role' do
    stub_neon('/sign-up/email', body: { 'user' => neon_user })
    stub_neon('/sign-in/email', body: { 'user' => neon_user })

    post '/api/v1/auth/sign_up', params: { name: 'Abebe Bikila', phone: '0911 22 33 44', password: 'secret-pass', app_mode: 'driver' }

    expect(response).to have_http_status(:created), response.body
    expect(json['user']).to include('phone' => '+251911223344', 'app_mode' => 'driver', 'phone_account' => true, 'email' => nil)
    expect(User.last).to have_attributes(phone: '+251911223344', app_mode: 'driver', email: stand_in)
    expect(WebMock).to have_requested(:post, "#{issuer}/sign-up/email").with(body: hash_including('email' => stand_in))
  end

  it 'defaults to passenger and refuses a number that is not an Ethiopian mobile' do
    stub_neon('/sign-up/email', body: { 'user' => neon_user })
    stub_neon('/sign-in/email', body: { 'user' => neon_user })
    post '/api/v1/auth/sign_up', params: { name: 'Abebe', phone: '0911223344', password: 'secret-pass', app_mode: 'pilot' }
    expect(json['user']['app_mode']).to eq 'passenger'

    post '/api/v1/auth/sign_up', params: { name: 'Abebe', phone: '12345', password: 'secret-pass' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json['error']['code']).to eq 'invalid_phone'
  end

  it 'says so when the number already has an account' do
    stub_neon('/sign-up/email', status: 422, body: { 'message' => 'User already exists. Use another email.' })
    post '/api/v1/auth/sign_up', params: { name: 'Abebe', phone: '0911223344', password: 'secret-pass' }
    expect(json['error']).to include('code' => 'phone_taken')
    expect(json['error']['message']).not_to include('email')
  end

  it 'signs in with the phone number, or still with an email address' do
    stub_neon('/sign-in/email', body: { 'user' => neon_user })
    post '/api/v1/auth/sign_in', params: { login: '+251911223344', password: 'secret-pass' }
    expect(response).to have_http_status(:ok)
    expect(WebMock).to have_requested(:post, "#{issuer}/sign-in/email").with(body: hash_including('email' => stand_in))

    post '/api/v1/auth/sign_in', params: { login: 'abebe@example.com', password: 'secret-pass' }
    expect(WebMock).to have_requested(:post, "#{issuer}/sign-in/email").with(body: hash_including('email' => 'abebe@example.com'))

    post '/api/v1/auth/sign_in', params: { login: 'not a login', password: 'secret-pass' }
    expect(json['error']['code']).to eq 'invalid_login'
  end

  it 'switches between passenger and driver' do
    user = create(:user)
    patch '/api/v1/me', params: { user: { app_mode: 'driver' } }, headers: api_headers(user)
    expect(json['user']['app_mode']).to eq 'driver'
    expect(user.reload).to be_driver_mode

    patch '/api/v1/me', params: { user: { app_mode: 'captain' } }, headers: api_headers(user)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'never tries to email a phone account' do
    message = Mail::Message.new(to: stand_in)
    PhoneLoginMailInterceptor.delivering_email(message)
    expect(message.perform_deliveries).to be false

    real = Mail::Message.new(to: 'abebe@example.com')
    PhoneLoginMailInterceptor.delivering_email(real)
    expect(real.perform_deliveries).not_to be false
  end
end

RSpec.describe 'API phone registration with an SMS code' do
  let(:issuer) { APP_CONFIG.neon_auth.issuer }
  let(:neon_user) { { 'id' => 'neon-phone-2', 'email' => 'p251911223344@phone.icare.invalid', 'name' => 'Abebe', 'image' => nil } }
  let(:challenge_url) { %r{https://api.afromessage.com/api/challenge} }
  let(:verify_url) { %r{https://api.afromessage.com/api/verify} }

  before do
    allow(AfroMessageClient).to receive(:token).and_return('afro-token')
    stub_request(:get, challenge_url).to_return(body: { acknowledge: 'success', response: { code: '123456', verificationId: 'ver-1', to: '+251911223344' } }.to_json)
    stub_request(:post, "#{issuer}/sign-up/email").to_return(body: { 'user' => neon_user }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:post, "#{issuer}/sign-in/email").to_return(body: { 'user' => neon_user }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def sign_up(code: '123456', verification_id: 'ver-1')
    post '/api/v1/auth/sign_up', params: { name: 'Abebe', phone: '0911223344', password: 'secret-pass', app_mode: 'driver', verification_id:, code: }
  end

  it 'tells the app that codes are on' do
    get '/api/v1/config'
    expect(json['phone_verification']).to be true
  end

  it 'texts a six-digit code and never reveals it' do
    post '/api/v1/auth/send_code', params: { phone: '0911 22 33 44' }

    expect(response).to have_http_status(:created)
    expect(json).to eq('verification_id' => 'ver-1', 'expires_in' => 600, 'code_length' => 6)
    expect(response.body).not_to include('123456')
    expect(WebMock).to have_requested(:get, challenge_url).with(query: hash_including('to' => '+251911223344', 'len' => '6', 'ttl' => '600'), headers: { 'Authorization' => 'Bearer afro-token' })
    expect(PhoneVerification.last).to have_attributes(phone: '+251911223344', verification_id: 'ver-1')
  end

  it 'does not text a number that already has an account, a bad number, or one that asked too often' do
    create(:user, email: 'p251911223344@phone.icare.invalid')
    post '/api/v1/auth/send_code', params: { phone: '0911223344' }
    expect(json['error']['code']).to eq 'phone_taken'

    post '/api/v1/auth/send_code', params: { phone: '123' }
    expect(json['error']['code']).to eq 'invalid_phone'

    ids = %w[ver-a ver-b ver-c].map { |id| { body: { acknowledge: 'success', response: { verificationId: id } }.to_json } }
    stub_request(:get, challenge_url).to_return(*ids)
    3.times { post '/api/v1/auth/send_code', params: { phone: '0922334455' } }
    post '/api/v1/auth/send_code', params: { phone: '0922334455' }
    expect(response).to have_http_status(:too_many_requests)
    expect(WebMock).to have_requested(:get, challenge_url).times(3)
  end

  it 'creates the account only with the right code, and marks the number verified' do
    post '/api/v1/auth/send_code', params: { phone: '0911223344' }
    stub_request(:get, verify_url).to_return(body: { acknowledge: 'success', response: { phone: '+251911223344' } }.to_json)

    sign_up
    expect(response).to have_http_status(:created), response.body
    expect(json['user']).to include('phone_verified' => true, 'app_mode' => 'driver')
    expect(WebMock).to have_requested(:get, verify_url).with(query: hash_including('vc' => 'ver-1', 'code' => '123456'))

    sign_up # the same code cannot be used twice
    expect(json['error']['code']).to eq 'invalid_code'
  end

  it 'refuses a wrong code, a missing code, and stops after five guesses' do
    post '/api/v1/auth/send_code', params: { phone: '0911223344' }
    stub_request(:get, verify_url).to_return(body: { acknowledge: 'error', response: { errors: ['Invalid code'] } }.to_json)

    expect { sign_up(code: '000000') }.not_to change(User, :count)
    expect(json['error']['code']).to eq 'invalid_code'
    expect(WebMock).not_to have_requested(:post, "#{issuer}/sign-up/email")

    sign_up(verification_id: nil, code: nil)
    expect(json['error']['code']).to eq 'invalid_code'

    6.times { sign_up(code: '111111') }
    expect(WebMock).to have_requested(:get, verify_url).times(5)
  end

  it 'says so when the SMS service is down' do
    stub_request(:get, challenge_url).to_return(status: 500, body: 'oops')
    post '/api/v1/auth/send_code', params: { phone: '0911223344' }
    expect(response).to have_http_status(:bad_gateway)
    expect(json['error']['code']).to eq 'sms_unavailable'
  end
end
