# SECURITY ARCHITECTURE & CYBERSECURITY REQUIREMENTS

**Versi:** 1.0  
**Project:** Sistem Informasi Penjualan UMKM

## 1. Tujuan

Keamanan merupakan persyaratan arsitektur sejak awal. Dokumen ini menetapkan aset, ancaman, kontrol, dan pengujian minimum. Tidak ada sistem yang dapat dinyatakan aman secara absolut; klaim harus didukung konfigurasi dan hasil pengujian aktual.

## 2. Prinsip

- Least privilege.
- Defense in depth.
- Secure by default.
- Fail securely.
- Validate on server.
- Minimize sensitive data.
- Auditability.
- Secure recovery.
- Privacy by design.

## 3. Aset yang dilindungi

- Akun, password, session, reset token.
- Data profil dan alamat.
- Order dan item.
- Payment dan bukti transfer.
- Rekening tujuan transfer.
- Harga, stok, voucher.
- Refund.
- Audit log.
- Database dan backup.
- Application secrets dan infrastructure credentials.

## 4. Threat model

Ancaman minimum:
- Brute force dan credential stuffing.
- Session hijacking.
- Broken access control, IDOR/BOLA.
- Privilege escalation.
- SQL injection.
- Stored/reflected XSS.
- CSRF.
- Malicious file upload.
- Manipulasi harga/diskon/ongkir.
- Replay dan duplicate request.
- Race condition dan overselling.
- Penyalahgunaan voucher.
- Kebocoran data.
- Denial of service dan resource exhaustion.
- Pencurian backup/secrets.
- Vulnerability dependency/supply chain.

Untuk fitur sensitif, identifikasi aktor, aset, trust boundary, ancaman, kontrol, dan test case.

## 5. Authentication

- Password disimpan menggunakan password hashing kuat seperti Argon2id atau bcrypt dengan parameter yang sesuai.
- Jangan menyimpan plaintext atau reversible password.
- API menggunakan JWT Bearer Token dengan header `Authorization: Bearer <token>` dan HS256.
- Logout mencabut token melalui tabel revocation; kegagalan baca revocation harus fail-closed.
- Token memiliki expiry dan klaim `jti` untuk pencabutan.
- Implementasi frontend saat ini menyimpan JWT di `localStorage` (`umkm_token`). JavaScript yang berjalan pada origin frontend, termasuk akibat XSS, dapat membaca dan mencuri token; token dapat digunakan sampai expiry atau revocation.
- React meng-escape teks interpolasi secara default, tetapi ini bukan mitigasi XSS menyeluruh. Repository tidak menunjukkan CSP atau sanitizer khusus; jangan menganggap kontrol tersebut sudah tersedia.
- `localStorage` bukan penyimpanan yang terlindung dari XSS. Hindari pola tersebut untuk token berumur panjang; catat kondisi saat ini sebagai risiko sampai ada perubahan yang disetujui dan diuji.
- Reset token acak, disimpan sebagai digest, expiry, sekali pakai.
- Forgot password tidak mengungkap apakah akun terdaftar.
- Registrasi publik hanya membuat customer.
- Admin MFA diwajibkan sebelum produksi.

## 6. Authorization

Setiap request privat memeriksa:
1. Sesi valid.
2. Role memiliki izin.
3. Aktor memiliki resource atau izin eksplisit.
4. Operasi valid untuk status resource saat ini.

Jangan mengandalkan route guard, hidden button, UUID, atau user ID dari browser sebagai pengganti authorization. Gunakan policy/authorization layer yang konsisten.

## 7. API and browser security

- HTTPS pada produksi.
- CORS allowlist per environment; production hanya HTTPS dari `CORS_ALLOWED_ORIGINS` dan menolak wildcard. Credentials CORS tidak diaktifkan karena autentikasi memakai Bearer Token.
- Rate limit.
- Validasi content type dan ukuran request.
- Pagination/filter dibatasi.
- Security headers: CSP, HSTS, X-Content-Type-Options, Referrer-Policy sesuai deployment.
- Error tidak membocorkan stack trace, SQL, path, atau secret.
- CORS diuji untuk origin lokal development dan allowlist production.
- Trusted proxy: jangan mempercayai `X-Forwarded-For` secara default (keputusan owner D3). Trusted proxy hanya dikonfigurasi setelah alamat proxy production diketahui dan diverifikasi. Rate limiting menggunakan `REMOTE_ADDR` via Rack.

## 8. Input/output/database

- Validasi semua input di backend.
- Gunakan ORM/parameterized query.
- Hindari interpolasi input ke SQL.
- Escape output sesuai konteks.
- Hindari rendering HTML tidak tepercaya.
- Allowlist field sort/filter.
- Batasi panjang, jumlah item, ukuran request, dan pagination.
- Terapkan foreign key, unique/check constraint, dan transaksi.
- Frontend validation hanya untuk UX.

## 9. M8 controls

- Customer cancellation uses ownership checks; admin cancellation and shipment actions require admin authorization.
- Payment approval and cancellation lock the order and payment in the same order to prevent both actions succeeding concurrently.
- Pending cancellation blocks proof resubmission and payment approval in the backend.
- Shipment transitions are validated server-side and do not accept arbitrary frontend status values.
- Reservation release, order cancellation, product counters, inventory movement, and audit log are atomic.
- Manual refund operations require admin authorization; customers cannot create or read refund details through the MVP API.
- Refund creation and processing serialize the payment-level limit check with writes; the sum of `pending` and `processed` refunds must not exceed the received payment amount. Rejected refunds do not count.
- Processing requires admin confirmation of the manual transfer and a `reference_number`. Transfer failure leaves the refund pending until resolved or rejected with a note; it is not reported as processed.
- Refund status, payment status and AuditLog updates are atomic. A payment remains `paid` after a partial refund and becomes `refunded` only when processed refunds total the payment amount. Refunds do not change order status or stock.
- Auto-completion only processes shipped orders at least seven days old and is safe to repeat.

## 10. File upload

Untuk bukti transfer:
- Private storage.
- Validasi extension, MIME, signature, dan ukuran.
- Jangan percaya Content-Type dari browser.
- Nama file internal acak.
- Cegah path traversal.
- File tidak boleh dieksekusi.
- Download melalui endpoint dengan authorization.
- Tetapkan retensi dan penghapusan.
- Pertimbangkan malware scanning sesuai risiko dan ketersediaan.

## 10. Payment and inventory integrity

- Backend menghitung harga.
- Bukti upload bukan bukti dana diterima.
- Admin berwenang yang mengesahkan pembayaran.
- Checkout menggunakan idempotency.
- Reservasi stok atomik.
- Concurrency test wajib.
- Payment approval idempotent.
- Reservation tidak double convert/release.
- Voucher usage limit diperiksa transaksional.
- Refund `pending` + `processed` dibatasi dana payment yang diterima; refund `rejected` tidak mengurangi batas. Pemeriksaan agregat dilakukan di dalam transaksi yang terserialisasi agar request bersamaan tidak melewati batas.
- Perubahan stok/payment dicatat.

## 11. SQLite boundaries

- SQLite untuk satu backend instance pada tahap awal.
- WAL tidak membuat SQLite multi-writer.
- Gunakan local disk.
- Aktifkan foreign key dan busy timeout.
- Transaksi singkat.
- Batasi akses file database.
- Database tidak diekspos ke internet.
- Jangan menghapus WAL secara manual.
- Backup melalui mekanisme aman.
- Backup terenkripsi dan akses terbatas.
- Uji restore.
- Evaluasi PostgreSQL saat concurrency atau multi-instance menuntut.

## 12. Secrets and infrastructure

- JWT production secret harus tersedia melalui `JWT_SECRET` atau Rails credentials `jwt.secret`, minimal 32 byte (keputusan owner D10). Aplikasi gagal saat startup bila secret hilang/lemah tanpa membocorkan nilainya. Development/test memakai secret lokal terpisah. Verifikasi konfigurasi sebelum deployment. Aplikasi tidak boleh dijalankan dengan secret production yang hilang atau lemah.
- CORS production wajib menggunakan daftar origin HTTPS eksplisit; konfigurasi kosong, origin tidak valid, HTTP, atau wildcard ditolak.
- Secret melalui environment/secret manager.
- `.env`, credential, private key, database produksi, backup tidak masuk Git.
- `.env.example` boleh dilacak dan hanya memuat placeholder aman.
- Batasi SSH dan akun server.
- Firewall hanya membuka port yang diperlukan.
- Database tidak publik.
- Patch OS dan dependency.
- Pisahkan development, test, production.
- Least privilege untuk proses aplikasi dan backup.

## 13. Logging and incident response

Audit aktivitas:
- Login admin.
- Perubahan akun/role.
- Perubahan harga/stok.
- Payment approval/rejection.
- Cancellation.
- Refund creation, processing, and rejection, including actor, amount, status, and transfer reference where recorded.
- Perubahan setting penting.

Jangan log password, token, secret, atau bukti transfer mentah. Audit log aplikasi bersifat append-only secara konvensi, bukan immutable secara kriptografis. Salin log kritis ke penyimpanan terpisah.

### Production logging (keputusan owner D4)

- `RAILS_LOG_LEVEL=info` atau level yang lebih tinggi untuk production normal.
- Hindari `debug` di production karena dapat mengekspos SQL bind values.
- Konfigurasi aktual harus diverifikasi sebelum deployment.
- `filter_parameters` tidak dianggap sebagai perlindungan SQL bind values — parameter filtering hanya berlaku untuk request parameters, bukan Active Record SQL bind payloads.

### AuditLog protection (keputusan owner D5)

- Model-level protection diterima untuk MVP (`readonly?` pada model `AuditLog` mencegah `update`, `update!`, `destroy`, `destroy!`, `delete` pada record yang sudah tersimpan).
- Bulk operations (`delete_all`, `update_all`, `update_columns`) dan raw SQL dapat melewati perlindungan model-level. Ini bukan database-level immutability.
- Keterbatasan ini dicatat sebagai residual risk. Database trigger ditunda untuk evaluasi hardening berikutnya (M12).

Prosedur insiden:
1. Identifikasi dan klasifikasi.
2. Batasi dampak.
3. Amankan bukti/log.
4. Cabut sesi/credential terkompromi.
5. Pulihkan dari sumber tervalidasi.
6. Periksa integritas data.
7. Dokumentasikan akar masalah dan mitigasi.

## 14. Privacy and retention

- Kumpulkan data minimum.
- Batasi akses berdasarkan kebutuhan.
- Tetapkan retensi data.
- Lindungi backup dan ekspor.
- Jangan mengirim data pribadi ke log/analytics yang tidak diperlukan.
- Penghapusan/anonimisasi mempertimbangkan histori transaksi dan kewajiban hukum.
- Kebijakan final ditinjau terhadap ketentuan perlindungan data yang berlaku.

### Kebijakan retensi data (keputusan owner D2, D7)

| Kategori | Periode retensi | Keterangan |
|----------|-----------------|------------|
| IP address / user-agent (`audit_logs`) | 90 hari | Dihapus atau dianonimkan setelah periode. Mekanisme cleanup menjaga catatan audit lainnya. |
| Bukti pembayaran (`payment_proofs`) | 1 tahun setelah transaksi selesai | File bukti dihapus atau dianonimkan setelah periode. |
| Audit log transaksi | 2 tahun | Catatan audit sistem pertahankan untuk keperluan investigasi. |
| Data pelanggan | Selama akun aktif | Setelah penghapusan akun, evaluasi kewajiban retensi transaksi dan hukum. |

Periode ini adalah kebijakan awal proyek yang harus ditinjau terhadap regulasi dan kebutuhan bisnis sebelum production — tidak diklaim sebagai kepastian kepatuhan hukum.

## 15. Security test checklist

- Customer A tidak dapat mengakses order Customer B.
- Customer tidak dapat mengakses admin API.
- Manipulasi role ditolak.
- SQL injection tidak berhasil.
- XSS tidak dieksekusi.
- Request privat tanpa JWT Bearer Token valid ditolak.
- Origin CORS tidak dikenal ditolak.
- Login rate limit berfungsi.
- File invalid/berbahaya ditolak.
- Proof tidak dapat diakses publik.
- Checkout concurrent tidak oversell.
- Idempotency mencegah order duplikat.
- Approval tidak double-process.
- Refund tidak melebihi dana.
- Secret tidak ditemukan di repository/log.
- Backup dapat dipulihkan.

## 16. Security acceptance

Fitur sensitif memerlukan authentication, authorization, ownership, validation, negative, concurrency (bila relevan), audit, dan regression tests.

## 17. Referensi

Gunakan versi resmi terkini OWASP Top 10, OWASP API Security Top 10, OWASP ASVS, dokumentasi keamanan Rails, dokumentasi SQLite, serta ketentuan perlindungan data pribadi yang berlaku. Referensi bukan bukti sertifikasi atau kepatuhan otomatis.

## 18. PaymentProof Cleanup — Residual Security Considerations

### TOCTOU (Time-of-Check-Time-of-Use)

`PaymentProofCleanupService` melakukan penghapusan file fisik setelah validasi melalui `VerifiedStorageFile.open`. Pola ini memiliki **residual TOCTOU risk** yang tidak dapat dihilangkan sepenuhnya secara portabel:

- Validasi descriptor-based (`VerifiedStorageFile.open` dengan `NOFOLLOW` + `File.identical?`) memastikan file yang dibuka adalah file yang divalidasi.
- `File.unlink(path)` menggunakan path, bukan file descriptor. Window antara validasi dan unlink (biasanya < 1ms) dapat dieksploitasi untuk swap file.
- **Linux**: `NOFOLLOW` tersedia, melindungi `open`; `unlink` tetap path-based.
- **Windows**: `File::NOFOLLOW` tidak tersedia; validasi descriptor tidak memproteksi dari symlink swap.

**Mitigasi yang diterapkan:**
1. Re-validasi tepat sebelum `File.unlink` (minimasi window).
2. Direktori `storage/private/payment_proofs` **wajib** dikunci aksesnya:
   - Linux: mode `0750`, owned by app user.
   - Windows: ACL write hanya untuk app service account + Administrators.
3. `VerifiedStorageFile` menolak symlink component manapun di path relatif root.
4. Logging kegagalan untuk audit trail.

**Asumsi filesystem (wajib dipenuhi deployment):**
- Single-host, local persistent storage (keputusan D9).
- Direktori storage tidak di-mount/bind ulang saat runtime.
- Tidak ada proses lain yang menulis ke direktori storage selain aplikasi.

### Duplicate Reference Protection

Sebelum penghapusan, service memeriksa `PaymentProof.where(storage_key: ...).where.not(id: ...).exists?`. Jika ada referensi lain:
- File **tidak dihapus** (kategori `skipped`).
- Kedua record `PaymentProof` utuh.
- Tidak ada unique index database (collision probability 2^-256 negligible).

### Dry-Run Default

`dry_run: true` adalah default. Eksekusi nyata (`dry_run: false`) **hanya** dijalankan setelah:
1. Dry-run diverifikasi statistiknya.
2. Backup database DAN direktori `storage/private/payment_proofs` tersedia.

### Tidak Ada AuditLog Event

Job ini maintenance sistem, bukan aksi user/admin. Tidak membuat `AuditLog` entry untuk menghindari pollution audit trail 2-tahun. Logging via Rails logger (structured, no PII).

# M7 controls

- Upload memeriksa ukuran, ekstensi yang diizinkan, dan MIME berdasarkan isi file menggunakan Marcel.
- Storage key memakai random token, bukan nama file asli; file disimpan di `storage/private/payment_proofs`.
- Customer dan admin melakukan ownership/role authorization di backend.
- Approval mengunci payment, order, reservation, dan product dalam satu transaksi; state check mencegah double approval.
- Approval mencatat `PaymentVerificationEvent`, `AuditLog`, konversi reservation, pengurangan stok, dan inventory movement secara atomik.
