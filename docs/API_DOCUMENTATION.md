# API Documentation
## Sistem Informasi Penjualan UMKM

**Versi:** 1.1\
**Path prefix:** tidak ada; path di bawah relatif terhadap host API.\
**Format request:** JSON untuk endpoint JSON; upload gambar katalog dan bukti pembayaran menggunakan `multipart/form-data`.\
**Format response:** JSON untuk endpoint JSON; unduhan gambar katalog dan bukti pembayaran mengirim file/binary.\
**Mata uang:** integer rupiah. Timestamp menggunakan ISO 8601 UTC.

Dokumen ini memisahkan endpoint yang tersedia dari aturan bisnis dan fitur yang belum tersedia. Endpoint berstatus **Implemented** hanya jika route dan action terkait ada di aplikasi. Fitur yang disebut di PRD tetapi belum memiliki route/action tidak dapat dipanggil sebagai endpoint.

## 1. Konvensi API

Response JSON sukses menggunakan `success: true`, `data`, dan biasanya `message`. Error menggunakan `success: false` dan objek `error` berisi `code`, `message`, serta `details`.

Endpoint privat memakai `Authorization: Bearer <token>`. Role requirement ditulis pada setiap endpoint. Registrasi publik hanya menghasilkan user ber-role customer.

Frontend saat ini menyimpan JWT pada `localStorage` dengan key `umkm_token` dan mengirimnya melalui Authorization header. JavaScript pada origin yang sama, termasuk script yang berjalan akibat XSS, dapat membaca token tersebut. Token dapat disalahgunakan sampai kedaluwarsa atau dicabut. React meng-escape teks interpolasi secara default, tetapi itu bukan perlindungan XSS menyeluruh. Tidak ada klaim bahwa localStorage aman atau bahwa CSP/sanitizer khusus sudah diterapkan.

## 2. Implemented API

Inventaris ini mencakup **55 route/action aplikasi** yang dideklarasikan di `backend/config/routes.rb`; jumlah ini bukan seluruh route runtime yang dapat ditambahkan Rails atau engine/framework. Setiap baris menyebut action tujuan dan status endpoint; `POST /checkout` berstatus Partial terhadap PRD karena integrasi voucher belum tersedia.

### 2.1 Health

| Method | Path | Controller/action | Akses | Status | Fungsi dan kontrak penting |
|---|---|---|---|---|---|
| GET | `/health` | `HealthCheckController#index` | Publik | Implemented | Health check aplikasi; JSON berisi status `ok`. |
| GET | `/up` | `Rails::HealthController#show` | Publik | Implemented | Rails health endpoint. |

### 2.2 Authentication

| Method | Path | Controller/action | Akses | Status | Fungsi dan kontrak penting |
|---|---|---|---|---|---|
| POST | `/auth/register` | `AuthController#register` | Publik | Implemented | Menerima `name`, `email`, `password`, `password_confirmation`; membuat customer dan mengembalikan token serta user. Rate limited. |
| POST | `/auth/login` | `AuthController#login` | Publik | Implemented | Menerima `email` dan `password`; mengembalikan token serta user bila kredensial valid. Rate limited. |
| DELETE | `/auth/logout` | `AuthController#logout` | JWT valid | Implemented | Mencabut token saat ini. |
| GET | `/auth/me` | `AuthController#me` | JWT valid | Implemented | Mengembalikan user saat ini. |
| PATCH | `/auth/profile` | `AuthController#update_profile` | JWT valid, user aktif | Implemented | Hanya field `name` yang diizinkan untuk diubah. |
| GET | `/auth/admin` | `AuthController#admin_only` | Admin | Implemented | Memeriksa akses admin dan mengembalikan role. |
| GET | `/auth/customer` | `AuthController#customer_only` | Customer | Implemented | Memeriksa akses customer dan mengembalikan role. |

Tidak ada route untuk forgot/reset password saat ini.

### 2.3 Customer profile and addresses

| Method | Path | Controller/action | Akses | Status | Fungsi dan kontrak penting |
|---|---|---|---|---|---|
| GET | `/customer/addresses` | `AddressesController#index` | Customer | Implemented | Mengembalikan alamat milik customer saat ini. |
| POST | `/customer/addresses` | `AddressesController#create` | Customer | Implemented | Membuat alamat untuk customer saat ini. Field yang diterima: `recipient_name`, `phone`, `address_line`, `province`, `city`, `district`, `postal_code`, `notes`, `is_default`. |
| PATCH | `/customer/addresses/:id` | `AddressesController#update` | Customer pemilik alamat | Implemented | Memperbarui field alamat yang diizinkan; `user_id` tidak diterima dari client. |
| DELETE | `/customer/addresses/:id` | `AddressesController#destroy` | Customer pemilik alamat | Implemented | Menghapus alamat. Jika alamat itu default, controller memilih alamat lain milik user yang sama bila tersedia. |

Database menegakkan maksimal satu alamat default per user melalui partial unique index. Alamat transaksi disalin sebagai snapshot saat checkout; perubahan alamat setelah checkout tidak mengubah snapshot order.

Jika user belum memiliki alamat, alamat pertama menjadi default kecuali request secara eksplisit mengirim `is_default: false`. Menetapkan alamat lain sebagai default mengganti default sebelumnya dalam scope user yang sama. Jika alamat default dihapus, alamat lain milik user tersebut dipilih bila masih ada.

### 2.4 Catalog

| Method | Path | Controller/action | Akses | Status | Fungsi dan kontrak penting |
|---|---|---|---|---|---|
| GET | `/categories` | `CategoriesController#index` | Publik | Implemented | Daftar kategori aktif. |
| GET | `/categories/:slug` | `CategoriesController#show` | Publik | Implemented | Detail kategori aktif dan produk aktif di dalamnya. |
| GET | `/products` | `ProductsController#index` | Publik | Implemented | Daftar produk/kategori aktif. Query yang didukung: `q`, `category`, `page`, `per_page`; ukuran halaman dibatasi 50. |
| GET | `/products/:slug` | `ProductsController#show` | Publik | Implemented | Detail produk aktif. |
| GET | `/products/:slug/images/:image_id` | `ProductsController#image` | Publik | Implemented | Mengirim konten gambar katalog (bukan JSON) setelah pemeriksaan file. |
| GET | `/shipping-methods` | `ShippingMethodsController#index` | Customer | Implemented | Daftar metode pengiriman aktif. Ini route pembacaan metode yang tersedia; tidak ada route admin untuk membuat atau mengubah metode pengiriman. |

### 2.5 Cart and checkout

| Method | Path | Controller/action | Akses | Status | Fungsi dan kontrak penting |
|---|---|---|---|---|---|
| GET | `/cart` | `CartController#index` | Customer | Implemented | Mengembalikan cart milik user saat ini. |
| POST | `/cart/items` | `CartController#create_item` | Customer | Implemented | Menerima `product_id` dan `quantity`; produk harus aktif dan stok tersedia. |
| PATCH | `/cart/items/:id` | `CartController#update_item` | Customer pemilik item | Implemented | Mengubah `quantity`; memeriksa status produk dan stok tersedia. |
| DELETE | `/cart/items/:id` | `CartController#destroy_item` | Customer pemilik item | Implemented | Menghapus item dari cart milik user saat ini. |
| DELETE | `/cart/items` | `CartController#clear` | Customer | Implemented | Mengosongkan cart milik user saat ini. |
| POST | `/checkout` | `CheckoutController#create` → `CheckoutService#call` | Customer | Partial terhadap PRD | Menerima `address_id`, `shipping_method_id`, dan opsional `customer_notes`; wajib menyertakan header `Idempotency-Key`. Mengembalikan order yang dibuat. Voucher belum terintegrasi. |

Checkout memverifikasi metode pengiriman aktif, mencari alamat melalui association user saat ini, dan mencari cart dengan `user_id` user tersebut. Produk serta kategori harus aktif, kuantitas harus positif, dan stok tersedia diperiksa serta direservasi dalam transaksi. Checkout membuat order, item order, snapshot nama/SKU/harga dan snapshot penerima/alamat, payment `pending` dengan metode `manual_transfer`, serta reservation dan movement stok; kemudian cart dikosongkan. Deadline pembayaran adalah 12 jam. Harga/diskon dari client tidak diterima; implementasi checkout saat ini menetapkan diskon nol dan belum mengintegrasikan voucher. Karena kebutuhan voucher pada PRD belum tersedia, endpoint checkout berstatus Partial terhadap PRD.

Idempotency key yang sama dengan payload sama mengulang hasil tersimpan; payload berbeda menghasilkan conflict. Kegagalan checkout menghapus record idempotency yang belum berhasil.

### 2.6 Orders

| Method | Path | Controller/action | Akses | Status | Fungsi dan kontrak penting |
|---|---|---|---|---|---|
| GET | `/customer/orders` | `OrdersController#index` | Customer | Implemented | Daftar order milik user saat ini, termasuk item, payment, shipment, cancellation requests, dan payment instructions yang tersedia. |
| GET | `/customer/orders/:id` | `OrdersController#show` | Pemilik order | Implemented | Detail order milik user saat ini. Data payment, shipment, cancellation, dan instruksi pembayaran terdapat dalam response; tidak ada endpoint GET payment terpisah pada customer order. |
| GET | `/admin/orders` | `Admin::OrdersController#index` | Admin | Implemented | Daftar order; mendukung filter `status` dan pencarian `q` pada nomor order. |
| GET | `/admin/orders/:id` | `Admin::OrdersController#show` | Admin | Implemented | Detail order. |

Snapshot item dan alamat disimpan pada order agar histori tidak mengikuti perubahan katalog atau alamat berikutnya.

### 2.7 Payments and payment proof

| Method | Path | Controller/action | Akses | Status | Fungsi dan kontrak penting |
|---|---|---|---|---|---|
| POST | `/customer/orders/:order_id/payment-proof` | `PaymentsController#upload_proof` | Pemilik order | Implemented | `multipart/form-data`, field `proof`; order harus `awaiting_payment`, payment `pending`/`rejected`, deadline belum lewat, dan tidak ada cancellation pending. Mengubah payment menjadi `waiting_verification`. |
| GET | `/customer/orders/:order_id/payment-proofs/:proof_id` | `PaymentsController#proof` | Pemilik order | Implemented | Mengirim file bukti secara privat setelah ownership check. |
| GET | `/admin/payments` | `Admin::PaymentsController#index` | Admin | Implemented | Daftar payment; query `status` tersedia dan default-nya `waiting_verification`. |
| GET | `/admin/payments/:id` | `Admin::PaymentsController#show` | Admin | Implemented | Detail payment, order, bukti, dan riwayat verifikasi. |
| GET | `/admin/payments/:id/proofs/:proof_id` | `Admin::PaymentsController#proof` | Admin | Implemented | Mengirim file bukti secara privat. URL dalam response admin adalah endpoint terotorisasi, bukan URL publik permanen. |
| POST | `/admin/payments/:id/approve` | `Admin::PaymentsController#approve` | Admin | Implemented | Memverifikasi payment dan memproses perubahan order/reservation secara transaksional. |
| POST | `/admin/payments/:id/reject` | `Admin::PaymentsController#reject` | Admin | Implemented | Menolak bukti; menerima `reason`. |

Bukti pembayaran divalidasi berdasarkan ukuran, ekstensi, dan MIME type hasil deteksi. Ukuran maksimal 5 MB; format yang diterima JPG/JPEG, PNG, atau WEBP. Upload memakai `multipart/form-data`, field `proof`. Upload bukti bukan konfirmasi dana diterima; payment baru dianggap `paid` setelah admin menyetujui bukti.

Payment states yang dikenal model: `pending`, `waiting_verification`, `paid`, `rejected`, `expired`, `refunded`. Proof states: `submitted`, `approved`, `rejected`. Route approval/rejection hanya menangani verifikasi payment/proof; tidak ada gateway pembayaran.

### 2.8 Cancellation

| Method | Path | Controller/action | Akses | Status | Fungsi dan kontrak penting |
|---|---|---|---|---|---|
| GET | `/customer/orders/:order_id/cancellation-requests` | `CancellationRequestsController#index` | Pemilik order | Implemented | Daftar cancellation request pada order milik user. |
| POST | `/customer/orders/:order_id/cancellation-requests` | `CancellationRequestsController#create` | Pemilik order | Implemented | Menerima `reason`; membuat request jika aturan eligibility terpenuhi. |
| GET | `/admin/cancellation-requests` | `Admin::CancellationRequestsController#index` | Admin | Implemented | Daftar request; query `status` opsional, default `pending`. |
| POST | `/admin/cancellation-requests/:id/approve` | `Admin::CancellationRequestsController#approve` | Admin | Implemented | Menyetujui request dan melepas reservation terkait dalam transaksi. |
| POST | `/admin/cancellation-requests/:id/reject` | `Admin::CancellationRequestsController#reject` | Admin | Implemented | Menolak request; menerima `admin_note`. |

Pengajuan mensyaratkan order `awaiting_payment`, deadline belum lewat, tidak ada cancellation yang masih pending, dan payment berstatus `pending`, `rejected`, atau `waiting_verification`. `cancelled` bukan status eligible. Bila request disetujui saat payment menunggu verifikasi, payment dan proof submitted ditolak. Refund bukan bagian otomatis dari endpoint cancellation.

### 2.9 Shipping

| Method | Path | Controller/action | Akses | Status | Fungsi dan kontrak penting |
|---|---|---|---|---|---|
| POST | `/admin/orders/:order_id/shipments` | `Admin::ShipmentsController#create` | Admin | Implemented | Membuat shipment untuk order eligible. |
| PATCH | `/admin/shipments/:id/pack` | `Admin::ShipmentsController#pack` | Admin | Implemented | Mengubah shipment dari `not_shipped` menjadi `packed`. |
| PATCH | `/admin/shipments/:id/ship` | `Admin::ShipmentsController#ship` | Admin | Implemented | Menerima `tracking_number`; mengirim shipment dan mengubah order menjadi `shipped`. |
| PATCH | `/admin/shipments/:id/deliver` | `Admin::ShipmentsController#deliver` | Admin | Implemented | Menandai shipment `delivered`. |

Shipment hanya dibuat untuk order `processing` dengan payment `paid`; maksimal satu shipment per order. Transisi shipment diperiksa oleh service. Pengiriman dikelola manual; tidak ada integrasi courier API. Informasi shipment tersedia pada response detail order customer dan admin.

### 2.10 Admin catalog and payment settings

| Method | Path | Controller/action | Akses | Status | Fungsi dan kontrak penting |
|---|---|---|---|---|---|
| GET | `/admin/categories` | `Admin::CategoriesController#index` | Admin | Implemented | Daftar kategori. |
| POST | `/admin/categories` | `Admin::CategoriesController#create` | Admin | Implemented | Membuat kategori dengan atribut yang diizinkan controller. |
| PATCH | `/admin/categories/:id` | `Admin::CategoriesController#update` | Admin | Implemented | Memperbarui kategori. |
| GET | `/admin/products` | `Admin::ProductsController#index` | Admin | Implemented | Daftar produk; mendukung `category_id` dan `q`. |
| POST | `/admin/products` | `Admin::ProductsController#create` | Admin | Implemented | Membuat produk. |
| PATCH | `/admin/products/:id` | `Admin::ProductsController#update` | Admin | Implemented | Memperbarui produk. |
| POST | `/admin/products/:id/images` | `Admin::ProductsController#upload_image` | Admin | Implemented | Mengunggah gambar melalui multipart file dan metadata gambar. |
| DELETE | `/admin/products/:id/images/:image_id` | `Admin::ProductsController#delete_image` | Admin | Implemented | Menghapus gambar produk. |
| GET | `/admin/payment-settings` | `Admin::PaymentsController#settings` | Admin | Implemented | Mengembalikan `bank_name`, `bank_account_name`, `bank_account_number`, dan `bank_transfer_instructions`. |
| PATCH | `/admin/payment-settings` | `Admin::PaymentsController#update_settings` | Admin | Implemented | Memperbarui field pengaturan yang diizinkan dan mengembalikan settings. |

## 3. Business Rules

### Authentication and profile

- API menggunakan JWT Bearer Token melalui `Authorization: Bearer <token>`; token tidak diterima dari role yang dikirim client sebagai sumber otorisasi.
- Backend memvalidasi token, status user, role, dan ownership sesuai endpoint; role yang dikirim client tidak memberi hak akses.
- JWT frontend saat ini disimpan di `localStorage`, yang dapat dibaca JavaScript pada origin yang sama. Ini merupakan risiko pencurian token jika terjadi XSS, bukan proteksi XSS.
- Profile memakai `/auth/me` untuk membaca dan `/auth/profile` untuk memperbarui nama saja.

### Cart, checkout, and transaction snapshots

- Validasi user serta kepemilikan cart dan alamat.
- Semua operasi cart menggunakan cart milik user yang terautentikasi. Checkout mencari cart berdasarkan user tersebut dan alamat melalui alamat milik user yang sama.
- Checkout memvalidasi metode pengiriman aktif, produk/kategori aktif, kuantitas, dan stok; operasi pembentukan order/reservation bersifat transaksional.
- Checkout menyimpan snapshot item dan alamat penerima. Pengubahan alamat/katalog setelah checkout tidak mengganti snapshot order historis.
- Diskon checkout saat ini nol. Voucher belum terintegrasi dalam checkout.

### Payments, cancellation, and refunds

- Pembayaran adalah transfer bank manual. Bukti transfer perlu diperiksa admin; upload tidak berarti dana sudah diterima.
- Refund dilakukan secara manual sesuai kebijakan. API/service workflow refund otomatis belum tersedia. Model/schema mengenal payment status `refunded` dan tabel refund, tetapi tidak ada endpoint/service yang otomatis mencatat refund atau mentransisikan payment ke status itu.
- Cancellation eligibility memakai payment states `pending`, `rejected`, `waiting_verification` serta syarat order/deadline yang dijelaskan di atas.

### Shipping

- Metode yang ditampilkan melalui API adalah metode aktif. Pengelolaan shipment dilakukan admin secara manual melalui transisi yang tersedia.
- Tidak ada API courier tracking atau pengelolaan admin shipping methods saat ini.

## 4. Planned, Partial, and Deferred

Bagian ini bukan daftar endpoint yang tersedia. Tidak ada path, request schema, response schema, atau tanggal implementasi yang ditetapkan di sini untuk fitur yang belum memiliki route.

| Fitur | Status | Yang dapat dipastikan dari source saat ini |
|---|---|---|
| Password reset | Planned (M4 — Authentication and authorization) | Belum ada route/action reset password. Path dan alur email tidak ditetapkan dalam dokumen ini. |
| Voucher | Partial / Planned (M10) | Model/schema voucher dan redemption tersedia; route voucher dan integrasi validasi/reservasi voucher pada checkout belum tersedia. Batas per-user tidak diklaim telah ditegakkan oleh checkout. |
| Wishlist | Planned (M10) | Model/schema tersedia, tetapi API route wishlist tidak tersedia. |
| Notifications | Planned (M10) | Model tersedia, tetapi API route notifications tidak tersedia. |
| Inventory administration | Partial; advanced inventory planned (M10) | API khusus administrasi atau adjustment inventory belum tersedia. `PATCH /admin/products/:id` tetap dapat memperbarui `stock_on_hand` dan `reserved_stock` melalui strong parameters controller. Reservation dan inventory movement digunakan internal oleh alur transaksi, bukan melalui API inventory khusus. |
| Dashboard and reports | Planned (M9, bagian penyelesaian MVP) | Endpoint dashboard/reports belum tersedia. Dashboard summary dan laporan operasional dasar direncanakan dalam M9 sebagai bagian penyelesaian MVP. Advanced analytics dan peningkatan ekspor laporan tetap berada di M10. |
| Refund workflow | Deferred | Refund berada di luar implementasi M8 dan dilakukan secara manual sesuai kebijakan. API/service workflow refund otomatis belum tersedia. Model/schema refund tersedia; status `refunded` tidak membuktikan transisi otomatis. |
| Admin shipping-method management | Partial | API hanya menyediakan pembacaan metode aktif melalui `GET /shipping-methods`; route admin untuk mengelola metode tidak tersedia meskipun pengelolaan metode disebut sebagai kebutuhan admin di PRD. |

`auth_sessions` ditunda sesuai keputusan proyek; pencabutan JWT memakai `jwt_revocations`. Ini tidak menambah endpoint session.

## 5. Implementation Notes

Endpoint lain yang disebut dalam PRD, DATABASE, atau rencana pengembangan tidak otomatis menjadi endpoint API. Status **Implemented** hanya berlaku pada daftar di Bagian 2. Perubahan routes/controller harus diikuti pembaruan daftar endpoint dan test yang sesuai.
