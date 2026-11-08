# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API auth' do
  let(:issuer) { APP_CONFIG.neon_auth.issuer }
  let(:neon_user) { { 'id' => 'neon-uuid-1', 'email' => 'abebe@example.com', 'name' => 'Abebe Bikila', 'image' => nil } }

  def stub_neon(path, status: 200, body: {})
    stub_request(:post, "#{issuer}#{path}").to_return(status:, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'POST /api/v1/auth/sign_in' do
    it 'signs in through Neon Auth, creates the person on first use and returns a token' do
      stub_neon('/sign-in/email', body: { 'token' => 'neon-session', 'user' => neon_user })

      expect { post '/api/v1/auth/sign_in', params: { email: 'Abebe@Example.com', password: 'secret-pass' } }.to change(User, :count).by(1).and change(ApiToken, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(json['token']).to be_present
      expect(json['user']).to include('email' => 'abebe@example.com', 'name' => 'Abebe Bikila')
      expect(User.last).to have_attributes(provider: 'neon', uid: 'neon-uuid-1')
      expect(WebMock).to have_requested(:post, "#{issuer}/sign-in/email").with(headers: { 'Origin' => NeonAuthClient.origin }, body: hash_including('email' => 'abebe@example.com'))
    end

    it 'reuses an existing person and never stores the raw token' do
      create(:user, provider: 'neon', uid: 'neon-uuid-1', email: 'old@example.com')
      stub_neon('/sign-in/email', body: { 'user' => neon_user })

      expect { post '/api/v1/auth/sign_in', params: { email: 'abebe@example.com', password: 'secret-pass' } }.not_to change(User, :count)

      expect(User.find_by(uid: 'neon-uuid-1').email).to eq 'abebe@example.com'
      expect(ApiToken.pluck(:token_digest)).not_to include(json['token'])
      expect(ApiToken.authenticate(json['token'])).to be_present
    end

    it 'rejects wrong credentials with the provider message' do
      stub_neon('/sign-in/email', status: 401, body: { 'message' => 'Invalid email or password' })

      post '/api/v1/auth/sign_in', params: { email: 'abebe@example.com', password: 'nope' }

      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to include('code' => 'auth_failed', 'message' => 'Invalid email or password')
      expect(ApiToken.count).to eq 0
    end

    it 'does not sign in a banned person' do
      create(:user, provider: 'neon', uid: 'neon-uuid-1', banned: true)
      stub_neon('/sign-in/email', body: { 'user' => neon_user })

      post '/api/v1/auth/sign_in', params: { email: 'abebe@example.com', password: 'secret-pass' }

      expect(response).to have_http_status(:forbidden)
      expect(ApiToken.count).to eq 0
    end

    it 'reports an unavailable sign-in service' do
      stub_request(:post, "#{issuer}/sign-in/email").to_timeout

      post '/api/v1/auth/sign_in', params: { email: 'abebe@example.com', password: 'secret-pass' }

      expect(response).to have_http_status(:service_unavailable)
    end

    it 'needs an email and a password' do
      post '/api/v1/auth/sign_in', params: { email: 'abebe@example.com' }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'limits repeated attempts' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      stub_neon('/sign-in/email', status: 401, body: { 'message' => 'Invalid email or password' })

      Api::V1::AuthController::LIMIT.times { post '/api/v1/auth/sign_in', params: { email: 'a@example.com', password: 'x' } }
      expect(response).to have_http_status(:unauthorized)

      post '/api/v1/auth/sign_in', params: { email: 'a@example.com', password: 'x' }
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'POST /api/v1/auth/sign_up' do
    it 'creates the Neon account, signs in and returns a token' do
      stub_neon('/sign-up/email', body: { 'user' => neon_user })
      stub_neon('/sign-in/email', body: { 'user' => neon_user })

      post '/api/v1/auth/sign_up', params: { name: 'Abebe Bikila', email: 'abebe@example.com', password: 'secret-pass' }

      expect(response).to have_http_status(:created)
      expect(json['token']).to be_present
      expect(WebMock).to have_requested(:post, "#{issuer}/sign-up/email").once
    end

    it 'passes on a duplicate-account error' do
      stub_neon('/sign-up/email', status: 422, body: { 'message' => 'User already exists. Use another email.' })

      post '/api/v1/auth/sign_up', params: { name: 'Abebe', email: 'abebe@example.com', password: 'secret-pass' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']['message']).to include('already exists')
    end
  end

  describe 'tokens' do
    let(:user) { create(:user) }

    it 'requires a valid bearer token' do
      get '/api/v1/me'
      expect(response).to have_http_status(:unauthorized)

      get '/api/v1/me', headers: { 'Authorization' => 'Bearer nonsense' }
      expect(response).to have_http_status(:unauthorized)

      get '/api/v1/me', headers: api_headers(user)
      expect(response).to have_http_status(:ok)
    end

    it 'rejects expired tokens and banned people' do
      headers = api_headers(user)
      ApiToken.last.update_columns(expires_at: 1.minute.ago)
      get '/api/v1/me', headers: headers
      expect(response).to have_http_status(:unauthorized)

      headers = api_headers(user)
      user.update!(banned: true)
      get '/api/v1/me', headers: headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'signs out by revoking only that device token' do
      headers = api_headers(user)
      other = api_headers(user)

      delete '/api/v1/auth/sign_out', headers: headers
      expect(response).to have_http_status(:no_content)

      get '/api/v1/me', headers: headers
      expect(response).to have_http_status(:unauthorized)
      get '/api/v1/me', headers: other
      expect(response).to have_http_status(:ok)
    end
  end
end
