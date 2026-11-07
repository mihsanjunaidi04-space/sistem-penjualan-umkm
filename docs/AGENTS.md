# AGENTS.md
## OpenCode Engineering Rules

**Project:** Sistem Informasi Penjualan UMKM  
**Stack:** React + Vite + TypeScript, Ruby on Rails 8.1.4 API-only, SQLite

## 1. Misi

Bertindak sebagai engineering assistant yang mengutamakan kebutuhan bisnis, keamanan, integritas data, maintainability, UX, testability, dan dokumentasi. Jangan menghasilkan kode hanya agar terlihat banyak atau kompleks.

## 2. Sumber kebenaran

Sebelum coding, baca:
1. `docs/PRD.md`
2. `docs/DATABASE.md`
3. `docs/API_DOCUMENTATION.md`
4. `docs/DESIGN.md`
5. `docs/SECURITY.md`
6. `docs/DEVELOPMENT_PLAN.md`
7. `docs/AGENTS.md`

Keputusan bisnis terbaru yang disetujui pengguna mengungguli draft lama. Jika konflik ditemukan, jangan menebak: laporkan konflik, dampak, dan keputusan yang diperlukan.

## 3. Sebelum perubahan

- Audit struktur repository dan status Git.
- Periksa versi runtime/dependency, migration, route, model, controller, frontend, konfigurasi, dan tests.
- Identifikasi implementasi yang sudah ada.
- Jangan menganggap repository kosong.
- Jangan menghapus atau mengganti file tanpa analisis dampak.
- Tentukan milestone aktif.
- Buat rencana sebelum perubahan besar.

## 4. Scope

- Satu milestone/task pada satu waktu.
- Jangan membangun seluruh sistem sekaligus.
- Jangan melompati quality gate.
- Jangan menambah fitur di luar scope tanpa persetujuan.
- Jangan menambahkan payment gateway, COD, integrasi kurir, role tambahan, microservices, Redis, Kubernetes, atau multi-instance tanpa kebutuhan dan persetujuan.
- Jangan mengubah stack/arsitektur inti tanpa analisis.

## 5. Aturan bisnis yang harus dipertahankan

- Role: admin dan customer.
- Pembayaran: transfer bank manual.
- Pengiriman: Reguler dan Express, manual.
- Tidak ada payment gateway/COD/API kurir pada MVP.
- Payment deadline 12 jam.
- Bukti transfer bukan bukti dana diterima.
- Approval hanya admin berwenang.
- Pembatalan melalui cancellation request.
- Refund manual dan dicatat terpisah.
- Auto-completion tujuh hari setelah shipped_at dengan pemeriksaan kondisi.
- Harga, diskon, ongkir, total dihitung backend.
- Stok dan reservasi harus konsisten.
- Checkout idempotent.

Jika aturan berubah, perbarui dokumentasi terlebih dahulu.

## 6. Backend rules

- Ikuti konvensi Rails.
- Pisahkan controller, model, service, authorization, serializer sesuai kompleksitas.
- Gunakan transaksi untuk operasi lintas tabel.
- Gunakan foreign key dan constraint.
- Gunakan ORM/parameterized query.
- Validasi state transition.
- Hindari callback tersembunyi untuk proses transaksi kompleks.
- Gunakan service object bila memang membantu.
- Jangan membuat abstraction berlebihan.

## 7. Frontend rules

- TypeScript konsisten; hindari `any` tanpa alasan.
- Ikuti struktur feature-based.
- API client terpusat.
- Server state dikelola konsisten.
- Validasi frontend untuk UX, backend tetap wajib validasi.
- Autentikasi backend menggunakan JWT Bearer Token melalui `Authorization: Bearer <token>`; dokumentasi harus konsisten dan tidak mengasumsikan session cookie.
- Hindari menyimpan token autentikasi berumur panjang di `localStorage` karena JavaScript pada origin yang sama dapat membacanya saat terjadi XSS.
- Implementasi saat ini masih menyimpan JWT di `localStorage` (`umkm_token`); catat sebagai risiko yang ada, jangan menyebutnya aman, dan jangan mengklaim mitigasi yang belum diterapkan.
- Route guard bukan pengganti authorization.
- Sediakan loading, empty, error, success, unauthorized state.
- Ikuti DESIGN.md.

## 8. Security-first

Patuhi `SECURITY.md`. Semua input, header, parameter, dan file dari client tidak tepercaya.

Dilarang:
- Password plaintext.
- Mempercayai role dari browser.
- Mengandalkan frontend validation.
- Resource access tanpa ownership check.
- Wildcard CORS dengan credentials.
- Menonaktifkan CSRF untuk menghilangkan error.
- Bukti pembayaran public.
- Secret dalam source code.
- Secret production JWT kurang dari 32 byte atau fallback antar-environment.
- Wildcard CORS production.
- Stack trace/data rahasia di response.
- Mengklaim aman tanpa pengujian.

Frontend saat ini menyimpan JWT di `localStorage`, sehingga XSS yang dapat menjalankan JavaScript pada origin frontend berpotensi mencuri token. React melakukan escaping teks interpolasi secara default, tetapi itu bukan perlindungan menyeluruh terhadap XSS. Jangan mengklaim CSP atau sanitizer khusus telah tersedia tanpa implementasi dan verifikasi.

## 9. Transaction integrity

Checkout, payment approval, reservation, cancellation, refund, dan scheduled jobs harus mempertimbangkan:
- Atomic transaction.
- Constraint.
- Idempotency.
- Concurrency.
- Valid state transition.
- Audit trail.
- Retry/failure partial.

Jangan double-decrement, double-release, atau double-refund. Ingat SQLite satu writer aktif; WAL bukan multi-writer.

## 10. Dependency and supply chain

- Evaluasi dependency sebelum menambahkan.
- Pilih package terpelihara dan kompatibel.
- Jalankan vulnerability checks yang tersedia.
- Jangan mengabaikan temuan tanpa alasan/mitigasi.
- Periksa lisensi kode pihak ketiga.
- Jangan upgrade major tanpa analisis dan test.

## 11. Testing

Setiap perubahan memiliki test yang sesuai:
- Unit.
- Request/API.
- Validation.
- Authorization/ownership.
- Negative.
- Regression.
- Concurrency/idempotency/rollback untuk transaksi kritis.

Jangan mengklaim test berhasil jika belum dijalankan. Laporkan output aktual dan test yang belum dijalankan.

## 12. Dokumentasi

Production JWT secret harus melalui `JWT_SECRET` atau Rails credentials `jwt.secret`, minimal 32 byte; jika tidak tersedia atau lemah, startup harus gagal. Development/test tidak menggunakan secret production. CORS development/test hanya mengizinkan `http://localhost:5173`; production menggunakan allowlist origin HTTPS dari `CORS_ALLOWED_ORIGINS`, tanpa wildcard.

Deployment SQLite tahap awal dibatasi satu host/backend instance dengan persistent storage lokal. Jangan menganggap WAL mendukung multi-writer atau shared multi-host storage.

- Business rule → PRD.
- Schema/relasi → DATABASE.
- Endpoint/response → API_DOCUMENTATION.
- UI/UX → DESIGN.
- Threat/control → SECURITY.
- Milestone → DEVELOPMENT_PLAN.
- Tata kerja agent → AGENTS.

Implementasi dan dokumentasi harus sinkron.

## 13. Definition of Done

- Scope terpenuhi.
- Business rules benar.
- Authorization/security diuji.
- Relasi dan constraint benar.
- Test relevan berhasil atau kegagalannya dijelaskan.
- Tidak ada regresi tak terjelaskan.
- Dokumentasi diperbarui.
- Risiko dan pekerjaan tertunda dilaporkan.

## 14. Laporan setiap task

Laporkan:
1. Ringkasan.
2. File dibuat/diubah.
3. Business rules.
4. Schema/relasi.
5. Security controls.
6. Tests dan hasil aktual.
7. Risiko/limitasi.
8. Dokumentasi.
9. Rekomendasi task berikutnya.

Jangan menyatakan siap produksi hanya karena aplikasi berjalan di development.
