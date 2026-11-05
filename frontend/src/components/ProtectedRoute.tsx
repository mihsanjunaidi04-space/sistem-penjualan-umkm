import type { ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '../app/AuthProvider'

interface ProtectedRouteProps {
  children: ReactNode
  requiredRole?: 'customer' | 'admin'
}

export function ProtectedRoute({ children, requiredRole }: ProtectedRouteProps) {
  const { isAuthenticated, user } = useAuth()
  const location = useLocation()

  if (!isAuthenticated) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />
  }

  if (requiredRole && user?.role !== requiredRole) {
    return <Navigate to="/" replace />
  }

  return <>{children}</>
}
