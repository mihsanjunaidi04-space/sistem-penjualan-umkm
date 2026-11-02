# DATABASE DESIGN
## Sistem Informasi Penjualan UMKM

**Versi:** 1.0  
**Database awal:** SQLite  
**ORM:** Active Record (Rails)

## 1. Prinsip desain

- Integritas data ditegakkan melalui foreign key, unique index, check constraint, transaksi, dan validasi aplikasi.
- Nilai uang disimpan sebagai integer rupiah.
- Timestamp disimpan dalam UTC.
- Data transaksi menggunakan snapshot agar histori tidak berubah ketika data produk/alamat diedit.
- File bukti pembayaran disimpan di private storage; database hanya menyimpan metadata dan storage key.
- Perubahan stok dan transaksi harus dapat ditelusuri.
- Data transaksi penting tidak dihapus secara fisik melalui operasi normal.

## 2. Konfigurasi SQLite

- Foreign keys aktif.
- WAL digunakan setelah diuji pada environment.
- Busy timeout dikonfigurasi.
- Transaksi dibuat singkat.
- Database berada pada disk lokal.
- Satu backend instance untuk SQLite.
- WAL tidak menghilangkan batas satu writer aktif.
- Backup menggunakan mekanisme SQLite yang aman dan mencakup konsistensi WAL.
- Jangan menyalin atau menghapus file database/WAL secara sembarangan saat aplikasi aktif.

## 3. Daftar tabel

Rancangan ini terdiri dari **28 tabel**:

1. `users`
2. `addresses`
3. `auth_sessions`
4. `password_reset_tokens`
5. `categories`
6. `products`
7. `product_images`
8. `carts`
9. `cart_items`
10. `orders`
11. `order_items`
12. `payments`
13. `payment_proofs`
14. `inventory_reservations`
15. `inventory_movements`
16. `shipping_methods`
17. `shipments`
18. `vouchers`
19. `voucher_redemptions`
20. `wishlists`
21. `wishlist_items`
22. `reviews`
23. `notifications`
24. `audit_logs`
25. `idempotency_keys`
26. `store_settings`
27. `cancellation_requests`
28. `refunds`

## 4. Struktur tabel konseptual

Kolom `id`, `created_at`, dan `updated_at` yang lazim pada Rails tidak selalu diulang pada setiap daftar.

### 4.1 Identity

**users**
- `name`, `email` (unique), `password_digest`, `role`, `phone`, `is_active`, `email_verified_at`.
- Role: `admin`, `customer`.
- Registrasi publik hanya membuat customer.

**addresses**
- `user_id` FK, `recipient_name`, `phone`, `address_line`, `province`, `city`, `district`, `postal_code`, `notes`, `is_default`.
- User memiliki banyak alamat; akses dibatasi pemilik.

**auth_sessions**
- `user_id` FK, `session_token_digest`, `expires_at`, `last_used_at`.
- Simpan referensi/digest sesi, bukan token mentah jika implementasi memungkinkan.

**password_reset_tokens**
- `user_id` FK, `token_digest`, `expires_at`, `used_at`.
- Token acak, sekali pakai, memiliki expiry.

### 4.2 Catalog

**categories**
- `name`, `slug` unique, `description`, `is_active`.

**products**
- `category_id` FK, `name`, `slug` unique, `sku` unique, `description`, `price`, `stock_on_hand`, `reserved_stock`, `is_active`.
- Harga dan stok tidak negatif.
- `reserved_stock <= stock_on_hand`.
- Stok tersedia = `stock_on_hand - reserved_stock`.

**product_images**
- `product_id` FK, `storage_key`, `alt_text`, `position`.
- Validasi file dan storage dilakukan di aplikasi.

### 4.3 Cart

**carts**
- `user_id` FK.
- Satu cart aktif per customer pada MVP.

**cart_items**
- `cart_id` FK, `product_id` FK, `quantity`.
- Unique `(cart_id, product_id)`.
- Quantity > 0.
- Harga cart bukan sumber kebenaran checkout.

### 4.4 Order dan payment

**orders**
- `order_number` unique, `user_id` FK, `shipping_method_id` FK.
- `status`, `subtotal`, `discount_amount`, `shipping_cost`, `total_amount`.
- `voucher_code_snapshot`, `recipient_name_snapshot`, `recipient_phone_snapshot`, `shipping_address_snapshot`, `customer_notes`.
- `payment_deadline_at`, `shipped_at`, `completed_at`, `cancelled_at`.
- Status: `awaiting_payment`, `processing`, `shipped`, `completed`, `cancelled`.

**order_items**
- `order_id` FK, `product_id` FK.
- `product_name_snapshot`, `sku_snapshot`, `unit_price`, `quantity`, `subtotal`.
- Snapshot mempertahankan histori produk dan harga.

**payments**
- `order_id` unique FK, `payment_method`, `amount`, `status`, `verified_by` FK users, `verified_at`, `rejection_reason`.
- Status: `pending`, `waiting_verification`, `paid`, `rejected`, `expired`, `refunded`.
- Satu payment per order untuk MVP.

**payment_proofs**
- `payment_id` FK, `storage_key`, `original_filename`, `mime_type`, `file_size`, `status`, `uploaded_at`, `reviewed_at`.
- Status proof: `submitted`, `approved`, `rejected`.
- Mendukung riwayat unggah ulang.

### 4.5 Inventory

**inventory_reservations**
- `order_id` FK, `product_id` FK, `quantity`, `status`, `expires_at`, `converted_at`, `released_at`.
- Unique `(order_id, product_id)`.
- Status: `reserved`, `converted`, `released`.

**inventory_movements**
- `product_id` FK, optional `order_id` FK, `movement_type`, `quantity`, `stock_before`, `stock_after`, `reference`, `notes`, `created_by` FK users.
- Movement: `stock_in`, `stock_out`, `reservation`, `reservation_release`, `reservation_conversion`, `adjustment`, `return`.
- Riwayat normal bersifat append-only pada tingkat aplikasi; koreksi dicatat sebagai movement baru.

### 4.6 Shipping

**shipping_methods**
- `name`, `description`, `estimated_days`, `cost`, `is_active`.
- Metode awal Reguler dan Express.

**shipments**
- `order_id` unique FK, `shipping_method_id` FK.
- Snapshot penerima/alamat, `tracking_number`, `status`, `shipped_at`, `delivered_at`.
- Status: `not_shipped`, `packed`, `shipped`, `delivered`.
- Satu shipment per order untuk MVP.

### 4.7 Voucher

**vouchers**
- `code` unique, `description`, `discount_type`, `discount_value`, `minimum_purchase`, `maximum_discount`, `usage_limit`, `per_user_limit`, `starts_at`, `expires_at`, `is_active`.
- Discount type: `fixed`, `percentage`.

**voucher_redemptions**
- `voucher_id` FK, `user_id` FK, `order_id` unique nullable FK, `status`, `reserved_at`, `used_at`, `released_at`.
- Status: `reserved`, `used`, `released`.

### 4.8 Engagement

**wishlists**
- `user_id` FK; satu wishlist per customer.

**wishlist_items**
- `wishlist_id` FK, `product_id` FK.
- Unique `(wishlist_id, product_id)`.

**reviews**
- `user_id` FK, `product_id` FK, `order_item_id` unique FK, `rating`, `comment`, `is_visible`.
- Rating 1–5.
- Review hanya untuk order item yang memenuhi syarat pembelian.

**notifications**
- `user_id` FK, `type`, `title`, `message`, `data`, `read_at`.

### 4.9 Governance

**audit_logs**
- `user_id` nullable FK, `action`, `resource_type`, `resource_id`, `ip_address`, `user_agent`, `metadata`.
- Jangan menyimpan password, token, secret, atau bukti transfer mentah.
- Retensi IP/user-agent harus ditetapkan.

**idempotency_keys**
- `user_id` FK, `key`, `request_hash`, `response_status`, `response_body`, `resource_type`, `resource_id`, `expires_at`.
- Unique `(user_id, key)`.
- Key sama dengan payload berbeda harus ditolak.

**store_settings**
- `setting_key` unique, `setting_value`, `updated_by` FK users.
- Hanya untuk pengaturan non-rahasia.
- Secret dan credential tidak disimpan di sini.

**cancellation_requests**
- `order_id` FK, `requested_by` FK users, `reason`, `status`, `reviewed_by` FK users, `reviewed_at`, `admin_note`.
- Status: `pending`, `approved`, `rejected`.

**refunds**
- `payment_id` FK, `order_id` FK, `amount`, `reason`, `status`, `processed_by` FK users, `processed_at`, `reference_number`, `notes`.
- Status: `pending`, `processed`, `rejected`.
- Total refund processed tidak boleh melebihi dana diterima.

## 5. Relasi utama

- User 1—N Address.
- User 1—N Order.
- User 1—N AuthSession.
- User 1—1 Cart aktif.
- Cart 1—N CartItem.
- Product 1—N ProductImage.
- Category 1—N Product.
- Order 1—N OrderItem.
- Order 1—1 Payment.
- Payment 1—N PaymentProof.
- Order 1—N InventoryReservation.
- Product 1—N InventoryReservation.
- Product 1—N InventoryMovement.
- Order 1—1 Shipment (MVP).
- Order 1—N CancellationRequest secara historis; kebijakan aplikasi membatasi permintaan aktif.
- Payment 1—N Refund.
- Voucher 1—N VoucherRedemption.
- User 1—1 Wishlist.
- Wishlist 1—N WishlistItem.
- Product 1—N Review.
- User 1—N Notification.

Semua FK harus memiliki kebijakan delete yang mempertahankan histori transaksi. Jangan memakai cascade delete secara membabi buta pada order, payment, proof, movement, refund, dan audit.

## 6. Aturan transaksi

### Checkout
Dalam transaksi:
1. Validasi user, alamat, cart, produk aktif.
2. Ambil harga dari database.
3. Validasi stok tersedia.
4. Hitung subtotal, diskon, ongkir, total.
5. Buat order dan item snapshot.
6. Buat payment `pending`.
7. Buat reservation `reserved`.
8. Buat voucher redemption `reserved` bila dipakai.
9. Simpan deadline 12 jam.
10. Simpan hasil idempotency.
11. Commit.

Concurrency harus diuji. SQLite satu writer aktif; gunakan transaksi singkat dan strategi serialisasi yang benar.

### Bukti pembayaran
- Upload sebelum deadline.
- Payment menjadi `waiting_verification`.
- Reservation tetap ditahan selama pemeriksaan.
- Admin approve/reject.
- Rejection dan resubmission mengikuti tenggat yang berlaku.
- SLA verifikasi admin belum ditetapkan dan harus menjadi kebijakan operasional.

### Approval pembayaran
Dalam transaksi atomik:
- Validasi payment/order belum diproses.
- Payment menjadi `paid`.
- Kurangi `stock_on_hand` dan `reserved_stock`.
- Reservation menjadi `converted`.
- Buat inventory movement.
- Voucher redemption menjadi `used`.
- Order menjadi `processing`.
- Buat audit log/notifikasi.

### Expiry
- Jika tidak ada proof sebelum 12 jam: payment `expired`, order `cancelled`, reservation dan voucher redemption `released`.
- Job harus idempotent dan memeriksa status terbaru sebelum perubahan.

### Cancellation/refund
- Cancellation request diputuskan admin.
- Jika disetujui, order `cancelled`.
- Reservation yang belum dikonversi dilepas.
- Jika dana telah diterima, buat/lanjutkan refund manual.
- Refund `processed` hanya setelah pengembalian dana dikonfirmasi.
- Jangan otomatis mengembalikan stok barang yang telah dikirim.

### Completion
- Job memeriksa `shipped_at` dan status order.
- Selesaikan setelah tujuh hari jika masih memenuhi syarat.
- Jangan menyelesaikan order yang sudah berubah status atau memiliki sengketa aktif yang tercatat.
- Jika fitur sengketa belum ada, nyatakan keterbatasan tersebut.

## 7. Constraint dan index

Unique:
- `users.email`
- `categories.slug`
- `products.slug`
- `products.sku`
- `orders.order_number`
- `payments.order_id`
- `shipments.order_id`
- `vouchers.code`
- `idempotency_keys(user_id, key)`
- `cart_items(cart_id, product_id)`
- `wishlist_items(wishlist_id, product_id)`
- `inventory_reservations(order_id, product_id)`
- `reviews.order_item_id`

Check:
- Harga, diskon, ongkir, total, stok, dan quantity tidak negatif.
- Quantity > 0.
- Rating 1–5.
- `reserved_stock <= stock_on_hand`.
- Nominal refund positif dan akumulasi refund processed tidak melebihi pembayaran diterima (aturan agregat juga divalidasi dalam transaksi).

Index:
- Foreign keys.
- Order by user/status/created_at.
- Payment by status.
- Reservation by status/expiry.
- Product by category/active.
- Shipment by status.
- Notification by user/read_at.
- Refund by payment/status.

## 8. Keamanan, privasi, backup

- Query melalui ORM/parameterized query.
- Authorization dan ownership check di backend.
- Private storage untuk payment proof.
- Backup terlindungi dan dienkripsi pada media penyimpanan.
- Uji restore berkala.
- Log tidak menyimpan rahasia.
- Retensi data ditentukan sebelum produksi.
- Data pribadi ditangani sesuai ketentuan perlindungan data yang berlaku.
- SQLite bukan database multi-instance; evaluasi PostgreSQL bila kebutuhan meningkat.

## 9. Rails implementation notes

- Gunakan migrations.
- Tambahkan foreign key, unique index, dan check constraint pada database.
- Validasi model melengkapi, bukan menggantikan, constraint database.
- Gunakan service object untuk checkout, payment approval, cancellation, refund, dan inventory bila kompleksitasnya memerlukan.
- Hindari callback tersembunyi untuk transaksi lintas tabel.
- Uji migration pada development dan test.
- Perubahan schema harus memperbarui dokumen ini.

## 10. Required tests

- Concurrent checkout tidak oversell.
- Idempotency mencegah order duplikat.
- Payment approval tidak double-decrement.
- Reservation tidak double-release.
- Voucher limit tidak terlampaui.
- Customer tidak dapat mengakses data customer lain.
- Refund tidak melebihi dana diterima.
- File proof privat.
- Scheduled jobs idempotent.
- Rollback menjaga konsistensi jika langkah transaksi gagal.
