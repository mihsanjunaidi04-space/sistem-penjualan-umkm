require 'rails_helper'
require 'stringio'

RSpec.describe 'Logging security', type: :request do
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

  it 'filters sensitive request values and does not emit them in actual request logs' do
    email = 'sentinel.logging@example.com'
    password = 'SentinelPassword-123'
    confirmation = password
    token = 'sentinel.jwt.token'
    authorization = "Bearer #{token}"

    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(
      email: email,
      password: password,
      password_confirmation: confirmation,
      token: token
    )

    expect(filtered.values).to all(eq('[FILTERED]'))

    with_captured_application_logs do |output|
      post '/auth/register', params: {
        name: 'Logging Sentinel',
        email: email,
        password: password,
        password_confirmation: confirmation
      }, headers: { 'Authorization' => authorization }, as: :json

      expect(response).to have_http_status(:created)
      log_output = output.string
      expect(log_output).not_to include(email, password, confirmation, token, authorization, JwtService.secret_key)
    end
  end

  it 'keeps authentication and authorization results when the structured logger fails' do
    user = User.create!(name: 'Logger Failure User', email: 'logger-failure@example.test', password: 'password123', role: 'customer')
    token = JwtService.encode(user_id: user.id, role: user.role)
    allow(Rails.logger).to receive(:info).and_wrap_original do |original, message, *args|
      raise IOError, 'logger unavailable' if message.to_s.include?('"event"')

      original.call(message, *args)
    end
    warnings = []
    allow(Kernel).to receive(:warn) { |message| warnings << message }

    get '/auth/me', headers: { 'Authorization' => "Bearer #{token}" }
    expect(response).to have_http_status(:ok)

    get '/auth/admin', headers: { 'Authorization' => "Bearer #{token}" }
    expect(response).to have_http_status(:forbidden)
    expect(warnings.join).to include('auth.logger.failure', 'degraded')
    expect(warnings.join).not_to include(token, user.email, 'logger unavailable')
  end

  it 'does not expose logger failure details to the client' do
    allow(Rails.logger).to receive(:info).and_wrap_original do |original, message, *args|
      raise IOError, 'secret logger path /internal/logger.sock' if message.to_s.include?('"event"')

      original.call(message, *args)
    end
    warnings = []
    allow(Kernel).to receive(:warn) { |message| warnings << message }

    get '/auth/me', headers: { 'Authorization' => 'Bearer malformed.sentinel.token' }

    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('logger unavailable', 'secret logger path', '/internal/logger.sock', 'IOError')
    expect(warnings.join).not_to include('secret logger path', '/internal/logger.sock', 'IOError')
  end
end
