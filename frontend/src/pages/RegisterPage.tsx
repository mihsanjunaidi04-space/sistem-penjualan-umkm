import { useState } from 'react'
import type { FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../app/AuthProvider'

export function RegisterPage() {
  const { register } = useAuth()
  const navigate = useNavigate()
  const [form, setForm] = useState({
    name: '',
    email: '',
    password: '',
    password_confirmation: '',
  })
  const [error, setError] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)

  const handleChange = (field: keyof typeof form, value: string) => {
    setForm((current) => ({ ...current, [field]: value }))
  }

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setError('')
    setIsSubmitting(true)

    try {
      await register(form)
      navigate('/customer')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Registrasi gagal.')
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <div className="container narrow-panel">
      <section className="panel-card auth-card">
        <p className="eyebrow text-center">Daftar</p>
        <h1 className="text-center">Buat akun pelanggan</h1>

        <form className="auth-form" onSubmit={handleSubmit}>
          <label>
            Nama lengkap
            <input
              type="text"
              value={form.name}
              onChange={(event) => handleChange('name', event.target.value)}
              required
              placeholder="Nama lengkap"
            />
          </label>

          <label>
            Email
            <input
              type="email"
              value={form.email}
              onChange={(event) => handleChange('email', event.target.value)}
              required
              placeholder="nama@contoh.com"
            />
          </label>

          <label>
            Password
            <input
              type="password"
              value={form.password}
              onChange={(event) => handleChange('password', event.target.value)}
              required
              minLength={8}
              placeholder="Minimal 8 karakter"
            />
          </label>

          <label>
            Konfirmasi password
            <input
              type="password"
              value={form.password_confirmation}
              onChange={(event) => handleChange('password_confirmation', event.target.value)}
              required
              minLength={8}
              placeholder="Ulangi password"
            />
          </label>

          {error ? <div className="form-error">{error}</div> : null}

          <button type="submit" disabled={isSubmitting}>
            {isSubmitting ? 'Mendaftar...' : 'Daftar'}
          </button>
        </form>

        <p className="auth-switch">
          Sudah punya akun? <Link to="/login">Masuk</Link>
        </p>
      </section>
    </div>
  )
}
