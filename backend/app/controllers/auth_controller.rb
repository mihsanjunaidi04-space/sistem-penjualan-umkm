class AuthController < ApplicationController
  def register
    user = User.new(user_params)
    user.role = "customer"

    if user.save
      render json: {
        success: true,
        data: {
          token: build_token(user),
          user: serialize_user(user)
        },
        message: "Registrasi berhasil."
      }, status: :created
    else
      render_error(:unprocessable_entity, "VALIDATION_ERROR", "Data registrasi tidak valid.", user.errors.to_hash)
    end
  end

  def login
    email = params[:email].to_s.strip.downcase
    password = params[:password].to_s

    user = User.find_by(email: email)
    if user&.authenticate(password)
      render json: {
        success: true,
        data: {
          token: build_token(user),
          user: serialize_user(user)
        },
        message: "Login berhasil."
      }, status: :ok
    else
      render_error(:unauthorized, "INVALID_CREDENTIALS", "Email atau password tidak valid.")
    end
  end

  def logout
    authenticate_user!
    return if performed?

    claims = JwtService.decode(authenticated_token)
    JwtService.revoke(authenticated_token, claims) if claims

    render json: {
      success: true,
      data: {},
      message: "Logout berhasil. Token sudah dicabut."
    }, status: :ok
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
