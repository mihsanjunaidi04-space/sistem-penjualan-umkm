class ApplicationController < ActionController::API
  before_action :set_default_response_format

  def current_user
    @current_user
  end

  def authenticate_user!
    token = bearer_token
    return render_error(:unauthorized, "AUTHENTICATION_REQUIRED", "Token autentikasi diperlukan.") if token.blank?

    claims = JwtService.decode(token)
    return render_error(:unauthorized, "INVALID_TOKEN", "Token tidak valid atau kedaluwarsa.") if claims.blank?
    return render_error(:unauthorized, "INVALID_TOKEN", "Token tidak valid atau kedaluwarsa.") if JwtService.revoked?(claims)

    @current_user = User.find_by(id: claims[:user_id])
    return render_error(:unauthorized, "USER_NOT_FOUND", "Pengguna tidak ditemukan.") if @current_user.blank?
    render_error(:unauthorized, "ACCOUNT_INACTIVE", "Akun tidak aktif.") unless @current_user.is_active?
  rescue JWT::InvalidTokenError, JWT::DecodeError
    render_error(:unauthorized, "INVALID_TOKEN", "Token tidak valid atau kedaluwarsa.")
  end

  def require_admin!
    authenticate_user!
    return if performed?
    return if current_user.admin?

    render_error(:forbidden, "FORBIDDEN", "Anda tidak memiliki akses admin.")
  end

  def require_customer!
    authenticate_user!
    return if performed?
    return if current_user.customer?

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
