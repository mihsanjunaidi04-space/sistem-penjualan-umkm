import { BrowserRouter, Navigate, Route, Routes, useParams } from 'react-router-dom'
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
import { AdminCatalogPage } from '../pages/AdminCatalogPage'
import { CatalogPage, ProductDetailPage } from '../pages/CatalogPage'
import { CartPage } from '../pages/CartPage'
import { CheckoutPage } from '../pages/CheckoutPage'
import { CustomerOrdersPage } from '../pages/CustomerOrdersPage'
import { CustomerPaymentPage } from '../pages/CustomerPaymentPage'
import { AdminPaymentsPage } from '../pages/AdminPaymentsPage'
import { AdminOrdersPage } from '../pages/AdminOrdersPage'
import { AdminCancellationsPage } from '../pages/AdminCancellationsPage'

export function AppRouter() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<PublicLayout />}>
          <Route path="/" element={<HomePage />} />
          <Route path="/catalog" element={<CatalogPage />} />
          <Route path="/products/:slug" element={<ProductDetailRoute />} />
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
          <Route path="cart" element={<CartPage />} />
          <Route path="checkout" element={<CheckoutPage />} />
          <Route path="orders" element={<CustomerOrdersPage />} />
          <Route path="orders/:id/payment" element={<CustomerPaymentPage />} />
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
          <Route path="catalog" element={<AdminCatalogPage />} />
          <Route path="payments" element={<AdminPaymentsPage />} />
          <Route path="orders" element={<AdminOrdersPage />} />
          <Route path="cancellations" element={<AdminCancellationsPage />} />
        </Route>

        <Route path="/redirect" element={<Navigate to="/" replace />} />
        <Route path="*" element={<NotFoundPage />} />
      </Routes>
    </BrowserRouter>
  )
}

function ProductDetailRoute() {
  const { slug } = useParams()
  return <ProductDetailPage slug={slug ?? ''} />
}
