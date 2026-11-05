export function CustomerDashboardPage() {
  return (
    <div className="grid two-col">
      <article className="panel-card">
        <p className="eyebrow">Ringkasan</p>
        <h2>Selamat datang, pelanggan</h2>
        <ul className="plain-list">
          <li>Pesanan aktif: 2</li>
          <li>Siap dikirim: 1</li>
          <li>Belum dibayar: 1</li>
        </ul>
      </article>

      <article className="panel-card">
        <p className="eyebrow">Aksi cepat</p>
        <h2>Menu utama</h2>
        <ul className="plain-list">
          <li>Riwayat pesanan</li>
          <li>Alamat pengiriman</li>
          <li>Metode pembayaran</li>
        </ul>
      </article>
    </div>
  )
}
