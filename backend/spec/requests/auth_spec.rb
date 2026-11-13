# frozen_string_literal: true

require 'rails_helper'
require 'base64'
require 'openssl'

RSpec.describe 'Authentication API', type: :request do
  def auth_headers(user)
    {
      'Authorization' => "Bearer #{JwtService.encode({ user_id: user.id, role: user.role, email: user.email })}"
    }
  end

  def capture_security_events
    events = []
    allow(Rails.logger).to receive(:info) do |message|
      events << JSON.parse(message) if message.is_a?(String)
    end
    events
  end

  it 'registers a customer and returns a JWT token' do
    events = []
    allow(Rails.logger).to receive(:info) { |message| events << JSON.parse(message) if message.is_a?(String) }

    post '/auth/register', params: {
      name: 'Alice Customer',
      email: 'alice@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    }, as: :json

    expect(response).to have_http_status(:created)
    json = JSON.parse(response.body)
    expect(json['success']).to be(true)
    expect(json['data']['user']['role']).to eq('customer')
    expect(json['data']['token']).to be_present

    event = events.find { |entry| entry['event'] == 'auth.register.success' }
    expect(event).to include('event' => 'auth.register.success', 'user_id' => json['data']['user']['id'])
    expect(event.to_json).not_to include('alice@example.com', 'password123', json['data']['token'], 'Authorization', JwtService.secret_key)
  end

  it 'rejects invalid registration data and duplicate email addresses' do
    events = []
    allow(Rails.logger).to receive(:info) { |message| events << JSON.parse(message) if message.is_a?(String) }

    post '/auth/register', params: {
      name: '',
      email: 'invalid-email',
      password: 'short',
      password_confirmation: 'different'
    }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)['error']['code']).to eq('VALIDATION_ERROR')

    User.create!(name: 'Existing User', email: 'existing@example.com', password: 'password123', role: 'customer')
    post '/auth/register', params: {
      name: 'Duplicate User',
      email: 'existing@example.com',
      password: 'password123',
      password_confirmation: 'password123'
    }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(events.none? { |entry| entry['event'] == 'auth.register.success' }).to be(true)
  end

  it 'logs in and returns the current user identity' do
    user = User.create!(name: 'Bob Customer', email: 'bob@example.com', password: 'password123', role: 'customer')

    post '/auth/login', params: {
      email: user.email,
      password: 'password123'
    }, as: :json

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json['success']).to be(true)
    expect(json['data']['user']['email']).to eq(user.email)

    get '/auth/me', headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    me_json = JSON.parse(response.body)
    expect(me_json['data']['user']['id']).to eq(user.id)
  end

  it 'rejects invalid login credentials' do
    User.create!(name: 'Login User', email: 'login@example.com', password: 'password123', role: 'customer')

    post '/auth/login', params: { email: 'login@example.com', password: 'wrong-password' }, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('INVALID_CREDENTIALS')
  end

  it 'rejects inactive accounts at login with the same generic response and no token' do
    inactive_user = User.create!(name: 'Inactive User', email: 'inactive@example.com', password: 'password123', role: 'customer', is_active: false)

    post '/auth/login', params: { email: inactive_user.email, password: 'password123' }, as: :json

    inactive_response_body = response.body
    inactive_response = JSON.parse(inactive_response_body)

    expect(response).to have_http_status(:unauthorized)
    expect(inactive_response['error']['code']).to eq('INVALID_CREDENTIALS')
    expect(inactive_response['error']['message']).to eq('Email atau password tidak valid.')
    expect(inactive_response_body).not_to include('ACCOUNT_INACTIVE')
    expect(inactive_response_body).not_to include(inactive_user.email)
    expect(inactive_response.dig('data', 'token')).to be_nil

    post '/auth/login', params: { email: inactive_user.email, password: 'wrong-password' }, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).to eq(inactive_response_body)

    get '/auth/me', headers: auth_headers(inactive_user)

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('ACCOUNT_INACTIVE')
  end

  it 'rejects missing, invalid, and expired tokens' do
    get '/auth/me'
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('AUTHENTICATION_REQUIRED')

    get '/auth/me', headers: { 'Authorization' => 'Bearer invalid.token.value' }
    expect(response).to have_http_status(:unauthorized)

    invalid_body = JSON.parse(response.body)
    expect(invalid_body['error']['code']).to eq('INVALID_TOKEN')

    user = User.create!(name: 'Expired User', email: 'expired@example.com', password: 'password123', role: 'customer')
    expired_token = JwtService.encode({ user_id: user.id }, 1.minute.ago.to_i)
    get '/auth/me', headers: { 'Authorization' => "Bearer #{expired_token}" }
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('INVALID_TOKEN')
  end

  it 'logs one safe invalid JWT event for a malformed or incorrectly signed token' do
    events = capture_security_events
    invalid_token = 'malformed.jwt.value'

    get '/auth/me', headers: { 'Authorization' => "Bearer #{invalid_token}" }

    expect(response).to have_http_status(:unauthorized)
    invalid_events = events.select { |entry| entry['event'] == 'auth.jwt.invalid' }
    expect(invalid_events.size).to eq(1)
    expect(invalid_events.first.to_json).not_to include(invalid_token, 'Authorization', JwtService.secret_key, 'password', '@')
  end

  it 'logs expired JWTs distinctly without changing the response' do
    events = capture_security_events
    user = User.create!(name: 'Expired Event User', email: 'expired-event@example.com', password: 'password123', role: 'customer')
    expired_token = JwtService.encode({ user_id: user.id }, 1.minute.ago.to_i)

    get '/auth/me', headers: { 'Authorization' => "Bearer #{expired_token}" }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('INVALID_TOKEN')
    expect(events.count { |entry| entry['event'] == 'auth.jwt.expired' }).to eq(1)
  end

  it 'rejects tokens missing required claims' do
    user = User.create!(name: 'Required Claims User', email: 'required-claims@example.com', password: 'password123', role: 'customer')
    secret = JwtService.secret_key

    {
      'exp' => { user_id: user.id, jti: SecureRandom.uuid },
      'jti' => { user_id: user.id, exp: 1.hour.from_now.to_i },
      'user_id' => { jti: SecureRandom.uuid, exp: 1.hour.from_now.to_i }
    }.each do |missing_claim, claims|
      token = JWT.encode(claims, secret, JwtService::ALGORITHM)

      get '/auth/me', headers: { 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:unauthorized), "expected token missing #{missing_claim} to be rejected"
      expect(JSON.parse(response.body)['error']['code']).to eq('INVALID_TOKEN')
    end
  end

  it 'rejects tokens with a non-numeric exp claim' do
    user = User.create!(name: 'Non Numeric Exp User', email: 'non-numeric-exp@example.com', password: 'password123', role: 'customer')
    claims = { user_id: user.id, jti: SecureRandom.uuid, exp: 'not-a-timestamp' }
    header = Base64.urlsafe_encode64({ alg: JwtService::ALGORITHM, typ: 'JWT' }.to_json, padding: false)
    payload = Base64.urlsafe_encode64(claims.to_json, padding: false)
    signing_input = "#{header}.#{payload}"
    signature = Base64.urlsafe_encode64(OpenSSL::HMAC.digest(OpenSSL::Digest::SHA256.new, JwtService.secret_key, signing_input), padding: false)
    token = "#{signing_input}.#{signature}"

    get '/auth/me', headers: { 'Authorization' => "Bearer #{token}" }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('INVALID_TOKEN')
  end

  it 'rejects tokens with invalid signatures and algorithms' do
    user = User.create!(name: 'JWT Validation User', email: 'jwt-validation@example.com', password: 'password123', role: 'customer')
    claims = { user_id: user.id, jti: SecureRandom.uuid, exp: 1.hour.from_now.to_i }

    invalid_signature = JWT.encode(claims, 'wrong-secret', JwtService::ALGORITHM)
    get '/auth/me', headers: { 'Authorization' => "Bearer #{invalid_signature}" }
    expect(response).to have_http_status(:unauthorized)

    wrong_algorithm = JWT.encode(claims, JwtService.secret_key, 'HS384')
    get '/auth/me', headers: { 'Authorization' => "Bearer #{wrong_algorithm}" }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'accepts a valid token and rejects a revoked token' do
    events = capture_security_events
    user = User.create!(name: 'Valid JWT User', email: 'valid-jwt@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: user.id, role: user.role })

    get '/auth/me', headers: { 'Authorization' => "Bearer #{token}" }
    expect(response).to have_http_status(:ok)

    claims = JwtService.decode(token)
    JwtService.revoke(token, claims)

    get '/auth/me', headers: { 'Authorization' => "Bearer #{token}" }
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('INVALID_TOKEN')
    expect(events.count { |entry| entry['event'] == 'auth.jwt.revoked' }).to eq(1)
  end

  it 'logs revocation storage failure and remains fail-closed' do
    events = capture_security_events
    user = User.create!(name: 'Revocation Event User', email: 'revocation-event@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: user.id, role: user.role })
    allow(JwtRevocation).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)

    get '/auth/me', headers: { 'Authorization' => "Bearer #{token}" }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('INVALID_TOKEN')
    expect(events.count { |entry| entry['event'] == 'auth.jwt.revocation_unavailable' }).to eq(1)
    expect(events.join).not_to include(token, 'Authorization', 'ConnectionNotEstablished', 'password', user.email)
  end

  it 'logs missing users and inactive accounts after token validation' do
    events = capture_security_events
    missing_user_token = JwtService.encode({ user_id: 999_999, role: 'customer' })
    get '/auth/me', headers: { 'Authorization' => "Bearer #{missing_user_token}" }
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('USER_NOT_FOUND')
    expect(events.count { |entry| entry['event'] == 'auth.jwt.user_missing' }).to eq(1)

    inactive_user = User.create!(name: 'Inactive Event User', email: 'inactive-event@example.com', password: 'password123', role: 'customer', is_active: false)
    inactive_token = JwtService.encode({ user_id: inactive_user.id, role: inactive_user.role })
    get '/auth/me', headers: { 'Authorization' => "Bearer #{inactive_token}" }
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('ACCOUNT_INACTIVE')
    expect(events.count { |entry| entry['event'] == 'auth.jwt.account_inactive' }).to eq(1)
  end

  it 'requires authentication for logout and revokes a logged-out token' do
    events = []
    allow(Rails.logger).to receive(:info) { |message| events << JSON.parse(message) if message.is_a?(String) }

    user = User.create!(name: 'Logout User', email: 'logout@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: user.id, role: user.role })

    delete '/auth/logout'
    expect(response).to have_http_status(:unauthorized)
    expect(events).to include(include('event' => 'auth.logout.failure', 'reason' => 'token_missing'))

    delete '/auth/logout', headers: { 'Authorization' => "Bearer #{token}" }
    expect(response).to have_http_status(:ok)
    success_event = events.find { |entry| entry['event'] == 'auth.logout.success' }
    expect(success_event).to include('event' => 'auth.logout.success', 'user_id' => user.id)
    expect(success_event.to_json).not_to include(token, 'Authorization', user.email, JwtService.secret_key)

    get '/auth/me', headers: { 'Authorization' => "Bearer #{token}" }
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('INVALID_TOKEN')
  end

  it 'persists revocation in SQLite across a connection reinitialization', use_transactional_fixtures: false do
    token = JwtService.encode({ user_id: 999_999, role: 'customer' })
    claims = JwtService.decode(token)

    JwtService.revoke(token, claims)
    expect(JwtRevocation.where(jti: claims[:jti]).count).to eq(1)

    # Commit this record so a newly initialized SQLite connection can observe it.
    ActiveRecord::Base.connection.execute("COMMIT")
    ActiveRecord::Base.connection_pool.disconnect!
    ActiveRecord::Base.establish_connection(Rails.application.config.database_configuration.fetch(Rails.env))

    expect(JwtService.revoked?(claims)).to be(true)
    expect(JwtRevocation.find_by!(jti: claims[:jti]).expires_at).to be > Time.current
    JwtRevocation.delete_by(jti: claims[:jti])
  end

  it 'treats repeated logout for the same token as idempotent' do
    user = User.create!(name: 'Repeated Logout User', email: 'repeated-logout@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: user.id, role: user.role })

    2.times do
      delete '/auth/logout', headers: { 'Authorization' => "Bearer #{token}" }
      expect(response).to have_http_status(:ok)
    end

    claims = JwtService.decode(token)
    expect(JwtRevocation.where(jti: claims[:jti]).count).to eq(1)
  end

  it 'returns 503 without internal details when revocation cannot be written' do
    events = []
    allow(Rails.logger).to receive(:info) { |message| events << JSON.parse(message) if message.is_a?(String) }

    user = User.create!(name: 'Logout Failure User', email: 'logout-failure@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: user.id, role: user.role })
    allow(JwtRevocation).to receive(:create_or_find_by!).and_raise(ActiveRecord::ConnectionNotEstablished)

    delete '/auth/logout', headers: { 'Authorization' => "Bearer #{token}" }

    expect(response).to have_http_status(:service_unavailable)
    body = JSON.parse(response.body)
    expect(body['success']).to be(false)
    expect(body['error']['code']).to eq('REVOCATION_UNAVAILABLE')
    expect(response.body).not_to include('ConnectionNotEstablished', 'SQLite', 'database')
    expect(events).to include(include('event' => 'auth.logout.failure', 'reason' => 'revocation_failed'))
    expect(events.none? { |entry| entry['event'] == 'auth.logout.success' }).to be(true)
  end

  it 'logs invalid logout tokens without exposing the token' do
    events = []
    allow(Rails.logger).to receive(:info) { |message| events << JSON.parse(message) if message.is_a?(String) }
    invalid_token = 'invalid.logout.token'

    delete '/auth/logout', headers: { 'Authorization' => "Bearer #{invalid_token}" }

    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('INVALID_TOKEN')
    failure_event = events.find { |entry| entry['event'] == 'auth.logout.failure' }
    expect(failure_event).to include('event' => 'auth.logout.failure', 'reason' => 'authentication_failed')
    expect(failure_event.to_json).not_to include(invalid_token, 'Authorization', JwtService.secret_key)
  end

  it 'fails closed when the revocation store cannot be read' do
    user = User.create!(name: 'Unavailable Store User', email: 'unavailable-store@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: user.id, role: user.role })
    claims = JwtService.decode(token)

    allow(JwtRevocation).to receive(:where).and_raise(ActiveRecord::ConnectionNotEstablished)

    expect(JwtService.revoked?(claims)).to be(true)
  end

  it 'does not silently accept a token when revocation cannot be written' do
    user = User.create!(name: 'Write Failure User', email: 'write-failure@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: user.id, role: user.role })
    claims = JwtService.decode(token)

    allow(JwtRevocation).to receive(:create_or_find_by!).and_raise(ActiveRecord::ConnectionNotEstablished)

    expect { JwtService.revoke(token, claims) }.to raise_error(ActiveRecord::ConnectionNotEstablished)
  end

  it 'enforces admin and customer access rules' do
    events = capture_security_events
    customer = User.create!(name: 'Customer Access', email: 'customer-access@example.com', password: 'password123', role: 'customer')
    admin = User.create!(name: 'Admin Access', email: 'admin-access@example.com', password: 'password123', role: 'admin')

    get '/auth/customer', headers: auth_headers(customer)
    expect(response).to have_http_status(:ok)

    get '/auth/admin', headers: auth_headers(customer)
    expect(response).to have_http_status(:forbidden)
    expect(events.count { |entry| entry['event'] == 'auth.authorization.denied' }).to eq(1)

    get '/auth/admin', headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(events.count { |entry| entry['event'] == 'auth.authorization.denied' }).to eq(1)
  end

  it 'does not trust a token role claim over the database user role' do
    customer = User.create!(name: 'Role User', email: 'role-user@example.com', password: 'password123', role: 'customer')

    get '/auth/admin', headers: { 'Authorization' => "Bearer #{JwtService.encode({ user_id: customer.id, role: 'admin' })}" }

    expect(response).to have_http_status(:forbidden)
  end

  describe 'rate limiting' do
    def auth_ip(ip)
      { 'REMOTE_ADDR' => ip }
    end

    it 'rate limits repeated failed logins by IP before bcrypt' do
      stub_const('AuthRateLimiter::LOGIN_IP_LIMIT', 2)
      user = User.create!(name: 'Rate Limited User', email: 'rate-limited@example.com', password: 'password123', role: 'customer')

      2.times do
        post '/auth/login', params: { email: user.email, password: 'wrong-password' }, headers: auth_ip('198.51.100.10'), as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      post '/auth/login', params: { email: user.email, password: 'wrong-password' }, headers: auth_ip('198.51.100.10'), as: :json
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers['Retry-After'].to_i).to be_positive
      expect(JSON.parse(response.body)['error']['code']).to eq('RATE_LIMITED')
    end

    it 'does not hard-lock an account when failures come from different IPs' do
      stub_const('AuthRateLimiter::LOGIN_IP_LIMIT', 1)
      user = User.create!(name: 'Distributed Login User', email: 'distributed-login@example.com', password: 'password123', role: 'customer')

      2.times do |index|
        post '/auth/login', params: { email: user.email, password: 'wrong-password' }, headers: auth_ip("198.51.100.#{20 + index}"), as: :json
        expect(response).to have_http_status(:unauthorized)
      end

      post '/auth/login', params: { email: user.email, password: 'password123' }, headers: auth_ip('198.51.100.22'), as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'applies the IP limit across different email addresses' do
      stub_const('AuthRateLimiter::LOGIN_IP_LIMIT', 1)

      post '/auth/login', params: { email: 'first@example.com', password: 'wrong-password' }, headers: auth_ip('198.51.100.30'), as: :json
      expect(response).to have_http_status(:unauthorized)

      post '/auth/login', params: { email: 'second@example.com', password: 'wrong-password' }, headers: auth_ip('198.51.100.30'), as: :json
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'allows login attempts again after the IP window expires' do
      stub_const('AuthRateLimiter::LOGIN_IP_LIMIT', 1)
      user = User.create!(name: 'Window Recovery User', email: 'window-recovery@example.com', password: 'password123', role: 'customer')
      ip = '198.51.100.35'

      post '/auth/login', params: { email: user.email, password: 'wrong-password' }, headers: auth_ip(ip), as: :json
      expect(response).to have_http_status(:unauthorized)
      post '/auth/login', params: { email: user.email, password: 'wrong-password' }, headers: auth_ip(ip), as: :json
      expect(response).to have_http_status(:too_many_requests)

      counter_key = AuthRateLimiter.send(:key, 'login-ip', ip)
      AuthRateLimitCounter.find_by!(key: counter_key).update!(expires_at: 1.second.ago)

      post '/auth/login', params: { email: user.email, password: 'wrong-password' }, headers: auth_ip(ip), as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'ignores a client-supplied X-Forwarded-For value for the effective IP' do
      stub_const('AuthRateLimiter::REGISTER_IP_LIMIT', 1)
      headers = auth_ip('198.51.100.40').merge('X-Forwarded-For' => '203.0.113.1')
      post '/auth/register', params: { name: 'First', email: 'first-register@example.com', password: 'password123', password_confirmation: 'password123' }, headers: headers, as: :json
      expect(response).to have_http_status(:created)

      headers['X-Forwarded-For'] = '203.0.113.2'
      post '/auth/register', params: { name: 'Second', email: 'second-register@example.com', password: 'password123', password_confirmation: 'password123' }, headers: headers, as: :json
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'returns a generic registration error for duplicate email addresses' do
      User.create!(name: 'Existing Registration User', email: 'existing-registration@example.com', password: 'password123', role: 'customer')

      post '/auth/register', params: { name: 'Duplicate', email: 'existing-registration@example.com', password: 'password123', password_confirmation: 'password123' }, headers: auth_ip('198.51.100.50'), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']['code']).to eq('VALIDATION_ERROR')
      expect(body['error']['details']).to eq({})
      expect(response.body).not_to include('taken')
    end
  end
end
