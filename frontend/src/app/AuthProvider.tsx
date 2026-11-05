import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import type { AuthUser, LoginPayload, RegisterPayload } from '../types/auth'
import { authService } from '../services/authService'

interface AuthContextValue {
  user: AuthUser | null
  token: string | null
  login: (payload: LoginPayload) => Promise<void>
  register: (payload: RegisterPayload) => Promise<void>
  logout: () => Promise<void>
  isAuthenticated: boolean
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined)

const STORAGE_KEYS = {
  token: 'umkm_token',
  user: 'umkm_user',
}

function readStoredUser(): AuthUser | null {
  try {
    const value = localStorage.getItem(STORAGE_KEYS.user)
    return value ? (JSON.parse(value) as AuthUser) : null
  } catch {
    localStorage.removeItem(STORAGE_KEYS.user)
    return null
  }
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [token, setToken] = useState<string | null>(() => localStorage.getItem(STORAGE_KEYS.token))
  const [user, setUser] = useState<AuthUser | null>(readStoredUser)

  const persistSession = useCallback((nextToken: string | null, nextUser: AuthUser | null) => {
    setToken(nextToken)
    setUser(nextUser)

    if (nextToken) {
      localStorage.setItem(STORAGE_KEYS.token, nextToken)
    } else {
      localStorage.removeItem(STORAGE_KEYS.token)
    }

    if (nextUser) {
      localStorage.setItem(STORAGE_KEYS.user, JSON.stringify(nextUser))
    } else {
      localStorage.removeItem(STORAGE_KEYS.user)
    }
  }, [])

  useEffect(() => {
    const clearUnauthorizedSession = () => persistSession(null, null)
    window.addEventListener('auth:unauthorized', clearUnauthorizedSession)

    if (token) {
      void authService
        .me()
        .then((response) => persistSession(token, response.data.user))
        .catch(() => persistSession(null, null))
    }

    return () => window.removeEventListener('auth:unauthorized', clearUnauthorizedSession)
  }, [persistSession, token])

  const login = useCallback(async (payload: LoginPayload) => {
    const response = await authService.login(payload)
    persistSession(response.data.token, response.data.user)
  }, [persistSession])

  const register = useCallback(async (payload: RegisterPayload) => {
    const response = await authService.register(payload)
    persistSession(response.data.token, response.data.user)
  }, [persistSession])

  const logout = useCallback(async () => {
    try {
      await authService.logout()
    } catch {
      // Ignore backend logout errors and clear client session
    } finally {
      persistSession(null, null)
    }
  }, [persistSession])

  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      token,
      login,
      register,
      logout,
      isAuthenticated: Boolean(token && user),
    }),
    [login, logout, register, token, user],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)

  if (!context) {
    throw new Error('useAuth must be used within AuthProvider')
  }

  return context
}
