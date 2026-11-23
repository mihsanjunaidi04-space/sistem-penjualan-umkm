# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Customer Address API', type: :request do
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

  def address_params
    {
      recipient_name: 'John Doe',
      phone: '081234567890',
      address_line: 'Jl. Contoh No. 123',
      province: 'DKI Jakarta',
      city: 'Jakarta Pusat',
      district: 'Menteng',
      postal_code: '10310',
      notes: 'Depan gedung'
    }
  end

  describe 'GET /customer/addresses' do
    it 'returns only the current user addresses' do
      user = create_user
      other_user = create_user
      own_address = user.addresses.create!(address_params)
      other_address = other_user.addresses.create!(address_params)

      get '/customer/addresses', headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be(true)
      expect(json['data']['addresses'].map { |address| address['id'] }).to eq([ own_address.id ])
      expect(json['data']['addresses'].map { |address| address['id'] }).not_to include(other_address.id)
    end

    it 'returns an empty list when the current user has no addresses' do
      user = create_user

      get '/customer/addresses', headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be(true)
      expect(json['data']['addresses']).to eq([])
    end

    it 'rejects unauthenticated request' do
      get '/customer/addresses'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /customer/addresses' do
    it 'creates a new address' do
      user = create_user
      expect {
        post '/customer/addresses', params: address_params, headers: auth_headers(user)
      }.to change(user.addresses, :count).by(1)
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['success']).to be(true)
      expect(json['data']['address']['recipient_name']).to eq('John Doe')
    end

    it 'sets first address as default' do
      user = create_user
      post '/customer/addresses', params: address_params, headers: auth_headers(user)
      json = JSON.parse(response.body)
      expect(json['data']['address']['is_default']).to be(true)
    end

    it 'does not set as default when explicitly set to false' do
      user = create_user
      post '/customer/addresses', params: address_params.merge(is_default: false), headers: auth_headers(user)
      json = JSON.parse(response.body)
      expect(json['data']['address']['is_default']).to be(false)
    end

    it 'rejects unauthenticated request' do
      post '/customer/addresses', params: address_params
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects invalid address data' do
      user = create_user
      post '/customer/addresses', params: { recipient_name: '' }, headers: auth_headers(user)
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']['code']).to eq('VALIDATION_ERROR')
    end
  end

  describe 'PATCH /customer/addresses/:id' do
    it 'updates address' do
      user = create_user
      address = user.addresses.create!(address_params.merge(is_default: false))
      patch "/customer/addresses/#{address.id}", params: { recipient_name: 'Jane Doe' }, headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['data']['address']['recipient_name']).to eq('Jane Doe')
    end

    it 'cannot update another user address' do
      user = create_user
      other_user = create_user
      address = other_user.addresses.create!(address_params)
      patch "/customer/addresses/#{address.id}", params: { recipient_name: 'Hacker' }, headers: auth_headers(user)
      expect(response).to have_http_status(:not_found)
    end

    it 'rejects unauthenticated request' do
      patch '/customer/addresses/1', params: { recipient_name: 'Hacker' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /customer/addresses/:id' do
    it 'deletes address' do
      user = create_user
      address = user.addresses.create!(address_params)
      expect {
        delete "/customer/addresses/#{address.id}", headers: auth_headers(user)
      }.to change(user.addresses, :count).by(-1)
      expect(response).to have_http_status(:ok)
    end

    it 'cannot delete another user address' do
      user = create_user
      other_user = create_user
      address = other_user.addresses.create!(address_params)
      expect {
        delete "/customer/addresses/#{address.id}", headers: auth_headers(user)
      }.not_to change(other_user.addresses, :count)
      expect(response).to have_http_status(:not_found)
    end

    it 'rejects unauthenticated request' do
      delete '/customer/addresses/1'
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'default address logic' do
    it 'sets first address as default' do
      user = create_user
      post '/customer/addresses', params: address_params, headers: auth_headers(user)
      json = JSON.parse(response.body)
      expect(json['data']['address']['is_default']).to be(true)
    end

    it 'does not set as default when explicitly set to false' do
      user = create_user
      post '/customer/addresses', params: address_params.merge(is_default: false), headers: auth_headers(user)
      json = JSON.parse(response.body)
      expect(json['data']['address']['is_default']).to be(false)
    end

    it 'makes second address default when explicitly set' do
      user = create_user
      post '/customer/addresses', params: address_params, headers: auth_headers(user)
      post '/customer/addresses', params: address_params.merge(is_default: true), headers: auth_headers(user)
      json = JSON.parse(response.body)
      expect(json['data']['address']['is_default']).to be(true)
      # First address should no longer be default
      first_address = user.addresses.first
      expect(first_address.reload.is_default).to be(false)
    end

    it 'makes another address default when default is deleted' do
      user = create_user
      addr1 = user.addresses.create!(address_params.merge(is_default: true))
      addr2 = user.addresses.create!(address_params.merge(is_default: false))
      delete "/customer/addresses/#{addr1.id}", headers: auth_headers(user)
      addr2.reload
      expect(addr2.is_default).to be(true)
    end
  end
end
