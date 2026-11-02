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
- Jangan simpan token autentikasi jangka panjang di localStorage.
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
- Stack trace/data rahasia di response.
- Mengklaim aman tanpa pengujian.

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
