# Product Requirements Document (PRD)
## Sistem Informasi Penjualan UMKM Berbasis Web

**Versi:** 1.0  
**Status:** Baseline rancangan  
**Target:** Proyek Pemrograman Web, Informatika Semester 5

## 1. Ringkasan

Sistem Informasi Penjualan UMKM adalah aplikasi web untuk mendukung penjualan produk secara online dan pengelolaan operasional toko oleh admin. Pelanggan dapat melihat katalog, mengelola keranjang, melakukan checkout, membayar melalui transfer bank manual, memantau pesanan, dan memberikan ulasan. Admin mengelola produk, stok, pelanggan, pesanan, pembayaran, pengiriman, dan laporan.

Sistem dirancang sebagai aplikasi monolitik terpisah frontend-backend: React sebagai frontend dan Ruby on Rails API sebagai backend. SQLite digunakan pada tahap awal dengan batas operasional satu backend instance.

## 2. Latar belakang dan masalah

UMKM membutuhkan proses penjualan yang lebih terstruktur daripada pencatatan manual atau komunikasi pesanan melalui pesan pribadi. Risiko proses manual meliputi kesalahan pencatatan stok, ketidaksesuaian harga, pesanan terlewat, bukti pembayaran sulit ditelusuri, dan laporan penjualan yang tidak konsisten.

Sistem ini menyediakan satu sumber data terpusat untuk katalog, transaksi, pembayaran, stok, dan pengiriman.

## 3. Tujuan

1. Menyediakan katalog produk yang dapat diakses pelanggan.
2. Memungkinkan pelanggan melakukan pemesanan online.
3. Menjaga konsistensi harga, stok, dan transaksi.
4. Memfasilitasi verifikasi pembayaran transfer manual.
5. Memudahkan admin memproses pesanan dan pengiriman.
6. Menyediakan laporan operasional dan penjualan.
7. Menerapkan keamanan, otorisasi, audit, dan perlindungan data sejak awal.

## 4. Ruang lingkup

### 4.1 MVP — fitur inti

1. Produk dan kategori.
2. Pelanggan dan alamat.
3. Keranjang dan checkout.
4. Pesanan.
5. Pembayaran transfer manual dan verifikasi bukti.
6. Pengiriman manual.
7. Pengelolaan stok dasar dan histori pergerakan.
8. Dashboard dan laporan dasar.
9. Autentikasi, otorisasi, dan pengelolaan akun.

### 4.2 Fitur pengembangan setelah alur inti stabil

1. Manajemen stok lanjutan.
2. Voucher dan diskon.
3. Wishlist/produk favorit.
4. Ulasan dan rating.
5. Notifikasi sistem.
6. Dashboard analitik lanjutan.
7. Ekspor laporan.

Fitur lanjutan tidak boleh menghambat penyelesaian alur transaksi inti. Penerapan dilakukan bertahap mengikuti `DEVELOPMENT_PLAN.md`.

### 4.3 Di luar MVP

- Payment gateway.
- Cash on Delivery (COD).
- Integrasi API kurir atau pelacakan otomatis.
- Multi-vendor atau multi-toko.
- Multi-warehouse.
- Aplikasi mobile native.
- Microservices dan infrastruktur terdistribusi.
- Multi-instance backend dengan SQLite.

## 5. Aktor dan hak akses

### Customer
- Melihat katalog dan detail produk.
- Mendaftar, login, logout, dan mengelola profil.
- Mengelola alamat sendiri.
- Mengelola keranjang sendiri.
- Checkout dan melihat pesanan sendiri.
- Mengunggah bukti transfer untuk pesanan sendiri.
- Mengajukan pembatalan sesuai ketentuan.
- Melihat informasi pengiriman.
- Mengelola wishlist, ulasan, dan notifikasi sesuai kelayakan.

### Admin
- Mengelola produk, kategori, dan stok.
- Melihat dan mengelola pelanggan sesuai kewenangan.
- Memproses pesanan.
- Memeriksa bukti pembayaran dan memverifikasi pembayaran.
- Menyetujui atau menolak permintaan pembatalan.
- Mengelola refund manual.
- Mengelola metode pengiriman dan shipment.
- Mengelola voucher, ulasan, notifikasi, dan pengaturan toko.
- Melihat laporan dan mengekspor data sesuai izin.

Registrasi publik hanya boleh menghasilkan role `customer`. Role admin tidak boleh dapat ditetapkan melalui payload registrasi publik.

## 6. Alur bisnis utama

### 6.1 Katalog dan keranjang
1. Pelanggan membuka katalog.
2. Backend hanya menampilkan produk aktif.
3. Pelanggan memasukkan produk ke keranjang.
4. Keranjang menampilkan harga indikatif; harga final selalu dihitung ulang oleh backend saat checkout.

### 6.2 Checkout
1. Pelanggan memilih alamat dan metode pengiriman.
2. Backend memvalidasi kepemilikan alamat dan produk.
3. Backend mengambil harga terbaru dari database.
4. Backend menghitung subtotal, diskon, ongkir, dan total.
5. Backend memeriksa stok tersedia.
6. Dalam transaksi atomik, sistem membuat order, order items, payment, reservasi stok, dan reservasi voucher jika digunakan.
7. Sistem menetapkan batas pembayaran 12 jam.
8. Idempotency key mencegah order duplikat akibat retry.

### 6.3 Pembayaran
1. Pelanggan melakukan transfer di luar sistem ke rekening toko.
2. Pelanggan mengunggah bukti transfer sebelum tenggat.
3. Bukti disimpan secara privat dan status pembayaran menjadi `waiting_verification`.
4. Admin memeriksa bukti dan mencocokkan dana melalui kanal perbankan di luar aplikasi.
5. Jika valid, admin menyetujui pembayaran.
6. Jika tidak valid, admin menolak dengan alasan; pengajuan ulang hanya diperbolehkan selama aturan tenggat masih mengizinkan.

Bukti transfer yang diunggah bukan bukti dana telah diterima. Hanya verifikasi admin yang berwenang yang dapat mengesahkan pembayaran.

### 6.4 Stok
- Stok tersedia = `stock_on_hand - reserved_stock`.
- Reservasi dibuat saat checkout.
- Reservasi normal berlaku 12 jam.
- Jika bukti pembayaran diajukan sebelum tenggat, reservasi dipertahankan selama pemeriksaan admin.
- Pembayaran disetujui: reservasi dikonversi dan stok fisik dikurangi.
- Order kedaluwarsa atau pembatalan disetujui: reservasi dilepas.
- Semua perubahan stok dicatat.

### 6.5 Pengiriman dan penyelesaian
- Admin mengemas pesanan dan memperbarui shipment.
- Metode awal: Reguler dan Express.
- Pengelolaan pengiriman dan nomor pelacakan dilakukan manual.
- Ketika benar-benar dikirim, `shipped_at` dicatat.
- Order dapat otomatis selesai tujuh hari setelah `shipped_at` jika masih berstatus shipped dan tidak ada laporan/sengketa aktif yang tercatat.

**Catatan:** fitur laporan/sengketa harus tersedia dan didefinisikan sebelum pengecualian sengketa pada auto-completion diklaim telah bekerja. Jika belum tersedia, jangan mengklaim sistem mampu mendeteksi sengketa.

### 6.6 Pembatalan dan refund
- Customer mengajukan cancellation request sebelum pesanan diproses.
- Admin menyetujui atau menolak.
- Order menjadi `cancelled` hanya setelah pembatalan disetujui atau kedaluwarsa sesuai aturan.
- Reservasi stok dan voucher dilepas secara konsisten.
- Jika dana sudah diterima, refund manual dicatat terpisah.
- Refund hanya dianggap selesai setelah dana benar-benar dikembalikan dan dikonfirmasi admin.
- Barang yang telah dikirim tidak otomatis menambah stok ketika refund dilakukan. Pengembalian stok memerlukan proses retur dan verifikasi barang tersendiri.

## 7. Aturan status

### Order
- `awaiting_payment`
- `processing`
- `shipped`
- `completed`
- `cancelled`

### Payment
- `pending`
- `waiting_verification`
- `paid`
- `rejected`
- `expired`
- `refunded`

### Payment proof
- `submitted`
- `approved`
- `rejected`

### Shipment
- `not_shipped`
- `packed`
- `shipped`
- `delivered`

### Cancellation request
- `pending`
- `approved`
- `rejected`

### Refund
- `pending`
- `processed`
- `rejected`

### Inventory reservation
- `reserved`
- `converted`
- `released`

Status setiap entitas dipisahkan. Status tidak boleh diubah bebas melalui endpoint generik.

## 8. Kebutuhan fungsional

- FR-01: sistem menyediakan registrasi dan login.
- FR-02: sistem menerapkan role admin dan customer.
- FR-03: customer dapat melihat produk dan kategori aktif.
- FR-04: customer dapat mengelola keranjang sendiri.
- FR-05: customer dapat checkout dengan alamat dan metode pengiriman.
- FR-06: backend menghitung harga, diskon, ongkir, dan total.
- FR-07: sistem membuat reservasi stok saat checkout.
- FR-08: sistem menerima bukti transfer secara privat.
- FR-09: admin dapat memverifikasi atau menolak pembayaran.
- FR-10: customer dapat melihat status pesanan sendiri.
- FR-11: customer dapat mengajukan pembatalan sesuai aturan.
- FR-12: admin dapat memproses pembatalan dan refund manual.
- FR-13: admin dapat mengelola pengiriman.
- FR-14: sistem mencatat pergerakan stok.
- FR-15: admin dapat melihat laporan.
- FR-16: fitur lanjutan dapat diaktifkan secara bertahap.
- FR-17: tindakan sensitif dicatat dalam audit log.

## 9. Kebutuhan nonfungsional

### Keamanan
- Authentication dan authorization backend.
- Ownership check untuk resource customer.
- Password hashing yang kuat.
- Session cookie HttpOnly dan Secure pada HTTPS.
- CSRF protection.
- CORS allowlist.
- Rate limiting.
- Validasi input dan file.
- Private storage bukti transfer.
- Audit log tanpa secret.
- Secret tidak disimpan di repository.

### Integritas
- Foreign key dan constraint database.
- Transaksi atomik untuk checkout dan pembayaran.
- Idempotency untuk operasi yang dapat diulang.
- Proteksi overselling.
- Validasi state transition.
- Scheduled job idempotent.

### Kinerja dan skalabilitas
- Target performa ditentukan dan diukur melalui pengujian.
- SQLite hanya untuk satu backend instance pada tahap awal.
- PostgreSQL dievaluasi jika concurrency write atau kebutuhan multi-instance meningkat.
- Jangan mengklaim kapasitas tanpa benchmark.

### Usability
- Responsive.
- Loading, empty, error, dan success state.
- Form memiliki label dan validasi jelas.
- Aksesibilitas keyboard dan kontras warna diperhatikan.

## 10. Kriteria penerimaan utama

- Customer tidak dapat membaca order customer lain.
- Customer tidak dapat mengakses fungsi admin.
- Harga dari browser tidak dapat memanipulasi total.
- Checkout retry tidak membuat order duplikat.
- Checkout bersamaan tidak menyebabkan overselling.
- Bukti transfer tidak otomatis dianggap pembayaran.
- Pembayaran tidak dapat diverifikasi dua kali.
- Reservasi tidak dilepas atau dikonversi dua kali.
- Refund tidak melebihi dana yang diterima dikurangi refund yang sudah diproses.
- Bukti pembayaran tidak dapat diakses publik.
- Scheduled job aman dijalankan berulang.
- Laporan membedakan pembayaran terverifikasi, refund, dan pendapatan bersih.

## 11. Asumsi dan keputusan yang perlu dikonfirmasi

Sebelum produksi, tetapkan:
1. Identitas toko, rekening tujuan, dan instruksi transfer final.
2. SLA operasional admin untuk verifikasi bukti pembayaran.
3. Kebijakan pengajuan ulang setelah bukti ditolak.
4. Kebijakan retur barang dan refund untuk barang yang sudah dikirim.
5. Apakah fitur laporan/sengketa pelanggan masuk scope.
6. Kebijakan retensi bukti transfer, audit log, dan data pelanggan.
7. Aturan biaya pengiriman dan estimasi waktu Reguler/Express.
8. Kebijakan pajak atau biaya tambahan jika memang berlaku.

Jangan mengarang nilai atau kebijakan tersebut selama implementasi.
