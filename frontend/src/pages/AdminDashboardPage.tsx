export function AdminDashboardPage() {
  return (
    <div className="grid two-col">
      <article className="panel-card">
        <p className="eyebrow">Operasional</p>
        <h2>Dashboard admin</h2>
        <ul className="plain-list">
          <li>Pesanan menunggu verifikasi: 6</li>
          <li>Menunggu pengiriman: 4</li>
          <li>Refund pending: 1</li>
        </ul>
      </article>

      <article className="panel-card">
        <p className="eyebrow">Prioritas</p>
        <h2>Aktivitas penting</h2>
        <ul className="plain-list">
          <li>Verifikasi bukti bayar</li>
          <li>Persetujuan pembatalan</li>
          <li>Review stok</li>
        </ul>
      </article>
    </div>
  )
}
