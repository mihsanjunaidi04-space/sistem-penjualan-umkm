import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../app/AuthProvider'

export function CustomerLayout() {
  const { user, logout } = useAuth()

  return (
    <div className="app-shell app-shell--sidebar">
      <aside className="sidebar">
        <div className="sidebar-brand">Customer Portal</div>
        <nav className="sidebar-nav" aria-label="menu customer">
          <NavLink to="/customer">Dashboard</NavLink>
          <NavLink to="/customer">Pesanan</NavLink>
          <NavLink to="/customer">Alamat</NavLink>
          <NavLink to="/customer">Pembayaran</NavLink>
          <NavLink to="/">Kembali ke publik</NavLink>
          <button type="button" className="sidebar-logout" onClick={() => void logout()}>
            Logout ({user?.name ?? 'Customer'})
          </button>
        </nav>
      </aside>

      <div className="main-panel">
        <header className="panel-header">
          <div>
            <p className="eyebrow">Customer</p>
            <h1>Area pelanggan</h1>
          </div>
        </header>

        <main className="panel-content">
          <Outlet />
        </main>
      </div>
    </div>
  )
}
