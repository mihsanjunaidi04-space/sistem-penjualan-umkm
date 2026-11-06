class JwtService
  ALGORITHM = "HS256"
  REVOCATION_PREFIX = "revoked-jwt:"

  def self.encode(payload, exp = 24.hours.from_now.to_i)
    payload_with_exp = payload.deep_dup
    payload_with_exp[:jti] ||= SecureRandom.uuid
    payload_with_exp[:exp] = exp
    JWT.encode(payload_with_exp, secret_key, ALGORITHM)
  end

  def self.decode(token)
    JWT.decode(token, secret_key, true, algorithm: ALGORITHM).first.with_indifferent_access
  rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::VerificationError
    nil
  end

  def self.revoke(token, claims)
    return if claims[:jti].blank? || claims[:exp].blank?

    expires_at = Time.at(claims[:exp].to_i).utc
    return if expires_at <= Time.current

    JwtRevocation.create!(jti: claims[:jti], expires_at: expires_at)
  end

  def self.revoked?(claims)
    return false if claims[:jti].blank? || claims[:exp].blank?

    JwtRevocation.where(jti: claims[:jti]).where("expires_at > ?", Time.current).exists?
  rescue ActiveRecord::ActiveRecordError
    # A storage outage must not turn a revoked token into an accepted token.
    true
  end

  def self.revocation_key(jti)
    "#{REVOCATION_PREFIX}#{jti}"
  end

  def self.secret_key
    ENV.fetch("JWT_SECRET", Rails.application.credentials.dig(:jwt, :secret) || "development-jwt-secret-change-me")
  end
end
