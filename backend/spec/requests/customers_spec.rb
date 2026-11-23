# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Customer Profile API', type: :request do
  def auth_headers(user)
    {
      'Authorization' => "Bearer #{JwtService.encode({ user_id: user.id, role: user.role, email: user.email })}"
    }
  end

  def create_user(attributes = {})
    User.create!(
      name: 'Test User',
      email: "test-#{SecureRandom.hex(4)}@example.com",
      password: 'password123',
      password_confirmation: 'password123',
      role: 'customer'
    ).tap { |u| attributes.each { |k, v| u.update_column(k, v) } }
  end

  describe 'GET /auth/me' do
    it 'returns current user profile' do
      user = create_user
      get '/auth/me', headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be(true)
      expect(json['data']['user']['id']).to eq(user.id)
      expect(json['data']['user']['email']).to eq(user.email)
      expect(json['data']['user']['name']).to eq(user.name)
      expect(json['data']['user']['role']).to eq('customer')
    end

    it 'rejects unauthenticated request' do
      get '/auth/me'
      expect(response).to have_http_status(:unauthorized)
      json = JSON.parse(response.body)
      expect(json['success']).to be(false)
    end
  end

  describe 'PATCH /auth/profile' do
    it 'updates user name' do
      user = create_user(name: 'Old Name')
      patch '/auth/profile', params: { name: 'New Name' }, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be(true)
      expect(json['data']['user']['name']).to eq('New Name')
    end

    it 'does not change role' do
      user = create_user(role: 'customer')
      patch '/auth/profile', params: { role: 'admin' }, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['data']['user']['role']).to eq('customer')
    end

    it 'does not change is_active' do
      user = create_user(is_active: true)
      patch '/auth/profile', params: { is_active: false }, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['data']['user']['is_active']).to be(true)
    end

    it 'rejects unauthenticated request' do
      patch '/auth/profile', params: { name: 'New Name' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows an authenticated admin to access their own profile' do
      admin = create_user(role: 'admin')
      patch '/auth/profile', params: { name: 'Admin Name' }, headers: auth_headers(admin)
      # Admin can still access /auth/profile since it uses authenticate_user! not require_customer!
      # But role should not change
      json = JSON.parse(response.body)
      expect(json['data']['user']['role']).to eq('admin')
    end
  end
end
