import { useState } from 'react'
import type { FormEvent } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../app/AuthProvider'

export function LoginPage() {
  const { login } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  const redirectPath = (location.state as { from?: string } | null)?.from ?? '/customer'

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setError('')
    setIsSubmitting(true)

    try {
      await login({ email, password })
      const user = JSON.parse(localStorage.getItem('umkm_user') || 'null')
      navigate(user?.role === 'admin' ? '/admin' : redirectPath)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login gagal.')
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <div className="container narrow-panel">
      <section className="panel-card auth-card">
        <p className="eyebrow text-center">Masuk</p>
        <h1 className="text-center">Selamat datang kembali</h1>

        <form className="auth-form" onSubmit={handleSubmit}>
          <label>
            Email
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              required
              placeholder="nama@contoh.com"
            />
          </label>

          <label>
            Password
            <input
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              required
              placeholder="Masukkan password"
            />
          </label>

          {error ? <div className="form-error">{error}</div> : null}

          <button type="submit" disabled={isSubmitting}>
            {isSubmitting ? 'Memproses...' : 'Masuk'}
          </button>
        </form>

        <p className="auth-switch">
          Belum punya akun? <Link to="/register">Daftar sekarang</Link>
        </p>
      </section>
    </div>
  )
}
