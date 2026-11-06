# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Authentication API', type: :request do
  def auth_headers(user)
    {
      'Authorization' => "Bearer #{JwtService.encode({ user_id: user.id, role: user.role, email: user.email })}"
    }
  end

  it 'registers a customer and returns a JWT token' do
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
  end

  it 'rejects invalid registration data and duplicate email addresses' do
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

  it 'requires authentication for logout and revokes a logged-out token' do
    user = User.create!(name: 'Logout User', email: 'logout@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: user.id, role: user.role })

    delete '/auth/logout'
    expect(response).to have_http_status(:unauthorized)

    delete '/auth/logout', headers: { 'Authorization' => "Bearer #{token}" }
    expect(response).to have_http_status(:ok)

    get '/auth/me', headers: { 'Authorization' => "Bearer #{token}" }
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']['code']).to eq('INVALID_TOKEN')
  end

  it 'keeps a revocation after the cache is initialized again' do
    user = User.create!(name: 'Persistent Logout User', email: 'persistent-logout@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: user.id, role: user.role })
    claims = JwtService.decode(token)

    JwtService.revoke(token, claims)
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    expect(JwtService.revoked?(claims)).to be(true)
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

    allow(JwtRevocation).to receive(:create!).and_raise(ActiveRecord::ConnectionNotEstablished)

    expect { JwtService.revoke(token, claims) }.to raise_error(ActiveRecord::ConnectionNotEstablished)
  end

  it 'enforces admin and customer access rules' do
    customer = User.create!(name: 'Customer Access', email: 'customer-access@example.com', password: 'password123', role: 'customer')
    admin = User.create!(name: 'Admin Access', email: 'admin-access@example.com', password: 'password123', role: 'admin')

    get '/auth/customer', headers: auth_headers(customer)
    expect(response).to have_http_status(:ok)

    get '/auth/admin', headers: auth_headers(customer)
    expect(response).to have_http_status(:forbidden)

    get '/auth/admin', headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
  end

  it 'does not trust a token role claim over the database user role' do
    customer = User.create!(name: 'Role User', email: 'role-user@example.com', password: 'password123', role: 'customer')

    get '/auth/admin', headers: { 'Authorization' => "Bearer #{JwtService.encode({ user_id: customer.id, role: 'admin' })}" }

    expect(response).to have_http_status(:forbidden)
  end
end
