import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { ProtectedRoute } from '../components/ProtectedRoute'
import { AdminLayout } from '../layouts/AdminLayout'
import { CustomerLayout } from '../layouts/CustomerLayout'
import { PublicLayout } from '../layouts/PublicLayout'
import { AdminDashboardPage } from '../pages/AdminDashboardPage'
import { CustomerDashboardPage } from '../pages/CustomerDashboardPage'
import { HomePage } from '../pages/HomePage'
import { LoginPage } from '../pages/LoginPage'
import { NotFoundPage } from '../pages/NotFoundPage'
import { RegisterPage } from '../pages/RegisterPage'

export function AppRouter() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<PublicLayout />}>
          <Route path="/" element={<HomePage />} />
          <Route path="/login" element={<LoginPage />} />
          <Route path="/register" element={<RegisterPage />} />
        </Route>

        <Route
          path="/customer"
          element={
            <ProtectedRoute requiredRole="customer">
              <CustomerLayout />
            </ProtectedRoute>
          }
        >
          <Route index element={<CustomerDashboardPage />} />
        </Route>

        <Route
          path="/admin"
          element={
            <ProtectedRoute requiredRole="admin">
              <AdminLayout />
            </ProtectedRoute>
          }
        >
          <Route index element={<AdminDashboardPage />} />
        </Route>

        <Route path="/redirect" element={<Navigate to="/" replace />} />
        <Route path="*" element={<NotFoundPage />} />
      </Routes>
    </BrowserRouter>
  )
}
