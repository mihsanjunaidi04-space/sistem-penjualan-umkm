import api from './api'
import type { AuthMeResponse, AuthResponse, LoginPayload, RegisterPayload } from '../types/auth'

export const authService = {
  register: async (payload: RegisterPayload): Promise<AuthResponse> =>
    (await api.post<AuthResponse>('/auth/register', payload)) as unknown as AuthResponse,

  login: async (payload: LoginPayload): Promise<AuthResponse> =>
    (await api.post<AuthResponse>('/auth/login', payload)) as unknown as AuthResponse,

  me: async (): Promise<AuthMeResponse> =>
    (await api.get<AuthMeResponse>('/auth/me')) as unknown as AuthMeResponse,

  logout: async (): Promise<{ success: boolean; message: string }> =>
    (await api.delete('/auth/logout')) as unknown as { success: boolean; message: string },
}
