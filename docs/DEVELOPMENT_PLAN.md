# DEVELOPMENT PLAN
## Sistem Informasi Penjualan UMKM

**Versi:** 1.0  
**Metode:** Milestone bertahap dengan quality gate

## 1. Prinsip pelaksanaan

- Audit repository sebelum coding.
- Ikuti dokumen yang disetujui.
- Kerjakan satu milestone pada satu waktu.
- Jangan membangun seluruh aplikasi sekaligus.
- Setiap milestone memiliki test dan acceptance criteria.
- Perubahan bisnis/schema/API harus memperbarui dokumentasi.
- Jangan mengklaim test berhasil tanpa menjalankannya.

## 2. Milestone

### M0 — Repository audit
- Periksa status Git, struktur, runtime, dependency, konfigurasi, kode, migration, dan test.
- Identifikasi implementasi yang sudah ada.
- Buat gap report terhadap dokumen.
- Jangan menghapus atau membangun ulang tanpa alasan.

**Gate:** audit dan rencana kerja disetujui.

### M1 — Backend foundation
- Rails API-only configuration.
- Environment development/test.
- Error handling dan logging dasar.
- CORS sesuai origin development.
- Health check.
- Test framework.

**Gate:** aplikasi berjalan, konfigurasi aman, test dasar berhasil.

### M2 — Database and domain model
- Implementasikan migration bertahap.
- Foreign key, unique/check constraints, indexes.
- Model dan associations.
- Seed data development yang aman.
- Test relasi dan constraint.

**Gate:** migration up/down teruji; constraint aktif; tidak ada data sensitif di seed.

### M3 — Frontend foundation
- React/Vite/TypeScript.
- Router dan layout dasar.
- Design tokens.
- API client.
- Error/loading/empty states.
- Struktur feature-based secukupnya.

**Gate:** build dan lint berhasil; layout responsive dasar.

### M4 — Authentication and authorization
- Register/login/logout/me.
- Server-side session.
- CSRF dan cookie configuration.
- Password reset.
- Role admin/customer.
- Ownership policy.

**Gate:** session, CSRF, rate limit, role, ownership, dan negative tests.

### M5 — Product and catalog
- Category/product CRUD.
- Public catalog/detail.
- Product images.
- Pagination, filtering.
- Admin authorization.

**Gate:** validasi, upload security, public/admin access tests.

### M6 — Cart and checkout
- Cart.
- Address selection.
- Shipping method selection.
- Server-side price calculation.
- Idempotency.
- Stock reservation.
- Order snapshots.

**Gate:** rollback, duplicate request, concurrent checkout, overselling tests.

### M7 — Payment
- Payment instructions.
- Private proof upload.
- Admin verification/rejection.
- Resubmission policy.
- Payment deadline handling.

**Gate:** private file access, payment state machine, double approval prevention, stock conversion.

### M8 — Orders, cancellation, shipping, refund
- Customer order history/detail.
- Cancellation request.
- Admin approval/rejection.
- Manual refund record.
- Shipment creation and status.
- Auto-completion job.

**Gate:** transition tests, refund limit, stock consistency, job idempotency.

### M9 — Dashboard and reports
- Summary.
- Sales/order/product/inventory reports.
- Payment vs refund accounting.
- Export with authorization and CSV formula injection protection.

**Gate:** report values reconcile with source transactions.

### M10 — Advanced features
Implementasikan bertahap:
- Advanced inventory.
- Voucher.
- Wishlist.
- Reviews.
- Notifications.
- Advanced analytics.
- Report export improvements.

**Gate:** setiap fitur memiliki PRD/API/schema/UI/test yang konsisten.

### M11 — Integration and acceptance
- End-to-end customer flow.
- End-to-end admin flow.
- Failure and retry paths.
- Regression tests.
- Usability checks.

**Gate:** semua skenario penerimaan utama lulus atau blocker tercatat.

### M12 — Security and performance hardening
- Threat-model review.
- OWASP-oriented testing.
- Dependency scan.
- Access-control review.
- Concurrency/load test.
- Backup/restore drill.
- Monitoring/logging review.

**Gate:** tidak ada critical/high issue yang belum ditangani atau diterima secara eksplisit dengan mitigasi.

### M13 — Deployment and documentation
- Environment production.
- HTTPS.
- Secure cookies/CSRF/CORS.
- Secret management.
- Admin MFA.
- Backup schedule.
- Monitoring.
- Runbook dan dokumentasi.

**Gate:** deployment checklist, restore test, dan smoke test.

## 3. Urutan prioritas

Jangan mengerjakan dashboard dekoratif atau fitur lanjutan sebelum alur inti aman:
1. Authentication/authorization.
2. Catalog.
3. Cart/checkout.
4. Stock reservation.
5. Payment verification.
6. Order processing.
7. Shipping.
8. Cancellation/refund.
9. Reports.
10. Advanced features.

## 4. Quality gates lintas milestone

### Security
- AuthN/AuthZ.
- Ownership.
- CSRF/CORS/session.
- Input validation.
- File security.
- Rate limit.
- Audit.
- Secret management.

### Data integrity
- FK/unique/check.
- Transactions.
- Idempotency.
- Concurrency.
- Rollback.
- State machine.

### Frontend
- Responsive.
- Accessible.
- Loading/empty/error/success.
- Tidak membocorkan data.
- Tidak mengandalkan route guard sebagai security.

### Documentation
- PRD, DATABASE, API, DESIGN, SECURITY, dan AGENTS konsisten.
- Update dokumen sebelum/bersamaan perubahan kontrak.

## 5. Pengujian performa

Angka berikut adalah target uji awal, bukan klaim kapasitas:
- 1.000 akun terdaftar.
- 100 concurrent users.
- 5.000 produk.
- 50.000 order.
- 200.000 order items.
- 10 request checkout bersamaan.

Target awal yang dapat diuji:
- API p95 < 1 detik untuk endpoint sederhana.
- Catalog/detail p95 < 2 detik.
- Dashboard p95 < 3 detik.
- Checkout p95 < 3 detik pada lingkungan uji yang ditetapkan.

Catat hardware, dataset, tool, konfigurasi, dan hasil aktual. Jangan menyatakan target tercapai tanpa benchmark.

## 6. SQLite and scaling

Tahap awal menggunakan satu Rails instance dengan SQLite pada local disk. Pantau busy errors, write contention, ukuran database, backup, dan response time. Evaluasi PostgreSQL sebelum kebutuhan multi-instance atau write concurrency melampaui desain awal. Redis, object storage, queue, dan load balancer ditambahkan hanya berdasarkan kebutuhan terukur.

## 7. Definition of Done

Task selesai jika:
- Scope terpenuhi.
- Aturan bisnis benar.
- Authorization dan ownership diuji.
- Integritas database terjaga.
- Test relevan dijalankan dan hasil dicatat.
- Tidak ada regresi yang tidak dijelaskan.
- Dokumentasi diperbarui.
- Risiko dan pekerjaan tertunda dilaporkan.

## 8. Format laporan milestone

1. Tujuan.
2. File dibuat/diubah.
3. Aturan bisnis.
4. Schema/relasi.
5. Kontrol keamanan.
6. Test dan hasil aktual.
7. Risiko/limitasi.
8. Dokumentasi.
9. Langkah berikutnya.
