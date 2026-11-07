class JwtService
  ALGORITHM = "HS256"

  def self.encode(payload, exp = 24.hours.from_now.to_i)
    payload_with_exp = payload.deep_dup
    payload_with_exp[:jti] ||= SecureRandom.uuid
    payload_with_exp[:exp] = exp
    JWT.encode(payload_with_exp, secret_key, ALGORITHM)
  end

  def self.decode(token)
    claims = JWT.decode(token, secret_key, true, algorithm: ALGORITHM, verify_expiration: true).first.with_indifferent_access
    return nil unless claims[:user_id].present? && claims[:jti].present?
    return nil unless claims[:exp].is_a?(Numeric) && claims[:exp] > Time.current.to_i

    claims
  rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::VerificationError
    nil
  end

  def self.revoke(token, claims)
    return if claims[:jti].blank? || claims[:exp].blank?

    expires_at = Time.at(claims[:exp].to_i).utc
    return if expires_at <= Time.current
    return if JwtRevocation.exists?(jti: claims[:jti])

    # The unique index resolves concurrent/repeated logout attempts atomically.
    JwtRevocation.create_or_find_by!(jti: claims[:jti]) do |revocation|
      revocation.expires_at = expires_at
    end
  end

  def self.revoked?(claims)
    return false if claims[:jti].blank? || claims[:exp].blank?

    JwtRevocation.where(jti: claims[:jti]).where("expires_at > ?", Time.current).exists?
  rescue ActiveRecord::ActiveRecordError
    # A storage outage must not turn a revoked token into an accepted token.
    true
  end

  def self.secret_key
    secret = ENV["JWT_SECRET"].presence || Rails.application.credentials.dig(:jwt, :secret).presence

    if Rails.env.production?
      raise_configuration_error("JWT_SECRET or Rails credentials jwt.secret must be configured") if secret.blank?
      raise_configuration_error("JWT secret must contain at least 32 bytes") if secret.bytesize < 32

      secret
    else
      # Keep local/test signing independent from production secrets and stable for this process.
      @development_secret ||= SecureRandom.hex(32)
    end
  end

  def self.raise_configuration_error(message)
    raise ArgumentError, "Invalid JWT configuration: #{message}"
  end
end
