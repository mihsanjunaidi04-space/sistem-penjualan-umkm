require 'rails_helper'

RSpec.describe AuthRateLimiter do
  describe 'positive integer configuration' do
    it 'uses the documented defaults when ENV values are absent' do
      expect(described_class::LOGIN_IP_LIMIT).to eq(30)
      expect(described_class::REGISTER_IP_LIMIT).to eq(5)
      expect(described_class::CLEANUP_BATCH_SIZE).to eq(100)
    end

    {
      'AUTH_LOGIN_IP_LIMIT' => [ '0', '-1', 'not-an-integer' ],
      'AUTH_REGISTER_IP_LIMIT' => [ '0', '-1', 'not-an-integer' ],
      'AUTH_RATE_LIMIT_CLEANUP_BATCH' => [ '0', '-1', 'not-an-integer' ]
    }.each do |name, invalid_values|
      invalid_values.each do |invalid_value|
        it "rejects #{name}=#{invalid_value.inspect}" do
          allow(ENV).to receive(:fetch).with(name, '1').and_return(invalid_value)

          expect {
            described_class.send(:positive_integer_env, name, 1)
          }.to raise_error(ArgumentError, /#{name}/)
        end
      end
    end
  end

  it 'stores HMAC-derived keys without the raw email' do
    user_email = 'sensitive@example.com'
    key = described_class.send(:key, 'login-account-failures', described_class.normalize_email(user_email))

    expect(key).not_to include(user_email)
    expect(key).to match(/\Alogin-account-failures:[0-9a-f]{64}\z/)
  end

  it 'increments counters atomically and reports remaining retry time' do
    first = described_class.send(:increment, 'test-counter', window: 1.minute)
    second = described_class.send(:increment, 'test-counter', window: 1.minute)

    expect(first[:count]).to eq(1)
    expect(second[:count]).to eq(2)
    expect(second[:retry_after]).to be_positive
  end

  it 'resets an expired counter into a new window' do
    counter = AuthRateLimitCounter.create!(key: 'expired-counter', count: 10, window_started_at: 2.minutes.ago, expires_at: 1.minute.ago)

    result = described_class.send(:increment, counter.key, window: 1.minute)

    expect(result[:count]).to eq(1)
    expect(counter.reload.expires_at).to be > Time.current
  end

  it 'marks login as degraded when the IP counter is degraded' do
    request = instance_double(ActionDispatch::Request, get_header: '198.51.100.62')
    allow(described_class).to receive(:cleanup_expired!)
    allow(described_class).to receive(:consume).and_return(
      allowed: true,
      count: nil,
      retry_after: 0,
      degraded: true
    )
    allow(described_class).to receive(:count).and_return(count: 0, degraded: false)

    result = described_class.before_login(request: request, email: 'degraded@example.com')

    expect(result).to include(allowed: true, degraded: true)
  end

  it 'removes expired counters without removing active counters' do
    AuthRateLimitCounter.create!(key: 'expired-cleanup', count: 1, window_started_at: 2.minutes.ago, expires_at: 1.minute.ago)
    active = AuthRateLimitCounter.create!(key: 'active-cleanup', count: 1, window_started_at: Time.current, expires_at: 1.minute.from_now)

    described_class.cleanup_expired!

    expect(AuthRateLimitCounter.find_by(key: 'expired-cleanup')).to be_nil
    expect(AuthRateLimitCounter.find_by(key: active.key)).to be_present
  end

  it 'does not delete a counter reactivated after candidate selection' do
    counter = AuthRateLimitCounter.create!(key: 'reactivated-during-cleanup', count: 7, window_started_at: 2.minutes.ago, expires_at: 1.minute.ago)
    candidate_ids = nil

    described_class.cleanup_expired!(before_delete: lambda { |ids|
      candidate_ids = ids
      result = described_class.send(:increment, counter.key, window: 1.minute)
      expect(result[:count]).to eq(1)
    })

    expect(candidate_ids).to include(counter.id)
    expect(counter.reload.count).to eq(1)
    expect(counter.expires_at).to be > Time.current
  end

  it 'does nothing when there are no expired counters' do
    active = AuthRateLimitCounter.create!(key: 'active-only-cleanup', count: 1, window_started_at: Time.current, expires_at: 1.minute.from_now)

    expect(described_class.cleanup_expired!).to eq(0)
    expect(active.reload).to be_present
  end

  it 'limits cleanup to a bounded batch' do
    stub_const('AuthRateLimiter::CLEANUP_BATCH_SIZE', 2)
    3.times do |index|
      AuthRateLimitCounter.create!(key: "expired-batch-#{index}", count: 1, window_started_at: 2.minutes.ago, expires_at: 1.minute.ago + index.seconds)
    end

    described_class.cleanup_expired!

    expect(AuthRateLimitCounter.where("expires_at <= ?", Time.current).count).to eq(1)
  end

  it 'leaves expired counters beyond the batch available for the next cleanup' do
    stub_const('AuthRateLimiter::CLEANUP_BATCH_SIZE', 2)
    3.times do |index|
      AuthRateLimitCounter.create!(key: "expired-next-batch-#{index}", count: 1, window_started_at: 2.minutes.ago, expires_at: 1.minute.ago + index.seconds)
    end

    described_class.cleanup_expired!
    expect(AuthRateLimitCounter.where("expires_at <= ?", Time.current).count).to eq(1)

    described_class.cleanup_expired!
    expect(AuthRateLimitCounter.where("expires_at <= ?", Time.current).count).to eq(0)
  end

  it 'keeps a counter durable when it is reloaded from the database' do
    described_class.send(:increment, 'durable-counter', window: 1.minute)

    expect(AuthRateLimitCounter.find_by(key: 'durable-counter').count).to eq(1)
  end

  it 'does not lose increments from many concurrent requests' do
    threads = 8.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.send(:increment, 'concurrent-counter', window: 1.minute)
        end
      end
    end
    threads.each(&:join)

    expect(AuthRateLimitCounter.find_by(key: 'concurrent-counter').count).to eq(8)
  ensure
    threads&.each(&:join)
  end

  it 'does not allow more concurrent requests than the configured limit' do
    threads = 8.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          described_class.send(:consume, 'concurrent-limit-counter', limit: 3, window: 1.minute)
        end
      end
    end
    results = threads.map(&:value)

    expect(results.count { |result| result[:allowed] }).to eq(3)
    expect(AuthRateLimitCounter.find_by(key: 'concurrent-limit-counter').count).to eq(8)
  ensure
    threads&.each(&:join)
  end

  it 'marks counter storage failures as degraded without claiming a count' do
    error = ActiveRecord::StatementInvalid.new('database is locked')
    allow(AuthRateLimitCounter).to receive(:create_or_find_by!).and_raise(error)

    result = described_class.send(:consume, 'busy-counter', limit: 1, window: 1.minute)

    expect(result).to include(allowed: true, count: nil, degraded: true)
  end

  it 'resets account and IP-email failure delays after a valid login' do
    request = instance_double(ActionDispatch::Request, get_header: '198.51.100.61')
    email = 'reset-delay@example.com'
    described_class.record_login_failure(request: request, email: email)
    described_class.reset_login_failures(request: request, email: email)

    account_key = described_class.send(:key, 'login-account-failures', email)
    ip_email_key = described_class.send(:key, 'login-ip-email-failures', "198.51.100.61:#{email}")
    expect(described_class.send(:count, account_key)[:count]).to eq(0)
    expect(described_class.send(:count, ip_email_key)[:count]).to eq(0)
  end

  it 'does not log raw email, password, or token values' do
    request = instance_double(ActionDispatch::Request, get_header: '198.51.100.60')
    logged = []
    allow(Rails.logger).to receive(:info) { |message| logged << message }

    described_class.record_login_failure(request: request, email: 'sensitive@example.com')

    expect(logged.join).not_to include('sensitive@example.com', 'password123', 'Bearer')
  end
end
