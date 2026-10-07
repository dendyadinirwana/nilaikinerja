# NilaiKinerja — Panduan Instalasi & Penggunaan (macOS)

Aplikasi pencatatan kinerja ASN berbasis hardware notch MacBook (Apple Silicon M1/M2/M3/M4) dengan pendamping maskot Mochi, integrasi drag & drop cerdas, dan Asisten AI lokal.

---

## 📋 Prasyarat Sistem

1. **macOS**: macOS 14.0 (Sonoma) atau macOS 15+ (Sequoia).
2. **Perangkat**: Dioptimalkan untuk MacBook Pro / Air ber-notch (M1/M2/M3/M4). Mendukung pula layar eksternal (mode Dynamic Island / floating capsule).
3. **Toolchain Pengembang**: 
   - Xcode Command Line Tools (Swift 5.9+).
   - Pastikan terpasang dengan menjalankan di Terminal:
     ```bash
     xcode-select --install
     ```
4. **Backend AI (Opsional untuk Fitur Chat)**:
   - 9router lokal atau gateway OpenAI-compatible (default: `http://localhost:20128/v1`).

---

## 🚀 Panduan Instalasi Cepat (Step-by-Step)

### 1. Buka Terminal dan Masuk ke Direktori Proyek

```bash
cd ~/dev/nilaikinerja
```

### 2. Kompilasi Aplikasi (Build Release)

Jalankan skrip build otomatis:

```bash
./build.sh release
```
*Skrip ini akan mengompilasi binary Swift secara teroptimasi (`-O`), menyusun bundle `NilaiKinerja.app`, menyematkan ikon resmi Mochi (`AppIcon.icns`), dan menandatangani bundle secara ad-hoc.*

### 3. Jalankan Pengujian Otomatis (Self-Test)

Pastikan seluruh logika state machine dan integrasi AI berfungsi 100%:

```bash
# Uji seluruh modul aplikasi (163 assertions)
./dist/NilaiKinerja.app/Contents/MacOS/NilaiKinerja --selftest

# Uji kesiapan koneksi AI
./dist/NilaiKinerja.app/Contents/MacOS/NilaiKinerja --selftest-ai
```
*(Keduanya harus menghasilkan status `PASS`)*.

### 4. Salin Aplikasi ke Folder `/Applications`

Pasang aplikasi ke sistem macOS dan perbarui signature:

```bash
# Hapus instalasi lama jika ada
rm -rf /Applications/NilaiKinerja.app

# Salin aplikasi terbaru
cp -R dist/NilaiKinerja.app /Applications/NilaiKinerja.app

# Tanda tangani ulang bundle di sistem
codesign --force --deep --sign - /Applications/NilaiKinerja.app

# Refresh cache ikon Finder/Dock
touch /Applications/NilaiKinerja.app
```

### 5. Jalankan Aplikasi

Jalankan langsung melalui Spotlight (`Cmd + Space` lalu ketik `Nilai Kinerja`), klik di folder Applications, atau via Terminal:

```bash
open /Applications/NilaiKinerja.app
```

---

## 🔒 Izin Akses macOS (Penting)

Agar aplikasi dapat mendeteksi kursor kursor saat idle di notch dan menerima gesture drag-and-drop dari Finder, berikan izin Aksesibilitas:

1. Buka **System Settings** (Pengaturan Sistem) ➔ **Privacy & Security** (Privasi & Keamanan).
2. Pilih menu **Accessibility** (Aksesibilitas).
3. Aktifkan sakelar di samping **Nilai Kinerja**. Jika belum muncul, klik tombol `+` lalu pilih `/Applications/NilaiKinerja.app`.

---

## 🎮 Panduan Interaksi & Fitur Utama

### 1. Interaksi 3-State Notch (MacBook M4 Native)
* **State 1 — Idle (Default):**
  - Tampilan menyatu murni dengan ukuran fisik hardware notch.
  - Terdapat garis tepi lembut bercahaya (*glowing Sky Blue border* `#60A5FA`).
  - Maskot Mochi dan teks disembunyikan agar layar tetap bersih dan minimalis.
* **State 2 — Idle Hover (Preview 1 Detik):**
  - Dekatkan kursor ke area notch ➔ notch mekar horizontal menjadi kapsul.
  - Maskot Mini Mochi dan counter capaian harian muncul.
  - **Aturan Dwell 1 Detik:** Jika kursor keluar sebelum 1 detik, kapsul langsung surut kembali ke State 1.
  - **Quick Expand:** Klik kapsul saat preview untuk langsung mekar instan tanpa menunggu 1 detik.
* **State 3 — Expanded (Panel Penuh):**
  - Jika kursor menetap di notch selama 1 detik penuh, panel mekar ke bawah (lebar 640pt).
  - Berisi Dashboard Kinerja, Daftar Tugas, Form Kegiatan, dan Asisten AI.
  - Klik tab header (*Tasks, Chat, Form, Settings*) tetap berada di mode Expanded.
  - Saat kursor keluar dari seluruh area panel, panel akan otomatis tertutup kembali ke State 1 sesuai timer di Pengaturan.

### 2. Drag & Drop File Langsung ke Notch
* Tarik berkas apa pun (PDF laporan, foto dokumentasi `.png`/`.jpg`, docx, xlsx) dari Finder langsung ke notch:
  - Notch otomatis langsung mekar ke mode Expanded tanpa jeda 1 detik.
  - Form **Tambah Kegiatan** otomatis terisi:
    - Judul otomatis dirapikan dari nama berkas.
    - Waktu default otomatis 1 jam ke depan.
    - Berkas otomatis terlampir sebagai dokumen pendukung bukti kinerja.
  - Mochi merayakan berkas yang diterima dengan animasi gembira.

### 3. Asisten AI & Model Selector
* Masuk ke tab **Chat AI** (`Cmd + 3`):
  - Area percakapan bersih tanpa banner yang mengganggu.
  - Di bawah kolom input chat, terdapat dropdown **Model Selector** rata kiri dengan indikator titik biru dan chevron.
  - Pilih model instan: *antigravity*, *chatgpt*, *claude*, *grok*, *gemini*, atau model yang terdeteksi dari 9router lokal.

### 4. Tombol Pintasan Keyboard (Shortcuts)
Saat panel sedang terbuka:
- `Cmd + 1` : Layar Utama (Home & Maskot Mochi)
- `Cmd + 2` : Daftar Kegiatan Hari Ini
- `Cmd + 3` : Asisten AI
- `Cmd + 4` : Form Tambah Kegiatan Cepat
- `Tab` / `Shift + Tab` : Pindah antar tab menu
- `←` / `→` : Navigasi layar

---

## 🛠️ Pemeliharaan & Troubleshooting

| Gejala | Solusi |
|---|---|
| Notch tidak merespons hover mouse | Pastikan izin Aksesibilitas (*Accessibility*) di System Settings sudah aktif untuk Nilai Kinerja. |
| Panel tidak mau mekar penuh saat di-hover | Pastikan kursor ditahan diam di atas notch selama **1 detik penuh**. |
| Chat AI menampilkan pesan error koneksi | Pastikan service 9router di `http://localhost:20128/v1` aktif. Cek URL endpoint di tab Pengaturan (`Cmd + 1` lalu klik ikon gear). |
| Reset total proses aplikasi | Jalankan di Terminal: `killall NilaiKinerja && open /Applications/NilaiKinerja.app` |

---

*Hak Cipta & Lisensi: NilaiKinerja dikembangkan untuk penggunaan operasional internal ASN. Aset karakter Mochi dilindungi dan dikompilasi secara privat (non-distributable).*
