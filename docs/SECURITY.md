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
- Refund dibatasi dana diterima dikurangi refund processed.
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

- JWT production secret harus tersedia melalui `JWT_SECRET` atau Rails credentials `jwt.secret`, minimal 32 byte. Aplikasi gagal saat startup bila secret hilang/lemah tanpa membocorkan nilainya. Development/test memakai secret lokal terpisah.
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
- Refund.
- Perubahan setting penting.

Jangan log password, token, secret, atau bukti transfer mentah. Audit log aplikasi bersifat append-only secara konvensi, bukan immutable secara kriptografis. Salin log kritis ke penyimpanan terpisah.

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
# M7 controls

- Upload memeriksa ukuran, ekstensi yang diizinkan, dan MIME berdasarkan isi file menggunakan Marcel.
- Storage key memakai random token, bukan nama file asli; file disimpan di `storage/private/payment_proofs`.
- Customer dan admin melakukan ownership/role authorization di backend.
- Approval mengunci payment, order, reservation, dan product dalam satu transaksi; state check mencegah double approval.
- Approval mencatat `PaymentVerificationEvent`, `AuditLog`, konversi reservation, pengurangan stok, dan inventory movement secara atomik.
