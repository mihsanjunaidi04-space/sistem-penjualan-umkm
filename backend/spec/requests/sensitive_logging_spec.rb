# frozen_string_literal: true

require 'rails_helper'
require 'base64'
require 'openssl'

RSpec.describe 'Sensitive Request Logging Security', type: :request do
  def with_captured_application_logs
    original_logger = Rails.logger
    original_active_record_logger = ActiveRecord::Base.logger
    output = StringIO.new
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(output))
    logger.level = Logger::DEBUG
    Rails.logger = logger
    ActiveRecord::Base.logger = logger
    yield output
  ensure
    Rails.logger = original_logger
    ActiveRecord::Base.logger = original_active_record_logger
  end

  it 'filters Authorization headers from request logging' do
    user = User.create!(name: 'Logging User', email: 'logging@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: user.id, role: user.role, email: user.email })
    authorization_header = "Bearer #{token}"

    with_captured_application_logs do |output|
      get '/auth/me', headers: { 'Authorization' => authorization_header }
      expect(response).to have_http_status(:ok)
      log_output = output.string
      expect(log_output).not_to include(authorization_header)
      expect(log_output).not_to include(token)
      expect(log_output).not_to include(user.email)
    end
  end

  it 'filters sensitive data from admin endpoints' do
    admin = User.create!(name: 'Admin User', email: 'admin-sensitive@example.com', password: 'password123', role: 'admin')
    token = JwtService.encode({ user_id: admin.id, role: admin.role, email: admin.email })
    authorization_header = "Bearer #{token}"

    with_captured_application_logs do |output|
      get '/auth/admin', headers: { 'Authorization' => authorization_header }
      expect(response).to have_http_status(:ok)
      log_output = output.string
      expect(log_output).not_to include(authorization_header)
      expect(log_output).not_to include(token)
      expect(log_output).not_to include(admin.email)
      expect(log_output).not_to include(admin.name)
    end
  end

  it 'filters sensitive data from customer endpoints' do
    customer = User.create!(name: 'Customer User', email: 'customer-sensitive@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: customer.id, role: customer.role, email: customer.email })
    authorization_header = "Bearer #{token}"

    with_captured_application_logs do |output|
      get '/auth/customer', headers: { 'Authorization' => authorization_header }
      expect(response).to have_http_status(:ok)
      log_output = output.string
      expect(log_output).not_to include(authorization_header)
      expect(log_output).not_to include(token)
      expect(log_output).not_to include(customer.email)
      expect(log_output).not_to include(customer.name)
    end
  end

  it 'filters sensitive data from logout endpoint' do
    user = User.create!(name: 'Logout User', email: 'logout-sensitive@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: user.id, role: user.role, email: user.email })
    authorization_header = "Bearer #{token}"

    with_captured_application_logs do |output|
      delete '/auth/logout', headers: { 'Authorization' => authorization_header }
      expect(response).to have_http_status(:ok)
      log_output = output.string
      expect(log_output).not_to include(authorization_header)
      expect(log_output).not_to include(token)
      expect(log_output).not_to include(user.email)
      expect(log_output).not_to include(user.name)
    end
  end

  it 'verifies JWT service error logging does not expose secrets' do
    invalid_token = 'invalid.token.value'

    with_captured_application_logs do |output|
      get '/auth/me', headers: { 'Authorization' => "Bearer #{invalid_token}" }
      expect(response).to have_http_status(:unauthorized)
      log_output = output.string
      expect(log_output).not_to include(invalid_token)
      expect(log_output).not_to include('Bearer')
      expect(log_output).not_to include(JwtService.secret_key)
    end
  end

  it 'verifies token revocation logging does not expose sensitive data' do
    user = User.create!(name: 'Revocation User', email: 'revocation@example.com', password: 'password123', role: 'customer')
    token = JwtService.encode({ user_id: user.id, role: user.role, email: user.email })
    claims = JwtService.decode(token)

    with_captured_application_logs do |output|
      JwtService.revoke(token, claims)
      log_output = output.string
      expect(log_output).not_to include(token)
      expect(log_output).not_to include(user.email)
      expect(log_output).not_to include(user.name)
      expect(log_output).not_to include(JwtService.secret_key)
    end
  end
end
