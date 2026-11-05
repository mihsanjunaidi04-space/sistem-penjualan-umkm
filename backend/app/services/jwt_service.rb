class JwtService
  ALGORITHM = 'HS256'

  def self.encode(payload, exp = 24.hours.from_now.to_i)
    payload_with_exp = payload.deep_dup
    payload_with_exp[:exp] = exp
    JWT.encode(payload_with_exp, secret_key, ALGORITHM)
  end

  def self.decode(token)
    JWT.decode(token, secret_key, true, algorithm: ALGORITHM).first.with_indifferent_access
  rescue JWT::DecodeError, JWT::ExpiredSignature, JWT::VerificationError
    nil
  end

  def self.secret_key
    ENV.fetch('JWT_SECRET', Rails.application.credentials.dig(:jwt, :secret) || 'development-jwt-secret-change-me')
  end
end
