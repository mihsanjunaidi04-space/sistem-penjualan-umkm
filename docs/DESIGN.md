# DESIGN SYSTEM & FRONTEND ARCHITECTURE
## Sistem Informasi Penjualan UMKM

**Versi:** 1.0  
**Arah visual:** Clean White & Smoke Grey dengan aksen biru

## 1. Prinsip desain

- Bersih, tenang, modern, dan mudah dibaca.
- Hierarki visual jelas.
- Fokus pada produk, informasi transaksi, dan tindakan pengguna.
- Hindari gradient berlebihan, dekorasi tidak fungsional, dan tampilan generik.
- Konsisten antara halaman publik, customer, dan admin.
- Responsive dan accessible.

## 2. Design tokens

### Warna

| Token | Nilai |
|---|---|
| Primary | `#2563EB` |
| Primary Hover | `#1D4ED8` |
| Primary Soft | `#EFF6FF` |
| Background | `#F8FAFC` |
| Surface | `#FFFFFF` |
| Surface Muted | `#F1F5F9` |
| Text Primary | `#0F172A` |
| Text Secondary | `#475569` |
| Text Muted | `#94A3B8` |
| Border | `#E2E8F0` |
| Success | `#16A34A` |
| Warning | `#D97706` |
| Danger | `#DC2626` |
| Info | `#0284C7` |

Gradient terbatas:
`linear-gradient(135deg, #2563EB 0%, #1D4ED8 100%)`

Gunakan hanya untuk area promosi/hero yang memang memerlukan penekanan. Jangan menerapkan gradient pada semua card, tombol, dan dashboard.

### Typography
- Inter atau system-ui.
- Body text mudah dibaca.
- Hierarki heading konsisten.
- Hindari terlalu banyak ukuran dan weight.

### Spacing dan bentuk
- Skala spacing kelipatan 4.
- Container maksimum sekitar 1200–1280px.
- Border tipis dan konsisten.
- Radius moderat.
- Shadow ringan hanya untuk membedakan elevasi.
- Jangan membuat seluruh elemen menjadi card.

## 3. Layout

### PublicLayout
- Navbar.
- Hero/intro.
- Katalog dan kategori.
- Detail produk.
- Footer.

### CustomerLayout
- Navigasi akun.
- Dashboard customer.
- Profil dan alamat.
- Pesanan dan detail pesanan.
- Pembayaran.
- Wishlist.
- Notifikasi.

### AdminLayout
- Sidebar.
- Topbar.
- Dashboard.
- Produk dan kategori.
- Pelanggan.
- Pesanan.
- Pembayaran.
- Pengiriman.
- Stok.
- Voucher.
- Ulasan.
- Notifikasi.
- Laporan.
- Pengaturan.

## 4. Halaman

### Public
- Home.
- Product catalog.
- Product detail.
- Login.
- Register.
- Forgot password.
- Reset password.

### Customer
- Dashboard.
- Profile.
- Addresses.
- Cart.
- Checkout.
- Order list/detail.
- Payment instructions and proof upload.
- Cancellation request.
- Shipment status.
- Wishlist.
- Notifications.
- Reviews.

### Admin
- Dashboard.
- Product CRUD.
- Category CRUD.
- Customer management.
- Order management.
- Payment verification.
- Cancellation requests.
- Refund records.
- Shipping methods and shipments.
- Inventory and movements.
- Voucher management.
- Review moderation.
- Notifications.
- Reports and exports.
- Store settings.

## 5. Status presentation

Jangan menyatukan status order, payment, dan shipment menjadi satu label yang ambigu. Tampilkan secara terpisah dengan label bahasa Indonesia yang mudah dipahami.

Setiap status harus memiliki:
- Label.
- Penjelasan singkat bila diperlukan.
- Warna yang konsisten.
- Aksi yang tersedia berdasarkan role dan status.

Frontend hanya menampilkan status dari backend; frontend tidak menentukan transisi.

## 6. UX transaksi

### Checkout
- Ringkasan item dan kuantitas.
- Alamat penerima.
- Metode pengiriman.
- Voucher bila tersedia.
- Rincian subtotal, diskon, ongkir, total.
- Penjelasan bahwa harga final dikonfirmasi backend.

### Payment
- Nomor pesanan.
- Jumlah transfer.
- Instruksi rekening yang dikonfigurasi admin.
- Tenggat pembayaran.
- Upload proof dengan batas format/ukuran.
- Status menunggu verifikasi, diterima, atau ditolak.
- Jangan menampilkan bukti atau data sensitif pengguna lain.

### Cancellation/refund
- Pisahkan permintaan pembatalan, keputusan admin, dan status refund.
- Jangan menampilkan refund selesai sebelum backend mencatat `processed`.

### Admin
- Konfirmasi sebelum aksi sensitif.
- Alasan wajib untuk penolakan/penyesuaian stok bila relevan.
- Riwayat aktivitas dan status jelas.
- Hindari tombol yang memungkinkan transisi ilegal.

## 7. Frontend architecture

Struktur feature-based yang disarankan:

```text
src/
  app/
    router/
    providers/
  assets/
  components/
    ui/
    layout/
    feedback/
    shared/
  features/
    auth/
    products/
    categories/
    cart/
    checkout/
    customers/
    orders/
    payments/
    cancellations/
    refunds/
    shipping/
    inventory/
    vouchers/
    wishlist/
    reviews/
    notifications/
    analytics/
    reports/
  layouts/
    PublicLayout.tsx
    CustomerLayout.tsx
    AdminLayout.tsx
  lib/
    api/
    query-client.ts
    utils/
  hooks/
  types/
  constants/
  styles/
```

Jangan memaksakan semua folder dibuat sekaligus. Tambahkan struktur ketika fitur milestone terkait mulai dikerjakan.

## 8. Frontend technology

- React + Vite + TypeScript.
- React Router untuk routing.
- Axios melalui API client terpusat.
- TanStack Query untuk server state jika sudah menjadi dependency proyek.
- React Hook Form dan Zod untuk form jika disetujui dalam setup.
- Lucide untuk icon bila diperlukan.
- Styling mengikuti design token; pilih pendekatan CSS/Tailwind yang sudah ada dan jangan mencampur banyak sistem tanpa alasan.

## 9. M8 UI decisions

- Customer order detail displays payment, shipment status, tracking number, and cancellation status.
- Customer sees the cancellation action only for eligible `awaiting_payment` orders without an active request.
- Admin has order/shipment and cancellation request views with status-aware actions.
- Tracking is displayed as stored data; the UI does not claim automatic courier tracking.

## 10. Authentication UX and security

- Gunakan server-side session dengan HttpOnly cookie.
- Jangan menyimpan token jangka panjang di localStorage.
- Terapkan CSRF pada request mutasi.
- Route guard hanya untuk UX.
- Backend tetap melakukan authorization dan ownership check.
- Tangani sesi expired dan unauthorized state dengan jelas.
- CORS, cookie, dan CSRF harus diuji pada origin development aktual.

## 10. Component standards

Komponen reusable:
- Button.
- Input.
- Select.
- Textarea.
- Modal/dialog.
- Table.
- Pagination.
- Badge/status.
- Alert.
- Toast.
- Loading/skeleton.
- Empty state.
- Error state.
- Confirm dialog.

Buat reusable component bila pola dan perilakunya memang sama. Hindari abstraction berlebihan.

## 11. Accessibility and responsive

- Label form terhubung dengan input.
- Navigasi keyboard.
- Focus state terlihat.
- Kontras warna memadai.
- Alt text gambar produk.
- Error tidak hanya disampaikan dengan warna.
- Layout diuji pada mobile, tablet, desktop.
- Tabel admin memiliki strategi responsive yang layak.

## 12. Performance

- Optimalkan ukuran gambar.
- Gunakan pagination untuk daftar besar.
- Hindari fetch berulang yang tidak perlu.
- Gunakan cache server state secara tepat.
- Lazy load halaman/fitur bila memberi manfaat.
- Jangan mengoptimalkan prematur tanpa pengukuran.

## 13. Design acceptance

- Konsistensi warna, typography, spacing.
- Tidak ada gradient/dekorasi berlebihan.
- Semua halaman memiliki loading, empty, error, dan success state.
- Data sensitif hanya terlihat oleh aktor berwenang.
- Responsif.
- Keyboard dan focus state berfungsi.
- Status transaksi sesuai backend.
