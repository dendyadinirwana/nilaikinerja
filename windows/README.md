# NilaiKinerja (Windows Edition) 🖥️⚡

> **Aplikasi Rekap Capaian Kinerja Harian ASN & Profesional Modern untuk Windows 10/11.**
> Menghadirkan konsep *Top-Center Floating Island* yang elegan, maskot 3D TV-Headed Robot interaktif, validasi biner dokumen anti-spoofing, ekspor resmi Microsoft Word (`.docx`), dan Asisten AI lokal.

[![GitHub Release](https://img.shields.io/github/v/release/dendyadinirwana/nilaikinerja-windows?color=3B82F6&logo=windows&label=Windows%20Release)](https://github.com/dendyadinirwana/nilaikinerja-windows/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## 📥 Unduh Langsung (Siap Pakai untuk Windows)

Unduh installer resmi dari halaman [GitHub Releases](https://github.com/dendyadinirwana/nilaikinerja-windows/releases/tag/v1.0.0):

| Berkas Installer | Ukuran | Keterangan | Tautan Unduh |
| :--- | :--- | :--- | :--- |
| **`NilaiKinerja_1.0.0_x64-setup.exe`** | **1.52 MB** | Installer mandiri NSIS (*Disarankan*) | [**Unduh .exe**](https://github.com/dendyadinirwana/nilaikinerja-windows/releases/download/v1.0.0/NilaiKinerja_1.0.0_x64-setup.exe) |
| **`NilaiKinerja_1.0.0_x64_en-US.msi`** | **2.20 MB** | Paket Windows Installer MSI | [**Unduh .msi**](https://github.com/dendyadinirwana/nilaikinerja-windows/releases/download/v1.0.0/NilaiKinerja_1.0.0_x64_en-US.msi) |

*Persyaratan Sistem: Windows 10 / Windows 11 (64-bit).*

---

## 🌟 Fitur Utama

### 1. 🏝️ Top-Center Floating Island (Dynamic Island Windows)
- **Idle State:** Kapsul hitam melayang minimalis menempel di tepi atas tengah layar monitor dengan pendaran cahaya (*glowing sky-blue border* `#60A5FA`).
- **Expanded State:** Mekar mulus ke bawah menjadi kartu kontrol 660pt yang menampilkan statistik harian, panggung 3D robot, formulir pencatatan kinerja, dan asisten AI.
- **Always-On-Top & Click-Through:** Tidak mengganggu multitasking aplikasi lain saat dalam posisi *Idle*.

### 2. 🤖 Maskot 3D TV Robot Head Reaktif (100% MIT)
- Berbasis engine grafis 3D Canvas murni dari [`fayazara/robot-heads`](https://github.com/fayazara/robot-heads).
- **Interaksi Sentuh:** Klik robot untuk memicu lompat dan putar 360 derajat (*hop with spin*) dengan ekspresi gembira `happy`.
- **Ragam Ekspresi Kontekstual:** `idle`, `working`, `thinking`, `searching`, `speaking`, `happy`, `error`, dan `sleeping` (otomatis tidur di luar jam kerja).

### 3. 📂 Smart File Drag & Drop + Inspeksi Biner Magic-Byte
- Tarik dokumen kerja langsung ke panel untuk mencatat kegiatan secara otomatis.
- **Inspeksi Biner (Rust Backend):** Membedah tanda tangan biner hingga 8 KB pertama:
  - Menolak executable berbahaya / terselubung (Windows `MZ`/PE `.exe`, Linux `ELF`, macOS `Mach-O`, shell script `#!`).
  - Memverifikasi paket zip dokumen OpenXML (Word `docx`, Excel `xlsx`, PowerPoint `pptx`).
  - Mendukung format PDF, teks/markdown, serta aneka gambar dokumentasi (PNG, JPG, WebP, GIF, BMP).
- **Mode Auto-Scanning (1.5 detik):** Robot beralih ke state `searching` dengan animasi radar pemindai sebelum formulir kegiatan dibuka.

### 4. 📄 Ekspor Resmi Dokumen Microsoft Word (`.docx`)
- Ekspor rekapitulasi capaian kinerja harian ke tabel formal `.docx` dalam satu klik:
  - Kolom: `No | Waktu | Kegiatan | Hasil / Detail | Dokumen Pendukung`.
  - Terhitung total durasi akumulasi jam dan menit kerja.

### 5. 🧠 Asisten AI Lokal (OpenAI-Compatible)
- Terhubung langsung ke runner AI lokal (Ollama di `http://localhost:11434/v1`, LM Studio) maupun provider remote via API Key.
- Tombol satu-klik **"Catat ke Kinerja"** untuk mentransfer rumusan AI langsung ke form kegiatan.

---

## 🛠️ Arsitektur & Teknologi

- **Framework:** [Tauri v2](https://v2.tauri.app/) (Arsitektur performa tinggi, konsumsi RAM rendah ~15 MB).
- **Backend:** Rust (File I/O, window sizing, Magic-Byte Validator, system explorer integration).
- **Frontend:** React 19 + TypeScript + Tailwind CSS v4 + Vite.
- **Prinsip:** 100% *Local-First*, *Zero-Telemetry*, tidak ada pengumpulan data privasi.

---

## 🚀 Membangun Aplikasi dari Source Code

### Prasyarat:
- [Node.js](https://nodejs.org/) v20+ & [pnpm](https://pnpm.io/)
- [Rust](https://rustup.rs/) (Toolchain `stable-x86_64-pc-windows-msvc` untuk Windows)

```bash
# 1. Clone repositori
git clone https://github.com/dendyadinirwana/nilaikinerja-windows.git
cd nilaikinerja-windows

# 2. Pasang dependensi frontend
pnpm install

# 3. Jalankan mode pengembangan desktop
pnpm tauri dev

# 4. Bangun paket installer produksi (.exe dan .msi)
pnpm tauri build
```

---

## 📄 Lisensi & Hak Cipta

Proyek ini didistribusikan di bawah lisensi terbuka [MIT License](LICENSE).  
Hak Cipta © 2026 **nirwna**.
