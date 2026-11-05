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

  it 'rejects invalid or expired tokens' do
    get '/auth/me', headers: { 'Authorization' => 'Bearer invalid.token.value' }
    expect(response).to have_http_status(:unauthorized)

    invalid_body = JSON.parse(response.body)
    expect(invalid_body['error']['code']).to eq('INVALID_TOKEN')
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
end
