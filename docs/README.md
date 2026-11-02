# Dokumentasi Sistem Informasi Penjualan UMKM

**Paket dokumentasi:** 1.0.0  
**Status:** Baseline rancangan untuk ditinjau dan disetujui  
**Stack:** React + Vite + TypeScript, Ruby on Rails 8.1.4 API-only, SQLite

## Daftar dokumen

| Dokumen | Fungsi |
|---|---|
| `PRD.md` | Tujuan, ruang lingkup, aktor, kebutuhan, dan aturan bisnis |
| `DATABASE.md` | Tabel, relasi, constraint, transaksi, dan strategi data |
| `API_DOCUMENTATION.md` | Kontrak endpoint, respons, autentikasi, dan state transition |
| `DESIGN.md` | Design system, halaman, struktur frontend, dan UX |
| `SECURITY.md` | Threat model, kontrol keamanan, dan kriteria pengujian |
| `DEVELOPMENT_PLAN.md` | Milestone, urutan implementasi, dan quality gate |
| `AGENTS.md` | Instruksi kerja OpenCode dan aturan perubahan repository |

## Cara menggunakan

1. Letakkan seluruh file Markdown ini di folder `docs` pada repository.
2. Baca seluruh dokumen sebelum meminta AI coding agent mengubah kode.
3. Periksa kembali keputusan yang ditandai **perlu konfirmasi**.
4. Setelah disetujui, jadikan dokumen sebagai baseline implementasi.
5. Setiap perubahan aturan bisnis, skema, API, atau keamanan harus memperbarui dokumen terkait.

## Status dan batasan

Dokumen ini adalah rancangan profesional untuk proyek akademik dan implementasi awal, bukan bukti bahwa aplikasi telah selesai, telah diuji, tersertifikasi, atau siap produksi. Implementasi harus diverifikasi terhadap repository, versi dependency, lingkungan deployment, dan hasil pengujian aktual.

## Keputusan dasar yang telah dibahas

- Satu toko UMKM dengan penjualan online.
- Role: `admin` dan `customer`.
- Pembayaran MVP: transfer bank manual, diverifikasi admin.
- Pengiriman MVP: Reguler dan Express, dikelola manual.
- Tidak termasuk payment gateway, COD, atau integrasi API kurir pada MVP.
- Batas pembayaran: 12 jam.
- Penyelesaian otomatis: tujuh hari sejak pengiriman, dengan pemeriksaan kondisi.
- Frontend React + Vite + TypeScript.
- Backend Ruby on Rails 8.1.4 API-only.
- Database awal SQLite untuk satu backend instance.
- Desain Clean White & Smoke Grey dengan aksen biru.
