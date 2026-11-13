require "openssl"

class AuthRateLimiter
  def self.positive_integer_env(name, default)
    value = Integer(ENV.fetch(name, default.to_s), 10)
    raise ArgumentError, "#{name} must be a positive integer" unless value.positive?

    value
  rescue ArgumentError, TypeError
    raise ArgumentError, "#{name} must be a positive integer"
  end

  LOGIN_IP_LIMIT = positive_integer_env("AUTH_LOGIN_IP_LIMIT", 30)
  LOGIN_IP_WINDOW = 1.minute
  LOGIN_FAILURE_WINDOW = 15.minutes
  REGISTER_IP_LIMIT = positive_integer_env("AUTH_REGISTER_IP_LIMIT", 5)
  REGISTER_IP_WINDOW = 10.minutes
  CLEANUP_BATCH_SIZE = positive_integer_env("AUTH_RATE_LIMIT_CLEANUP_BATCH", 100)

  def self.before_login(request:, email:)
    cleanup_expired!
    ip_result = consume(key("login-ip", source_ip(request)), limit: LOGIN_IP_LIMIT, window: LOGIN_IP_WINDOW)
    return ip_result unless ip_result[:allowed]

    ip_email_failures = count(key("login-ip-email-failures", "#{source_ip(request)}:#{normalize_email(email)}"))
    account_failures = count(key("login-account-failures", normalize_email(email)))
    delay = progressive_delay([ ip_email_failures[:count], account_failures[:count] ].max)
    sleep(delay) if delay.positive?

    { allowed: true, retry_after: 0, degraded: ip_result[:degraded] || ip_email_failures[:degraded] || account_failures[:degraded] }
  end

  def self.before_register(request:)
    cleanup_expired!
    consume(key("register-ip", source_ip(request)), limit: REGISTER_IP_LIMIT, window: REGISTER_IP_WINDOW)
  end

  def self.record_login_failure(request:, email:)
    increment(key("login-ip-email-failures", "#{source_ip(request)}:#{normalize_email(email)}"), window: LOGIN_FAILURE_WINDOW)
    increment(key("login-account-failures", normalize_email(email)), window: LOGIN_FAILURE_WINDOW)
    log_event("auth.login.failure", request: request, identifier: identifier_digest(normalize_email(email)))
  end

  def self.record_login_success(request:, user_id:)
    log_event("auth.login.success", request: request, user_id: user_id)
  end

  def self.reset_login_failures(request:, email:)
    now = Time.current
    keys = [
      key("login-account-failures", normalize_email(email)),
      key("login-ip-email-failures", "#{source_ip(request)}:#{normalize_email(email)}")
    ]
    AuthRateLimitCounter.where(key: keys).update_all(count: 0, expires_at: now, updated_at: now)
  rescue ActiveRecord::ActiveRecordError => error
    log_failure("counter reset", error)
    { degraded: true }
  end

  def self.record_register_limited(request:)
    log_event("auth.register.rate_limited", request: request)
  end

  def self.record_login_limited(request:)
    log_event("auth.login.rate_limited", request: request)
  end

  # Use the immediate peer supplied by Rack. X-Forwarded-For is not trusted until
  # the deployment defines and enforces a trusted reverse-proxy boundary.
  def self.source_ip(request)
    request.get_header("REMOTE_ADDR").to_s.presence || "unknown"
  end

  def self.normalize_email(email)
    email.to_s.strip.downcase
  end

  def self.key(scope, identifier)
    "#{scope}:#{identifier_digest(identifier)}"
  end

  def self.identifier_digest(value)
    OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, JwtService.secret_key, value.to_s)
  end

  def self.progressive_delay(failures)
    failures = failures[:count] if failures.is_a?(Hash)
    return 0 if failures < 5

    [ 0.25 * (2**(failures - 5)), 2.0 ].min
  end

  def self.consume(counter_key, limit:, window:)
    result = increment(counter_key, window: window)
    return result.merge(allowed: true) if result[:degraded]

    result.merge(allowed: result[:count] <= limit)
  rescue ActiveRecord::ActiveRecordError => error
    log_failure("counter consume", error)
    { allowed: true, count: nil, retry_after: 0, degraded: true }
  end

  def self.increment(counter_key, window:)
    now = Time.current
    counter = AuthRateLimitCounter.create_or_find_by!(key: counter_key) do |record|
      record.count = 0
      record.window_started_at = now
      record.expires_at = now + window
    end

    reset_at = now + window
    counter = AuthRateLimitCounter.transaction(requires_new: true) do
      updated = AuthRateLimitCounter.where(key: counter_key).update_all([
        "count = CASE WHEN expires_at <= ? THEN 1 ELSE count + 1 END, " \
        "window_started_at = CASE WHEN expires_at <= ? THEN ? ELSE window_started_at END, " \
        "expires_at = CASE WHEN expires_at <= ? THEN ? ELSE expires_at END, updated_at = ?",
        now, now, now, now, reset_at, now
      ])
      raise ActiveRecord::RecordNotFound unless updated == 1

      counter.reload
    end

    { count: counter.count, retry_after: [ (counter.expires_at - now).ceil, 1 ].max }
  rescue ActiveRecord::ActiveRecordError => error
    log_failure("counter increment", error)
    { count: nil, retry_after: 0, degraded: true }
  end

  def self.count(counter_key)
    counter = AuthRateLimitCounter.find_by(key: counter_key)
    return { count: 0, degraded: false } unless counter && counter.expires_at > Time.current

    { count: counter.count, degraded: false }
  rescue ActiveRecord::ActiveRecordError => error
    log_failure("counter read", error)
    { count: 0, degraded: true }
  end

  def self.cleanup_expired!(before_delete: nil)
    now = Time.current
    candidate_ids = AuthRateLimitCounter.where("expires_at <= ?", now).order(:expires_at).limit(CLEANUP_BATCH_SIZE).pluck(:id)

    # This callback exists only to make the candidate-selection/DELETE
    # interleaving deterministic in the regression spec. The DELETE itself
    # always re-checks expiry for the frozen candidate IDs.
    before_delete.call(candidate_ids) if before_delete

    AuthRateLimitCounter
      .where(id: candidate_ids)
      .where("expires_at <= ?", now)
      .delete_all
  rescue ActiveRecord::ActiveRecordError => error
    log_failure("counter cleanup", error)
    0
  end

  def self.log_event(event, request:, **attributes)
    Rails.logger.info({ event: event, ip: source_ip(request), **attributes }.to_json)
  rescue StandardError
    fallback_log(event)
  end

  def self.log_failure(operation, error)
    Rails.logger.warn({ event: "auth.rate_limiter.failure", operation: operation, error: error.class.name, degraded: true }.to_json)
  rescue StandardError
    fallback_log("auth.rate_limiter.failure")
  end

  def self.fallback_log(source)
    Kernel.warn({ event: "auth.logger.failure", source: source, degraded: true }.to_json)
  rescue StandardError
    nil
  end

  private_class_method :positive_integer_env, :key, :identifier_digest, :progressive_delay, :consume, :increment, :count, :log_event, :log_failure, :fallback_log
end
