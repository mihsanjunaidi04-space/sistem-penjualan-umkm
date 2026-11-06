# API DOCUMENTATION
## Sistem Informasi Penjualan UMKM

**Versi:** 1.0  
**Base path:** `/api/v1`  
**Format:** JSON  
**Waktu:** ISO 8601 UTC  
**Uang:** integer rupiah

## 1. Prinsip

- Backend adalah sumber kebenaran.
- Semua endpoint privat memerlukan autentikasi.
- Role dan ownership diperiksa di backend.
- Tidak ada endpoint generik untuk mengubah status transaksi sesuka client.
- Request mutasi dilindungi CSRF jika menggunakan cookie session.
- Perhitungan harga, diskon, ongkir, dan total dilakukan backend.
- Error tidak membocorkan stack trace, SQL, secret, atau data sensitif.

## 2. Response envelope

Success:
```json
{
  "success": true,
  "data": {},
  "message": "Operasi berhasil"
}
```

Error:
```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Data tidak valid",
    "details": {}
  }
}
```

HTTP status umum: 200, 201, 204, 400, 401, 403, 404, 409, 422, 429, 500.

## 3. Authentication

| Method | Endpoint | Akses |
|---|---|---|
| GET | `/auth/csrf` | Publik |
| POST | `/auth/register` | Publik |
| POST | `/auth/login` | Publik |
| DELETE | `/auth/logout` | Login |
| GET | `/auth/me` | Login |
| POST | `/auth/forgot-password` | Publik |
| POST | `/auth/reset-password` | Publik |

Gunakan server-side session dan HttpOnly cookie. Secure pada HTTPS, SameSite sesuai deployment, CSRF untuk mutasi. Jangan menyimpan token autentikasi jangka panjang di localStorage. Registrasi publik hanya membuat customer.

**Implementasi Rails:** endpoint CSRF dan cookie harus mengikuti konfigurasi Rails yang benar. Jangan membuat mekanisme CSRF buatan yang bertentangan dengan middleware Rails. Uji konfigurasi frontend/backend lintas origin pada development.

## 4. Public catalog

- GET `/products`
- GET `/products/:slug`
- GET `/products/:slug/images/:image_id`
- GET `/categories`
- GET `/categories/:slug`

Hanya produk/kategori aktif yang ditampilkan. Filter, sort, pagination, dan ukuran page divalidasi dan dibatasi.

## 5. Admin catalog

- GET `/admin/categories`
- POST `/admin/products`
- GET `/admin/products`
- PATCH `/admin/products/:id`
- POST `/admin/products/:id/images`
- DELETE `/admin/products/:id/images/:image_id`
- POST `/admin/categories`
- PATCH `/admin/categories/:id`

Penghapusan produk yang sudah memiliki histori transaksi harus mempertahankan histori; pertimbangkan nonaktifkan/soft delete.

Upload gambar katalog menerima JPEG, PNG, atau WebP dengan ukuran maksimum 5 MB. File diberi storage key acak dan tidak menggunakan nama file dari client. Penyimpanan lokal digunakan pada tahap awal; object storage/CDN untuk production masih merupakan keputusan terbuka.

## 6. Customer profile and addresses

- GET `/customer/profile`
- PATCH `/customer/profile`
- GET `/customer/addresses`
- POST `/customer/addresses`
- PATCH `/customer/addresses/:id`
- DELETE `/customer/addresses/:id`

Customer hanya mengakses data miliknya.

## 7. Cart

- GET `/cart`
- POST `/cart/items`
- PATCH `/cart/items/:id`
- DELETE `/cart/items/:id`
- DELETE `/cart/items`

Quantity harus positif. Harga cart bukan harga final checkout.

Cart hanya dapat diakses customer pemilik sesi. Produk harus aktif dan berada pada kategori aktif; backend memeriksa stok sebelum menambah atau mengubah quantity.

## 8. Checkout

- POST `/checkout`
- GET `/shipping-methods`
- GET `/customer/addresses`
- GET `/customer/orders`
- GET `/customer/orders/:id`

Header:
```http
Idempotency-Key: <unique-key>
```

Request mengirim referensi alamat, item/keranjang, metode pengiriman, dan voucher bila digunakan. Jangan menerima harga final dari client.

Backend:
1. Validasi user dan ownership alamat/cart.
2. Ambil harga aktual.
3. Validasi produk aktif dan stok.
4. Hitung subtotal, diskon, ongkir, total.
5. Buat order dan snapshot item.
6. Buat payment `pending`.
7. Buat inventory reservation.
8. Buat voucher redemption bila diperlukan.
9. Tetapkan deadline 12 jam.
10. Simpan idempotency result.
11. Commit atomik.

Checkout membuat payment `pending` sebagai placeholder transaksi M6. Upload bukti dan verifikasi pembayaran adalah scope M7.

Key sama dan payload sama mengembalikan hasil yang sama. Key sama dengan payload berbeda menghasilkan conflict. Concurrency test wajib.

## 9. Customer orders

- GET `/customer/orders`
- GET `/customer/orders/:id`
- POST `/customer/orders/:id/cancellation-requests`
- GET `/customer/orders/:id/cancellation-requests`

Ownership wajib diperiksa. Cancellation request tidak langsung mengubah order status.

## 10. Payments and proofs

Customer:
- GET `/customer/orders/:order_id/payment`
- POST `/customer/payments/:id/proofs`
- GET `/customer/payments/:id/proofs`

Admin:
- GET `/admin/payments`
- GET `/admin/payments/:id`
- GET `/admin/payments/:id/proofs/:proof_id`
- POST `/admin/payments/:id/approve`
- POST `/admin/payments/:id/reject`

Payment states:
- `pending`
- `waiting_verification`
- `paid`
- `rejected`
- `expired`
- `refunded`

Proof states:
- `submitted`
- `approved`
- `rejected`

Upload proof tidak berarti dana diterima. Proof disimpan privat, divalidasi MIME/signature/size, dan hanya dapat diakses setelah authorization. Approval harus idempotent dan atomik terhadap order, stock, reservation, voucher, dan audit log.

## 11. Cancellation

Admin:
- GET `/admin/cancellation-requests`
- GET `/admin/cancellation-requests/:id`
- POST `/admin/cancellation-requests/:id/approve`
- POST `/admin/cancellation-requests/:id/reject`

Status request: `pending`, `approved`, `rejected`. Order menjadi `cancelled` setelah persetujuan sah. Jika pembayaran sudah diterima, refund manual diperlukan.

## 12. Refund

Admin:
- GET `/admin/refunds`
- GET `/admin/refunds/:id`
- POST `/admin/orders/:order_id/refunds`
- POST `/admin/refunds/:id/mark-processed`
- POST `/admin/refunds/:id/reject`

Status: `pending`, `processed`, `rejected`. MVP refund manual di luar payment gateway. Nominal tidak boleh melebihi pembayaran diterima dikurangi refund processed. `processed` hanya setelah dana benar-benar dikembalikan dan dikonfirmasi. Payment menjadi `refunded` setelah seluruh kewajiban refund selesai.

## 13. Shipping

Customer:
- GET `/customer/orders/:order_id/shipment`

Admin:
- GET `/admin/shipping-methods`
- POST `/admin/shipping-methods`
- PATCH `/admin/shipping-methods/:id`
- POST `/admin/orders/:order_id/shipments`
- PATCH `/admin/shipments/:id/pack`
- PATCH `/admin/shipments/:id/ship`
- PATCH `/admin/shipments/:id/deliver`

Metode awal Reguler dan Express. Satu shipment per order untuk MVP. Admin mengelola manual. Status harus mengikuti transisi valid. Tidak ada klaim pelacakan otomatis kurir.

## 14. Inventory

Admin:
- GET `/admin/inventory`
- GET `/admin/inventory/movements`
- POST `/admin/inventory/adjustments`

Adjustment memerlukan alasan dan audit log. Stok tidak boleh negatif. Reservation tidak boleh dikonversi/dilepas dua kali.

## 15. Vouchers

Customer:
- POST `/vouchers/validate`

Admin:
- GET `/admin/vouchers`
- POST `/admin/vouchers`
- PATCH `/admin/vouchers/:id`
- POST `/admin/vouchers/:id/deactivate`

Validasi saat checkout wajib diulang secara atomik, termasuk periode, kuota, minimum pembelian, batas per pengguna, dan status voucher.

## 16. Wishlist and reviews

- GET `/customer/wishlist`
- POST `/customer/wishlist/items`
- DELETE `/customer/wishlist/items/:id`
- GET `/products/:product_id/reviews`
- POST `/customer/order-items/:order_item_id/reviews`
- PATCH `/customer/reviews/:id`
- GET `/admin/reviews`
- PATCH `/admin/reviews/:id/moderation`

Review harus terkait order item yang memenuhi syarat; satu order item maksimal satu review.

## 17. Notifications

- GET `/customer/notifications`
- PATCH `/customer/notifications/:id/read`
- PATCH `/customer/notifications/read-all`

Ownership wajib diperiksa.

## 18. Dashboard and reports

- GET `/admin/dashboard/summary`
- GET `/admin/reports/sales`
- GET `/admin/reports/orders`
- GET `/admin/reports/products`
- GET `/admin/reports/inventory`
- GET `/admin/reports/export`

Laporan membedakan pembayaran terverifikasi, refund processed, pendapatan bersih, order belum dibayar, order dibatalkan, stok tersedia, dan stok terreservasi. CSV export harus membatasi akses, filter, ukuran, dan mencegah formula injection.

## 19. State transitions

Order:
- `awaiting_payment` → `processing` setelah payment verified.
- `awaiting_payment` → `cancelled` karena expiry atau cancellation yang sah.
- `processing` → `shipped` setelah shipment dikirim.
- `shipped` → `completed` setelah aturan penyelesaian terpenuhi.

Payment:
- `pending` → `waiting_verification` saat proof diajukan.
- `pending` → `expired` setelah deadline tanpa proof.
- `waiting_verification` → `paid` setelah approval.
- `waiting_verification` → `rejected` setelah rejection.
- `rejected` → `waiting_verification` jika resubmission masih diizinkan.
- `paid` → `refunded` setelah refund selesai seluruhnya.

Shipment:
- `not_shipped` → `packed` → `shipped` → `delivered`.

Cancellation request:
- `pending` → `approved` atau `rejected`.

Refund:
- `pending` → `processed` atau `rejected`.

Backend memvalidasi aktor, status awal, izin, dan kondisi bisnis. Tidak ada arbitrary status update.

## 20. Rate limiting baseline

Nilai awal untuk diuji dan disesuaikan:
- Login: 5/menit per akun dan IP.
- Password reset: 3/jam per akun.
- Registration: 5/jam per IP.
- Product search: 60/menit per pengguna.
- Checkout: 5/menit per pengguna.
- Proof upload: 5/jam per order.
- General API: 120/menit per pengguna.

Tambahkan batas ukuran payload, pagination, dan resource consumption.

## 21. Security requirements

- Authentication dan authorization pada setiap endpoint privat.
- Ownership check untuk mencegah IDOR/BOLA.
- Parameterized query/ORM.
- Input validation.
- CSRF dan CORS yang benar.
- HTTPS pada produksi.
- Secure HttpOnly cookie.
- File proof private.
- Error tanpa stack trace.
- Audit log tindakan sensitif.
- Secret di environment/secret manager.
- Dependency vulnerability review.
- Backup dan restore test.

## 22. API acceptance tests

- Customer A tidak dapat membaca order Customer B.
- Customer tidak dapat memanggil admin endpoint.
- Harga client tidak mengubah total.
- Idempotency mencegah order duplikat.
- Concurrent checkout tidak oversell.
- Upload proof tidak mengesahkan payment.
- Approval tidak dapat double-process.
- Refund tidak melebihi dana.
- Private proof tidak dapat diakses tanpa izin.
- State transition ilegal ditolak.
- Scheduled job aman diulang.

## 23. M8 final implementation contract

Implemented M8 routes are:

- `GET /admin/orders` with optional `status` and `q` filters
- `GET /admin/orders/:id`
- `POST /admin/orders/:order_id/shipments`
- `PATCH /admin/shipments/:id/pack`
- `PATCH /admin/shipments/:id/ship` with required `tracking_number`
- `PATCH /admin/shipments/:id/deliver`
- `GET /admin/cancellation-requests`
- `POST /admin/cancellation-requests/:id/approve`
- `POST /admin/cancellation-requests/:id/reject` with required `admin_note`
- `GET/POST /customer/orders/:order_id/cancellation-requests`

Cancellation is eligible only for an `awaiting_payment` order whose payment is `pending`, `rejected`, or `waiting_verification`. A pending cancellation blocks payment proof resubmission and payment approval. Refund is not performed by these endpoints.

## 24. Catatan kontrak

Endpoint di atas merupakan kontrak rancangan. Sebelum implementasi, cocokkan dengan migration, model, authorization policy, konfigurasi session/CSRF Rails, dan kebutuhan UI. Perubahan endpoint harus memperbarui dokumen ini dan test terkait.
# M7 — Payment transfer manual

Endpoint customer:

- `GET /customer/orders/:id` mengembalikan jumlah, deadline, status payment, riwayat bukti, dan `payment_instructions` dari `store_settings`.
- `POST /customer/orders/:order_id/payment-proof` menerima multipart field `proof`. Hanya order milik customer, status `awaiting_payment`, dan payment `pending`/`rejected` sebelum deadline yang diterima.
- `GET /customer/orders/:order_id/payment-proofs/:proof_id` mengirim file secara privat setelah ownership check.

Endpoint admin (semua memerlukan role `admin`):

- `GET /admin/payments?status=waiting_verification`
- `GET /admin/payments/:id`
- `GET /admin/payments/:id/proofs/:proof_id`
- `POST /admin/payments/:id/approve`
- `POST /admin/payments/:id/reject` dengan JSON `{ "reason": "..." }`
- `GET/PATCH /admin/payment-settings` dengan key `bank_name`, `bank_account_name`, `bank_account_number`, dan `bank_transfer_instructions`.

Bukti transfer tidak pernah dikembalikan sebagai URL publik permanen. URL admin hanya endpoint terotorisasi dan file berada di private disk.
