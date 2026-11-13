class AuthController < ApplicationController
  def register
    rate_limit = AuthRateLimiter.before_register(request: request)
    unless rate_limit[:allowed]
      AuthRateLimiter.record_register_limited(request: request)
      return render_rate_limited(rate_limit[:retry_after])
    end

    user = User.new(user_params)
    user.role = "customer"

    if user.save
      log_security_event("auth.register.success", user_id: user.id)
      render json: {
        success: true,
        data: {
          token: build_token(user),
          user: serialize_user(user)
        },
        message: "Registrasi berhasil."
      }, status: :created
    else
      render_error(:unprocessable_entity, "VALIDATION_ERROR", "Data registrasi tidak valid.")
    end
  end

  def login
    email = params[:email].to_s.strip.downcase
    password = params[:password].to_s
    rate_limit = AuthRateLimiter.before_login(request: request, email: email)
    if !rate_limit[:allowed]
      AuthRateLimiter.record_login_limited(request: request)
      return render_rate_limited(rate_limit[:retry_after])
    end

    user = User.find_by(email: email)
    if user&.authenticate(password) && user.is_active?
      AuthRateLimiter.reset_login_failures(request: request, email: email)
      AuthRateLimiter.record_login_success(request: request, user_id: user.id)
      render json: {
        success: true,
        data: {
          token: build_token(user),
          user: serialize_user(user)
        },
        message: "Login berhasil."
      }, status: :ok
    else
      AuthRateLimiter.record_login_failure(request: request, email: email)
      render_error(:unauthorized, "INVALID_CREDENTIALS", "Email atau password tidak valid.")
    end
  end

  def logout
    token = authenticated_token
    authenticate_user!(check_revocation: false)
    if performed?
      log_security_event("auth.logout.failure", reason: token.blank? ? "token_missing" : "authentication_failed")
      return
    end

    claims = JwtService.decode(token)
    JwtService.revoke(token, claims) if claims
    log_security_event("auth.logout.success", user_id: current_user.id)

    render json: {
      success: true,
      data: {},
      message: "Logout berhasil. Token sudah dicabut."
    }, status: :ok
  rescue ActiveRecord::ActiveRecordError
    log_security_event("auth.logout.failure", reason: "revocation_failed")
    render_error(:service_unavailable, "REVOCATION_UNAVAILABLE", "Logout tidak dapat diproses saat ini. Silakan coba lagi.")
  end

  def me
    authenticate_user!
    return if performed?

    render json: {
      success: true,
      data: { user: serialize_user(current_user) },
      message: "Identitas pengguna berhasil diambil."
    }, status: :ok
  end

  def admin_only
    require_admin!
    return if performed?

    render json: {
      success: true,
      data: { role: current_user.role },
      message: "Akses admin valid."
    }, status: :ok
  end

  def customer_only
    require_customer!
    return if performed?

    render json: {
      success: true,
      data: { role: current_user.role },
      message: "Akses customer valid."
    }, status: :ok
  end

  private

  def render_rate_limited(retry_after)
    response.set_header("Retry-After", retry_after.to_i.to_s)
    render_error(:too_many_requests, "RATE_LIMITED", "Terlalu banyak percobaan. Silakan coba lagi nanti.")
  end

  def user_params
    params.permit(:name, :email, :password, :password_confirmation)
  end

  def build_token(user)
    JwtService.encode({ user_id: user.id, role: user.role, email: user.email })
  end

  def serialize_user(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      role: user.role,
      is_active: user.is_active,
      created_at: user.created_at.iso8601,
      updated_at: user.updated_at.iso8601
    }
  end

end
