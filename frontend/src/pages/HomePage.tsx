import { useHealthCheck } from '../hooks/useHealthCheck'

export function HomePage() {
  const { data, loading, error, status } = useHealthCheck()

  return (
    <div className="container">
      <section className="hero">
        <div className="hero-copy">
          <p className="eyebrow">Platform ecommerce UMKM</p>
          <h1>Frontend foundation siap digunakan</h1>
          <p className="lead">
            Struktur routing, layout, API client, dan desain sistem sudah disiapkan untuk tahap
            pengembangan berikutnya.
          </p>
        </div>

        <div className="status-card">
          <p className="status-label">Backend health</p>
          <div className={`status-pill ${error ? 'status-pill--danger' : 'status-pill--success'}`}>
            {loading ? 'Checking...' : error ? 'Unavailable' : status}
          </div>

          <div className="status-meta">
            {loading && <span>Memeriksa endpoint /health...</span>}
            {!loading && !error && data && <span>{data.message}</span>}
            {!loading && error && <span>{error}</span>}
          </div>
        </div>
      </section>

      <section className="feature-grid">
        <article className="feature-card">
          <h2>Public</h2>
          <p>Landing page, katalog, dan detail produk untuk pelanggan umum.</p>
        </article>
        <article className="feature-card">
          <h2>Customer</h2>
          <p>Dashboard pelanggan, alamat, pesanan, pembayaran, dan notifikasi.</p>
        </article>
        <article className="feature-card">
          <h2>Admin</h2>
          <p>Panel admin untuk produk, pesanan, pengiriman, stok, dan laporan.</p>
        </article>
      </section>
    </div>
  )
}
