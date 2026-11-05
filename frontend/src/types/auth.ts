export type UserRole = 'customer' | 'admin'

export interface AuthUser {
  id: number
  name: string
  email: string
  role: UserRole
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface AuthResponse {
  success: boolean
  data: {
    token: string
    user: AuthUser
  }
  message: string
}

export interface AuthMeResponse {
  success: boolean
  data: {
    user: AuthUser
  }
  message: string
}

export interface LoginPayload {
  email: string
  password: string
}

export interface RegisterPayload {
  name: string
  email: string
  password: string
  password_confirmation: string
}
