import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../app/AuthProvider'

export function AdminLayout() {
  const { user, logout, logoutError } = useAuth()

  return (
    <div className="app-shell app-shell--sidebar">
      <aside className="sidebar sidebar--admin">
        <div className="sidebar-brand">Admin Panel</div>
        <nav className="sidebar-nav" aria-label="menu admin">
          <NavLink to="/admin">Dashboard</NavLink>
          <NavLink to="/admin/catalog">Katalog</NavLink>
          <NavLink to="/admin">Produk</NavLink>
          <NavLink to="/admin/orders">Pesanan</NavLink>
          <NavLink to="/admin/payments">Pembayaran</NavLink>
          <NavLink to="/admin/cancellations">Pembatalan</NavLink>
          <NavLink to="/admin">Laporan</NavLink>
          <NavLink to="/">Kembali ke publik</NavLink>
          <button type="button" className="sidebar-logout sidebar-logout--admin" onClick={() => void logout()}>
            Logout ({user?.name ?? 'Admin'})
          </button>
        </nav>
      </aside>

      <div className="main-panel">
        <header className="panel-header panel-header--dark">
          <div>
            <p className="eyebrow">Admin</p>
            <h1>Area administrasi</h1>
          </div>
        </header>

        <main className="panel-content">
          {logoutError ? <div className="form-error" role="alert">{logoutError}</div> : null}
          <Outlet />
        </main>
      </div>
    </div>
  )
}
