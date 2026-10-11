# Changelog

Semua perubahan penting pada proyek **NilaiKinerja** dicatat dalam dokumen ini.

Format changelog ini mengacu pada [Keep a Changelog](https://keepachangelog.com/id/1.0.0/), dan mengikuti standar versi [Semantic Versioning](https://semver.org/).

---

## [1.0.0] - 2026-10-11

Rilis publik perdana **NilaiKinerja** — aplikasi pencatatan kinerja harian ASN modern berbasis hardware notch MacBook dengan maskot 3D reaktif, inspeksi berkas cerdas, dan asisten AI lokal.

### Ditambahkan (Added)
- **3-State Notch Interaction Engine**:
  - **State 1 (Idle):** Menyesuaikan ukuran fisik cutout hardware notch MacBook murni (hitam pekat) dengan garis tepi bercahaya (*glowing Sky Blue border* `#60A5FA`).
  - **State 2 (Idle Hover):** Mekar horizontal menjadi kapsul preview dengan robot mini dan counter tugas harian, didukung *dwell timer* (default 1.0 detik).
  - **State 3 (Expanded):** Mekar penuh ke bawah (lebar 640pt) menampilkan panggung robot utama, daftar tugas, form kinerja, dan chat AI.
- **Maskot 3D Robot Head Terintegrasi (100% Lisensi MIT)**:
  - Mengadopsi model 3D TV Robot Head dari `fayazara/robot-heads` berlisensi murni MIT tanpa restriksi aset non-komersial.
  - Simulasi fisika pegas (*damped spring physics*) pada antena dan kepala.
  - *Cursor Aware Tracking*: Kepala dan mata LED robot menoleh mengikuti posisi kursor mouse secara halus (40 FPS throttled).
  - Interaksi klik responsif: Robot melompat dan berputar 360 derajat (*hop with spin*) dengan ekspresi gembira `^ ^`.
  - 8 ragam ekspresi kontekstual: `idle`, `working`, `thinking`, `searching`, `speaking`, `listening`, `happy`, `error`, dan `sleeping`.
- **Inspeksi Biner & Validasi Anti-Spoofing (`FileContentValidator`)**:
  - Memeriksa langsung *magic bytes* biner berkas hingga 8 KB pertama (bukan sekadar membaca ekstensi nama file).
  - Menolak otomatis berkas biner berbahaya / terselubung (Windows Executable `MZ`/PE, Linux `ELF`, macOS `Mach-O`, dan skrip shell `#!`).
  - Memverifikasi keaslian format dokumen asli: PDF (`%PDF-`), OpenXML zip packages (DOCX dengan `word/`, PPTX dengan `ppt/`, XLSX dengan `xl/`), OLE legacy (DOC, XLS, PPT), dan format gambar (PNG, JPEG, GIF, WebP, HEIC, TIFF, BMP, SVG).
  - Berkas yang dimanipulasi ekstensinya otomatis ditolak dan memicu Robot Head ke state `.error` (mata merah `X X`, gelombang peringatan, dan suara alert).
- **Mode Auto-Scanning Cerdas (1.5s)**:
  - Saat berkas di-drop, Robot Head masuk ke mode pemindaian aktif (`.searching`) dengan sensor radar cyan berputar dan status *"Memindai & Memverifikasi [Nama Berkas]..."*.
  - Setelah verifikasi biner tervalidasi, form kegiatan otomatis meluncur mekar dengan animasi spring mulus.
- **Dukungan Format Dokumen Lengkap**:
  - Mendukung berkas presentasi (PPTX, PPT, Keynote `.key`, ODP).
  - Mendukung berkas dokumen kerja (PDF, Word DOCX/DOC, RTF, ODT, Pages, TXT, Markdown).
  - Mendukung berkas data (XLSX, XLS, CSV, ODS, Numbers).
  - Mendukung seluruh format gambar dokumentasi kinerja.
  - Pemetaan ikon cerdas pada form kegiatan (`doc.text.fill`, `play.rectangle.fill`, `tablecells.fill`, `doc.plaintext.fill`, `photo.fill`).
- **Sistem Izin macOS Terpadu (`SystemPermissionManager`)**:
  - Meminta izin sistem resmi macOS secara otomatis pada peluncuran pertama (*first launch*): Aksesibilitas (pemantauan mouse global & drag-drop) dan Pemberitahuan (pengingat checkpoint berkala).
  - Kartu kontrol status izin sistem pada Tab Pengaturan (Tentang) dengan tautan langsung ke *macOS System Settings*.
- **In-App OTA Updater**:
  - Integrasi GitHub Releases API (`dendyadinirwana/nilaikinerja`) untuk memeriksa versi terbaru.
  - Pembanding SemVer otomatis, penampil catatan rilis, progres pengunduhan, dan script penimpa bundle `/tmp/nk_relaunch_<pid>.sh`.
- **Asisten AI Terintegrasi (OpenAI-Compatible)**:
  - Antarmuka chat AI minimalis di dalam notch (`Cmd + 3`).
  - Dropdown **Model Selector** di bawah kolom input untuk berganti model secara instan.
  - Kompatibel dengan semua endpoint LLM: 9router lokal, Ollama, LM Studio, Groq, vLLM, OpenRouter, dan OpenAI.
- **Halaman Pengaturan Multi-Tab (36pt Standard)**:
  - Terorganisir dalam 4 tab kontekstual tanpa border stroke: *Notch & Interaksi*, *Asisten AI*, *Kinerja & Berkas*, dan *Tentang*.
  - Seluruh tombol aksi CTA dan input field single-line distandarisasi setinggi tepat `36pt`.

### Diubah (Changed)
- **Kalibrasi Proksimitas Drag Awareness**:
  - Membatasi zona deteksi saat idle hanya di lingkar perimeter terdekat notch (`dx: -60, dy: -36`), sehingga drag biasa di jendela Finder, browser, atau desktop tidak memicu pembukaan notch secara tidak disengaja.
  - Saat panel mekar, zona tahan mencakup seluruh bodi kartu 640pt dengan jeda penutupan yang stabil (tidak terburu-buru).
- **Pembersihan Dead Code & Reduksi Aset**:
  - Menghapus aset non-komersial lama (Mood Mates) dan decoder APNG lawas, menghemat ruang disk dan menghilangkan ribuan baris kode usang.
  - Zero compiler warnings pada kompilasi Swift.

### Diperbaiki (Fixed)
- Memperbaiki ketepatan presisi simetris animasi mekar notch (*center-anchored* `.top` alignment menggantikan `.topLeading` yang sempat meluncur miring).
- Memasang komponen `AttachmentDropView` (`DropView`) native di seluruh permukaan expanded notch dan panggung beranda robot, mengatasi kendala di mana berkas yang dilepas sempat tidak merespons pada *non-activating accessory window*.
- Menambahkan *debouncing* pada penerimaan drop (800ms) untuk mencegah penanganan berkas ganda dan menghilangkan efek *freeze*.
- Memperbaiki tag perataan tabel laporan Microsoft Word (`.docx`) pada `DocxWriter.swift`.
- Memperbaiki issue demosi status header saat diklik dalam mode expanded.

---

[1.0.0]: https://github.com/dendyadinirwana/nilaikinerja/releases/tag/v1.0.0
