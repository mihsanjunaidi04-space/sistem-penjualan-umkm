import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../app/AuthProvider'

export function PublicLayout() {
  const { isAuthenticated, user, logout, logoutError } = useAuth()

  return (
    <div className="app-shell">
      <header className="topbar">
        <div className="container nav-row">
          <div className="brand-wrap">
            <div className="brand-mark">UMKM</div>
            <div>
              <div className="brand-name">Sistem Penjualan</div>
              <div className="brand-caption">Toko digital</div>
            </div>
          </div>

          <nav className="nav" aria-label="menu utama">
            <NavLink to="/" end>
              Beranda
            </NavLink>
            <NavLink to="/catalog">Katalog</NavLink>
            {isAuthenticated && user?.role === 'customer' ? (
              <NavLink to="/customer">Customer</NavLink>
            ) : null}
            {isAuthenticated && user?.role === 'admin' ? (
              <NavLink to="/admin">Admin</NavLink>
            ) : null}
            {!isAuthenticated ? (
              <>
                <NavLink to="/login">Login</NavLink>
                <NavLink to="/register">Register</NavLink>
              </>
            ) : (
              <button type="button" className="logout-button" onClick={() => void logout()}>
                Logout
              </button>
            )}
          </nav>
        </div>
      </header>

      <main className="page-shell">
        {logoutError ? <div className="container"><div className="form-error" role="alert">{logoutError}</div></div> : null}
        <Outlet />
      </main>

      <footer className="footer">
        <div className="container footer-row">
          <span>© 2026 UMKM Platform</span>
          <span>Backend Rails API • Frontend React</span>
        </div>
      </footer>
    </div>
  )
}
