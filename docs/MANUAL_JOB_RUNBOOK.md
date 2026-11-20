# MANUAL JOB RUNBOOK — Scheduled Jobs (MVP)

**Versi:** 1.0
**Project:** Sistem Informasi Penjualan UMKM
**Status:** Prosedur operasional sementara (tidak recurring schedule otomatis)
**Keputusan owner D1:** Solid Queue ditunda untuk MVP. Kedua job dijalankan manual melalui `bin/rails runner`.

---

## A. Prasyarat

### Direktori backend

Semua perintah dijalankan dari direktori backend:

```bash
cd D:\sistem-penjualan-umkm\backend
```

### Environment

- Rails environment: `development` atau `production` (sesuai target deployment).
- Pastikan `RAILS_ENV` diatur dengan benar sebelum menjalankan perintah.
- Contoh PowerShell: `$env:RAILS_ENV="production"`
- Contoh CMD: `set RAILS_ENV=production`

### Database

- SQLite pada local disk (`storage/production.sqlite3` untuk production, `db/development.sqlite3` untuk development).
- Satu backend instance (keputusan owner D9). Tidak ada shared SQLite multi-host.
- Pastikan database tidak sedang diakses oleh proses Puma lain yang dapat menyebabkan write contention.

### Akses operator

- Operator harus memiliki akses ke terminal/backend host.
- Operator harus memahami status order dan reservasi sebelum menjalankan job.
- Tidak ada autentikasi tambahan untuk `bin/rails runner` — akses ke host dianggap sebagai otorisasi operasional.

---

## B. Inventory Reservation Expiry

### Fungsi job

`InventoryReservationExpiryJob` (backend/app/jobs/inventory_reservation_expiry_job.rb:1-7) mendelegasikan ke `InventoryReservationExpiryService.call` (backend/app/services/inventory_reservation_expiry_service.rb:1-28).

Service:
- Mencari semua `InventoryReservation` dengan `status = "reserved"` dan `expires_at <= sekarang`.
- Untuk setiap reservation yang kedaluwarsa:
  1. Lock baris reservation (`InventoryReservation.lock.find`).
  2. Double-check status dan expiry di dalam transaksi.
  3. Lewati jika bukti pembayaran sudah diunggah sebelum tenggat expiry.
  4. Kurangi `reserved_stock` pada produk terkait (dengan verifikasi `updated == 1`, rollback jika gagal).
  5. Ubah status reservation menjadi `released`, catat `released_at`.
  6. Buat `InventoryMovement` tipe `reservation_release`.
  7. Ubah status payment menjadi `expired`.
  8. Ubah status order menjadi `cancelled`, catat `cancelled_at`.
  9. Buat `AuditLog` untuk setiap langkah yang relevan.

### Kapan dijalankan

- Setiap kali admin ingin membersihkan reservasi stok yang sudah melewati tenggat pembayaran 12 jam.
- Sebelum memverifikasi ketersediaan stok untuk order baru.
- Secara berkala (misalnya setiap beberapa hari) selama MVP, karena tidak ada scheduler otomatis.

### Command aktual

```bash
bin/rails runner "InventoryReservationExpiryJob.perform_now"
```

Atau dengan environment tertentu:

```bash
# PowerShell (Windows)
$env:RAILS_ENV="production"; bin/rails runner "InventoryReservationExpiryJob.perform_now"

# CMD (Windows)
set RAILS_ENV=production
bin/rails runner "InventoryReservationExpiryJob.perform_now"
```

### Hasil yang diharapkan

- Semua reservation yang expired dan tidak memiliki bukti pembayaran akan dilepaskan (`status = "released"`).
- `reserved_stock` pada produk terkait dikurangi sesuai kuantitas reservation.
- Order terkait diubah menjadi `cancelled`, payment menjadi `expired`.
- `InventoryMovement` dan `AuditLog` tercatat.
- Reservation yang masih dalam tenggat atau sudah memiliki bukti pembayaran tidak tersentuh.

### Cara memverifikasi reservation yang sudah expired

```ruby
# Cek reservation yang masih status "reserved" dan expired
bin/rails runner "InventoryReservation.where(status: 'reserved').where('expires_at <= ?', Time.current).each { |r| puts \"#{r.id}: order=#{r.order_id}, product=#{r.product_id}, expires_at=#{r.expires_at}\" }"

# Cek order yang cancelled karena expiry
bin/rails runner "Order.where(status: 'cancelled').each { |o| puts \"#{o.order_number}: status=#{o.status}, cancelled_at=#{o.cancelled_at}\" }"

# Cek payment yang expired
bin/rails runner "Payment.where(status: 'expired').each { |p| puts \"#{p.id}: order=#{p.order_id}, status=#{p.status}\" }"

# Cek inventory movement tipe reservation_release
bin/rails runner "InventoryMovement.where(movement_type: 'reservation_release').each { |m| puts \"#{m.id}: product=#{m.product_id}, qty=#{m.quantity}, ref=#{m.reference}\" }"
```

---

## C. Order Auto-Completion

### Fungsi job

`OrderCompletionJob` (backend/app/jobs/order_completion_job.rb:1-7) mendelegasikan ke `OrderCompletionService.call(now:)` (backend/app/services/order_completion_service.rb:1-12).

Service:
- Mencari semua `Order` dengan `status = "shipped"` dan `shipped_at <= sekarang - 7 hari`.
- Untuk setiap order yang memenuhi syarat:
  1. Lock baris order (`Order.lock.find`).
  2. Double-check status dan `shipped_at` di dalam transaksi.
  3. Ubah status order menjadi `completed`, catat `completed_at`.
  4. Buat `AuditLog` dengan action `order_completed`.

### Ketentuan tujuh hari setelah shipped_at

- Order hanya dapat diselesaikan jika `shipped_at` sudah lewat 7 hari penuh.
- Order harus masih berstatus `shipped` (belum berubah menjadi status lain).
- Fitur dispute/sengketa tidak termasuk dalam MVP (keputusan owner D8). Auto-completion tidak memiliki exception handling untuk sengketa.

### Command aktual

```bash
bin/rails runner "OrderCompletionJob.perform_now"
```

Atau dengan waktu custom (untuk testing):

```bash
bin/rails runner "OrderCompletionJob.perform_now(Time.current)"
```

Atau dengan environment tertentu:

```bash
# PowerShell (Windows)
$env:RAILS_ENV="production"; bin/rails runner "OrderCompletionJob.perform_now"

# CMD (Windows)
set RAILS_ENV=production
bin/rails runner "OrderCompletionJob.perform_now"
```

### Hasil yang diharapkan

- Semua order yang shipped lebih dari 7 hari dan masih status `shipped` akan diubah menjadi `completed`.
- `completed_at` diisi dengan waktu eksekusi.
- `AuditLog` dengan action `order_completed` tercatat untuk setiap order.
- Order yang sudah `completed`, `cancelled`, atau belum 7 hari sejak `shipped_at` tidak tersentuh.

### Cara memverifikasi status pesanan dan audit log

```ruby
# Cek order yang sudah completed
bin/rails runner "Order.where(status: 'completed').each { |o| puts \"#{o.order_number}: status=#{o.status}, completed_at=#{o.completed_at}, shipped_at=#{o.shipped_at}\" }"

# Cek audit log order_completed
bin/rails runner "AuditLog.where(action: 'order_completed').each { |a| puts \"#{a.id}: order=#{a.resource_id}, created_at=#{a.created_at}\" }"

# Cek order shipped yang belum 7 hari (tidak boleh diselesaikan)
bin/rails runner "Order.where(status: 'shipped').where('shipped_at > ?', 7.days.ago).each { |o| puts \"#{o.order_number}: shipped_at=#{o.shipped_at}, hari_sesudah_shipped=#{(Time.current - o.shipped_at).to_i / 1.day}\" }"
```

---

## D. Operational Safety

### Idempotency

Kedua job aman dijalankan berulang kali (keputusan owner D1, PRD section 9):

- `InventoryReservationExpiryService`: double-check `status = "reserved"` di dalam transaksi sebelum mengubah. Reservation yang sudah `released` atau `converted` akan dilewati.
- `OrderCompletionService`: double-check `status = "shipped"` di dalam transaksi sebelum mengubah. Order yang sudah `completed` akan dilewati.
- Tidak ada risiko double-decrement atau double-release stok.

### Risiko menjalankan job bersamaan

- SQLite adalah single writer aktif (AGENTS.md section 9, DATABASE.md section 2). WAL tidak membuat SQLite multi-writer.
- Jika kedua job dijalankan bersamaan (dua terminal/process), satu akan menunggu lock database (busy_timeout 5000ms di database.yml).
- Jika lock tidak dapat diperoleh dalam waktu 5 detik, akan terjadi `SQLite3::BusyException`.
- **Rekomendasi:** Jalankan satu job pada satu waktu. Tunggu job pertama selesai sebelum menjalankan job kedua.

### Perilaku jika terjadi exception

- Semua perubahan dilakukan di dalam `ActiveRecord::Base.transaction`.
- Jika exception terjadi (misalnya `ActiveRecord::Rollback` dari `updated == 1` check), seluruh transaksi untuk reservation/order tersebut di-rollback.
- Order/reservation lain yang diproses dalam `find_each` yang sama tidak terpengaruh (setiap item dalam transaksi terpisah).
- Error akan muncul di terminal/STDOUT.

### Cara memeriksa log

```bash
# Lihat log Rails (development)
tail -f log/development.log

# Lihat log production (STDOUT, biasanya diwrap container/Kamal)
# Tidak ada file log terpisah untuk production kecuali dikonfigurasikan
```

Audit log juga tersimpan di database tabel `audit_logs`:

```ruby
bin/rails runner "AuditLog.where(action: ['reservation_released', 'order_completed', 'payment_expired', 'order_cancelled']).order(created_at: :desc).limit(20).each { |a| puts \"#{a.created_at}: #{a.action} - #{a.resource_type}##{a.resource_id}\" }"
```

### Langkah pemulihan jika eksekusi gagal

1. Jika job gagal di tengah proses (beberapa reservation diproses, beberapa tidak): reservation yang sudah diproses sudah tersimpan, yang belum akan diproses pada eksekusi berikutnya. Tidak perlu rollback manual.
2. Jika order salah di-complete karena data `shipped_at` salah: tidak ada fitur "un-complete" otomatis. Admin harus secara manual menyesuaikan data atau membuat order baru.
3. Jika stok salah dikurangi: admin harus secara manual mengoreksi `stock_on_hand` dan `reserved_stock` pada produk terkait, serta membuat `InventoryMovement` untuk koreksi.
4. Catat semua tindakan pemulihan dalam `AuditLog` jika dilakukan melalui kode, atau catat secara manual di catatan operasional.

---

## E. Jadwal Operasional Sementara

### Rekomendasi frekuensi (prosedur sementara, bukan recurring schedule aktif)

| Job | Frekuensi rekomendasi | Alasan |
|-----|----------------------|--------|
| `InventoryReservationExpiryJob` | Setiap hari (misalnya pagi hari) | Reservasi expired 12 jam setelah checkout. Eksekusi harian cukup untuk membersihkan reservasi yang melewati tenggat. |
| `OrderCompletionJob` | Setiap minggu (misalnya Senin pagi) | Order auto-complete setelah 7 hari dari `shipped_at`. Eksekusi mingguan cukup untuk memproses order yang sudah mencapai batas. |

### Catatan penting

- Ini adalah **prosedur operasional sementara**, bukan recurring schedule yang sudah aktif.
- Tidak ada Solid Queue worker yang berjalan otomatis (keputusan owner D1).
- Operator harus menjalankan command secara manual melalui terminal.
- Aktivasi scheduler otomatis dievaluasi kembali pada tahap pre-production (D1).

---

## F. Batasan

- Tidak ada scheduler otomatis. Kedua job hanya dapat dijalankan manual via `bin/rails runner`.
- Tidak ada worker Solid Queue aktif.
- Keterlambatan eksekusi dapat menyebabkan stok tertahan (reservation yang expired belum dilepaskan) atau pesanan tetap status `shipped` (belum auto-complete).
- SQLite menggunakan single-host persistent storage (keputusan owner D9).
- Fitur dispute/sengketa tidak termasuk dalam MVP (keputusan owner D8). Auto-completion tidak memiliki exception handling untuk sengketa.

## G. AuditLog PII Anonymization

### Fungsi job

`DataRetentionCleanupJob` (backend/app/jobs/data_retention_cleanup_job.rb:1-7) mendelegasikan ke `DataRetentionCleanupService.anonymize_ip_user_agent!` (backend/app/services/data_retention_cleanup_service.rb:1-42).

Service:
- Mencari semua `AuditLog` dengan `created_at <= cutoff` dan (`ip_address` atau `user_agent` masih terisi).
- Membatasi maksimal 100 record per pemanggilan.
- Mengubah `ip_address` dan `user_agent` menjadi `NULL`.
- Record `AuditLog` tetap dipertahankan (tidak dihapus).
- `action`, `user_id`, `created_at`, dan data transaksi lainnya tidak berubah.
- Idempotent: dapat dijalankan berulang kali tanpa efek samping.

### Kapan dijalankan

- Setiap kali ingin membersihkan data PII (IP address dan user-agent) dari audit log yang berusia lebih dari atau sama dengan 90 hari.
- Sebelum melaporkan audit log ke penyimpanan eksternal untuk investigasi jangka panjang.

### Command aktual

```bash
bin/rails runner "DataRetentionCleanupJob.perform_now"
```

Atau dengan cutoff custom (untuk testing):

```bash
bin/rails runner "DataRetentionCleanupJob.perform_now(before: Time.current - 100.days)"
```

Atau dengan environment tertentu:

```bash
# PowerShell (Windows)
$env:RAILS_ENV="production"; bin/rails runner "DataRetentionCleanupJob.perform_now"

# CMD (Windows)
set RAILS_ENV=production
bin/rails runner "DataRetentionCleanupJob.perform_now"
```

### Hasil yang diharapkan

- Satu pemanggilan `DataRetentionCleanupJob.perform_now` menggunakan cutoff default 90 hari sebelumnya (`90.days.ago` dari waktu eksekusi).
- Semua `AuditLog` dengan `created_at` lebih dari atau sama dengan 90 hari yang lalu akan memiliki `ip_address` dan `user_agent` diubah menjadi `NULL`.
- Record `AuditLog` tetap ada dan dapat diakses untuk keperluan investigasi.
- `action`, `user_id`, `created_at` tidak berubah.
- Maksimal 100 record diproses per pemanggilan. Jalankan ulang perintah untuk memproses batch berikutnya.

### Cara memverifikasi hasil

```ruby
# Cek audit log yang sudah dianonimkan
bin/rails runner "AuditLog.where(ip_address: nil, user_agent: nil).where('created_at <= ?', 90.days.ago).each { |a| puts \"#{a.id}: action=#{a.action}, created_at=#{a.created_at}\" }"

# Cek audit log yang belum dianonimkan (masih dalam 90 hari)
bin/rails runner "AuditLog.where('created_at > ?', 90.days.ago).where('ip_address IS NOT NULL OR user_agent IS NOT NULL').each { |a| puts \"#{a.id}: action=#{a.action}, ip=#{a.ip_address}\" }"

# Hitung jumlah record yang perlu dianonimkan
bin/rails runner "puts AuditLog.where('created_at <= ?', 90.days.ago).where('ip_address IS NOT NULL OR user_agent IS NOT NULL').count"
```

### Risiko residual

- `update_all` melewati `readonly?` pada model `AuditLog` (keputusan owner D5 diterima untuk MVP). Ini bukan database-level immutability. Database-level trigger ditunda untuk evaluasi hardening berikutnya (M12).
- Tidak ada mekanisme rollback otomatis setelah `update_all` dieksekusi. Pastikan backup database tersedia sebelum melakukan operasi massal pada produksi.

---

## H. PaymentProof Physical-File Cleanup

### Fungsi job

`PaymentProofCleanupJob` (backend/app/jobs/payment_proof_cleanup_job.rb) mendelegasikan ke `PaymentProofCleanupService.call` (backend/app/services/payment_proof_cleanup_service.rb).

Service:
- Mencari `PaymentProof` yang memenuhi **salah satu** dari tiga kombinasi eligible:
  1. `payments.status = 'paid'` AND `orders.status = 'completed'` AND `orders.completed_at <= cutoff`
  2. `payments.status = 'rejected'` AND `orders.status = 'cancelled'` AND `orders.cancelled_at <= cutoff`
  3. `payments.status = 'expired'` AND `orders.status = 'cancelled'` AND `orders.cancelled_at <= cutoff`
- `cutoff = waktu eksekusi - 1 tahun`
- Membatasi maksimal 100 kandidat per eksekusi.
- Urutan pemrosesan: `created_at` lalu `id` (deterministik).
- Untuk setiap kandidat:
  1. Validasi format `storage_key` (64 hex + ekstensi jpg/jpeg/png/webp).
  2. Cek referensi ganda: jika `PaymentProof` lain menggunakan `storage_key` yang sama -> **skip** (file tidak dihapus).
  3. Buka file melalui `VerifiedStorageFile.open` (validasi path, symlink, ukuran, descriptor).
  4. Tutup file handle.
  5. **Dry-run**: catat sebagai `would_delete`, **jangan** hapus file.
  6. **Eksekusi nyata**: `File.unlink(validated_path)`, catat sebagai `deleted`.
- Tidak mengubah record database (`PaymentProof`, `PaymentVerificationEvent`, `Payment`, `Order`).
- Tidak membuat `AuditLog` event (ini job maintenance, bukan aksi user/admin).

### Kapan dijalankan

- Bulanan (retensi 1 tahun setelah transaksi terminal: `completed_at` atau `cancelled_at`).
- Setelah memverifikasi tidak ada order aktif yang merujuk bukti yang eligible.
- Sebelum backup storage untuk mengurangi ukuran backup.

### Command aktual

```bash
# Dry-run (DEFAULT, aman) -- jalankan SELALU terlebih dahulu
bin/rails runner "PaymentProofCleanupJob.perform_now"

# Dry-run dengan cutoff custom (testing)
bin/rails runner "PaymentProofCleanupJob.perform_now(cutoff: Time.current - 366.days)"

# Eksekusi NYATA -- hanya setelah dry-run diverifikasi
bin/rails runner "PaymentProofCleanupJob.perform_now(dry_run: false)"

# Eksekusi nyata dengan environment tertentu:
# PowerShell (Windows)
$env:RAILS_ENV="production"; bin/rails runner "PaymentProofCleanupJob.perform_now(dry_run: false)"

# CMD (Windows)
set RAILS_ENV=production
bin/rails runner "PaymentProofCleanupJob.perform_now(dry_run: false)"
```

### Prasyarat Keamanan Filesystem (WAJIB)

**Linux/Unix:**
```bash
# Direktori storage harus dimiliki user aplikasi, mode 0750
chown appuser:appgroup storage/private/payment_proofs
chmod 0750 storage/private/payment_proofs
# Hanya app user + group yang bisa write; world no access
```

**Windows (ACL, BUKAN mode POSIX):**
```powershell
# Hapus inheritance, berikan write hanya ke app service account + Administrators
icacls "storage\private\payment_proofs" /inheritance:r
icacls "storage\private\payment_proofs" /grant "APP_USER:(OI)(CI)F"
icacls "storage\private\payment_proofs" /grant "Administrators:(OI)(CI)F"
icacls "storage\private\payment_proofs" /remove "Users" "Everyone"
```

**Deployment harus menjamin:** single-host, local persistent storage (keputusan D9). Tidak shared storage multi-host.

### Hasil yang diharapkan

- **Dry-run**: Statistik `processed`, `would_delete`, `missing`, `failed`, `skipped`. `deleted = 0`. File **tidak** dihapus. Database **tidak** berubah.
- **Eksekusi nyata**: Statistik `processed`, `deleted`, `missing`, `failed`, `skipped`. `would_delete = 0`. File terhapus. Database **tidak** berubah.
- File yang hilang (ENOENT) -> `missing`, **bukan** error.
- Permission error (EACCES/EPERM) -> `failed`, **bukan** `missing`.
- Referensi ganda -> `skipped`, file **tetap ada**, kedua record `PaymentProof` utuh.

### Cara memverifikasi hasil

```ruby
# Cek statistik batch terakhir (dari log Rails)
# tail -f log/development.log | grep PaymentProofCleanup

# Cek file yang seharusnya terhapus
bin/rails runner "
  cutoff = 1.year.ago
  PaymentProof.joins(payment: :order)
    .where(\"(payments.status = 'paid' AND orders.status = 'completed' AND orders.completed_at <= ?) OR (payments.status = 'rejected' AND orders.status = 'cancelled' AND orders.cancelled_at <= ?) OR (payments.status = 'expired' AND orders.status = 'cancelled' AND orders.cancelled_at <= ?)\", cutoff, cutoff, cutoff)
    .each { |p| puts \"#{p.id}: key=#{p.storage_key} exists=#{File.exist?(Rails.root.join('storage','private','payment_proofs',p.storage_key))}\" }
"

# Verifikasi PaymentProof dan PaymentVerificationEvent tetap ada
bin/rails runner "puts PaymentProof.count"
bin/rails runner "puts PaymentVerificationEvent.count"
```

### Risiko Residual (WAJIB DIPAHAMI)

1. **TOCTOU (Time-of-Check-Time-of-Use)**: Window antara `VerifiedStorageFile.open` validasi dan `File.unlink` tidak bisa dihilangkan sepenuhnya (path-based unlink). Mitigasi: re-validasi tepat sebelum unlink, direktori storage `0750`/ACL app-only, symlink ditolak. **Residual risk tetap ada**.

2. **Windows tanpa `File::NOFOLLOW`**: Descriptor validation tidak memproteksi dari symlink swap pada Windows. ACL ketat direktori storage **wajib**.

3. **Direktori storage diganti (mount/bind)**: Tidak termitigasi di application layer. Deployment single-host local disk (D9) mengurangi risiko.

4. **File dihapus eksternal antara dry-run dan eksekusi**: Dry-run `would_delete` -> eksekusi `missing`. Ini perilaku yang diharapkan (idempotent).

5. **Backup SEBELUM eksekusi nyata**: **WAJIB** backup database dan direktori `storage/private/payment_proofs` sebelum menjalankan `dry_run: false` pada production.

### Langkah pemulihan jika eksekusi gagal

1. File terhapus tapi seharusnya tidak: **Tidak bisa dipulihkan otomatis**. Restore dari backup storage.
2. Database tidak berubah -- tidak perlu rollback DB.
3. Job aman dijalankan ulang (idempotent): file yang sudah terhapus -> `missing`; yang gagal permission -> `failed` (perlu perbaiki ACL lalu jalankan ulang).

---

## Referensi

- `docs/DEVELOPMENT_PLAN.md` -- M6, M8, keputusan owner D1
- `docs/DATABASE.md` -- Section 4.5 (inventory_reservations), Section 4.6 (shipments), Section 6 (aturan transaksi)
- `docs/PRD.md` -- Section 6.4 (stok), Section 6.5 (pengiriman dan penyelesaian), Section 9 (FR-34 scheduled job idempotent)
- `docs/SECURITY.md` -- Section 9 (M8 controls), Section 11 (SQLite boundaries), Section 14 (retensi)
- `backend/app/jobs/inventory_reservation_expiry_job.rb`
- `backend/app/jobs/order_completion_job.rb`
- `backend/app/jobs/payment_proof_cleanup_job.rb`
- `backend/app/services/inventory_reservation_expiry_service.rb`
- `backend/app/services/order_completion_service.rb`
- `backend/app/services/payment_proof_cleanup_service.rb`
- `backend/app/services/data_retention_cleanup_service.rb`

---

**PERINGATAN:** Jangan menjalankan job ini terhadap database production tanpa memahami dampaknya. Pastikan backup database DAN direktori storage tersedia sebelum melakukan operasi massal pada produksi. **SELALU jalankan dry-run terlebih dahulu.**