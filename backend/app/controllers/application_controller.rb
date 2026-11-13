class ApplicationController < ActionController::API
  before_action :set_default_response_format

  def current_user
    @current_user
  end

  def authenticate_user!(check_revocation: true)
    token = bearer_token
    return render_error(:unauthorized, "AUTHENTICATION_REQUIRED", "Token autentikasi diperlukan.") if token.blank?

    decode_result = JwtService.decode_result(token)
    if decode_result[:claims].blank?
      log_security_event(decode_result[:status] == :expired ? "auth.jwt.expired" : "auth.jwt.invalid")
      return render_error(:unauthorized, "INVALID_TOKEN", "Token tidak valid atau kedaluwarsa.")
    end

    claims = decode_result[:claims]
    if check_revocation
      revocation_status = JwtService.revocation_status(claims)
      if revocation_status == :revoked
        log_security_event("auth.jwt.revoked")
        return render_error(:unauthorized, "INVALID_TOKEN", "Token tidak valid atau kedaluwarsa.")
      elsif revocation_status == :unavailable
        log_security_event("auth.jwt.revocation_unavailable")
        return render_error(:unauthorized, "INVALID_TOKEN", "Token tidak valid atau kedaluwarsa.")
      end
    end

    @current_user = User.find_by(id: claims[:user_id])
    if @current_user.blank?
      log_security_event("auth.jwt.user_missing")
      return render_error(:unauthorized, "USER_NOT_FOUND", "Pengguna tidak ditemukan.")
    end

    unless @current_user.is_active?
      log_security_event("auth.jwt.account_inactive", user_id: @current_user.id)
      return render_error(:unauthorized, "ACCOUNT_INACTIVE", "Akun tidak aktif.")
    end
  rescue JWT::InvalidTokenError, JWT::DecodeError
    log_security_event("auth.jwt.invalid")
    render_error(:unauthorized, "INVALID_TOKEN", "Token tidak valid atau kedaluwarsa.")
  end

  def require_admin!
    authenticate_user!
    return if performed?
    return if current_user.admin?

    log_security_event("auth.authorization.denied", user_id: current_user.id, required_role: "admin")
    render_error(:forbidden, "FORBIDDEN", "Anda tidak memiliki akses admin.")
  end

  def require_customer!
    authenticate_user!
    return if performed?
    return if current_user.customer?

    log_security_event("auth.authorization.denied", user_id: current_user.id, required_role: "customer")
    render_error(:forbidden, "FORBIDDEN", "Anda tidak memiliki akses pelanggan.")
  end

  def render_error(status, code, message, details = {})
    render json: {
      success: false,
      error: {
        code: code,
        message: message,
        details: details
      }
    }, status: status
  end

  def log_security_event(event, **attributes)
    Rails.logger.info({ event: event, ip: AuthRateLimiter.source_ip(request), **attributes }.to_json)
  rescue StandardError
    begin
      Kernel.warn({ event: "auth.logger.failure", source: event, degraded: true }.to_json)
    rescue StandardError
      nil
    end
  end

  private

  def set_default_response_format
    request.format = :json
  end

  def bearer_token
    authorization_header = request.headers["Authorization"].to_s.strip
    return nil if authorization_header.blank?

    match = authorization_header.match(/Bearer\s+(.+)/)
    match ? match[1] : nil
  end

  def authenticated_token
    bearer_token
  end
end
