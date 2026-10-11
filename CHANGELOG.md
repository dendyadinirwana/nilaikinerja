# Changelog

Semua perubahan penting pada proyek **NilaiKinerja** dicatat dalam dokumen ini.

Format changelog ini mengacu pada [Keep a Changelog](https://keepachangelog.com/id/1.0.0/), dan mengikuti standar versi [Semantic Versioning](https://semver.org/).

---

## [1.0.0] - 2026-10-11

Rilis publik pertama **NilaiKinerja** — aplikasi pencatatan kinerja ASN berbasis hardware notch MacBook dengan maskot 3D reaktif dan kecerdasan buatan lokal.

### Ditambahkan (Added)
- **3-State Notch Interaction Engine**:
  - **State 1 (Idle):** Menyesuaikan ukuran fisik cutout hardware notch MacBook M4/M3/M2/M1 dengan garis tepi bercahaya (*glowing Sky Blue border* `#60A5FA`).
  - **State 2 (Idle Hover):** Mekar horizontal menjadi kapsul preview dengan robot mini dan counter tugas harian, didukung *dwell timer* (default 1.0 detik).
  - **State 3 (Expanded):** Mekar penuh ke bawah (lebar 640pt) menampilkan panggung robot utama, daftar tugas, form kinerja, dan chat AI.
- **Maskot 3D Robot Head Terintegrasi**:
  - Mengadopsi model 3D TV Robot Head dari `fayazara/robot-heads` berlisensi penuh MIT.
  - Simulasi fisika pegas (*damped spring physics*) pada antena dan kepala.
  - *Cursor Aware Tracking*: Kepala dan mata LED robot menoleh mengikuti posisi kursor mouse secara halus (40 FPS throttled).
  - Interaksi klik responsif: Robot melompat dan berputar 360 derajat (*hop with spin*) dengan ekspresi gembira `^ ^`.
  - 8 ragam ekspresi kontekstual: `idle`, `working`, `thinking`, `searching`, `speaking`, `listening`, `happy`, `error`, dan `sleeping`.
- **Smart File Drag & Drop Ingestion**:
  - Tarik berkas apa pun (PDF, gambar dokumen, DOCX, XLSX) langsung ke notch untuk otomatis membuka dan mengisi formulir **Tambah Kegiatan**.
  - Judul kegiatan dibersihkan otomatis dari nama berkas.
  - Durasi kegiatan default otomatis 1 jam ke depan.
  - Berkas otomatis terlampir sebagai bukti kinerja yang tersimpan di folder aman.
- **Asisten AI Terintegrasi (OpenAI-Compatible)**:
  - Antarmuka chat AI minimalis di dalam notch.
  - Dropdown **Model Selector** di bawah kolom input untuk berganti model secara instan.
  - Kompatibel dengan semua endpoint LLM: 9router lokal, Ollama, LM Studio, Groq, vLLM, dan OpenAI resmi.
- **Halaman Pengaturan Multi-Tab**:
  - Terorganisir dalam tab kontekstual dengan animasi sliding pill tanpa border stroke:
    1. **Notch & Interaksi:** Pengaturan toggle glow, intensitas cahaya, dwell timer, ukuran kapsul, lebar panel, dan auto-collapse delay.
    2. **Asisten AI:** Konfigurasi Base URL API, API Key, dan model default.
    3. **Kinerja & Berkas:** Jam kerja ASN, hari kerja aktif, pengingat checkpoint berkala (15m–90m), suara notifikasi, dan pemilih folder lampiran.
    4. **Tentang:** Informasi versi, lisensi MIT, tautan repository, dan status OTA update.
- **Standarisasi Kontrol Antarmuka**:
  - Seluruh tombol CTA dan kolom input field distandarisasi setinggi `36pt`.
  - Toggle switch On/Off diratakan ke sisi kanan (*flush right*).
- **Otomasi Build & Distribusi**:
  - Skrip kompilasi mandiri `build.sh` tanpa dependensi Xcode IDE.
  - Ikon aplikasi resmi native macOS (`Resources/AppIcon.icns`).
  - Alur CI/CD GitHub Actions (`.github/workflows/release.yml`) untuk rilis tag otomatis.

### Diubah (Changed)
- Mengganti maskot Mochi Coucou (yang memiliki restriksi hak cipta karakter) dengan `robot-heads` agar repositori 100% legal dan bebas didistribusikan di bawah lisensi MIT.
- Menghapus slider stagger animasi demi menyederhanakan antarmuka.
- Menggantikan sistem logging debug `NSLog` berat dengan `NKLog` yang di-gate via env flag.

### Diperbaiki (Fixed)
- Memperbaiki bug hit-test AppKit pada koordinat notch yang sebelumnya menyebabkan kursor click-through tembus ke desktop saat drag berkas.
- Memperbaiki bug auto-collapse agar panel kembali tertutup otomatis sesuai delay saat kursor ditinggalkan.
- Memperbaiki issue di mana klik pada tab header saat expanded sempat menurunkan paksa status ke idle hover.
- Memperbaiki pembatalan instan State 2 ketika kursor keluar sebelum 1 detik tanpa memicu pembukaan panel expanded yang tidak disengaja.

---

[1.0.0]: https://github.com/dendyadinirwana/nilaikinerja/releases/tag/v1.0.0
