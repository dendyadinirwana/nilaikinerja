# NilaiKinerja — Panduan Instalasi & Penggunaan (macOS)

Aplikasi pencatatan kinerja ASN berbasis hardware notch MacBook (Apple Silicon M1/M2/M3/M4) dengan pendamping robot 3D (fayazara/robot-heads), smart drag & drop, dan Asisten AI.

---

## 📋 Prasyarat Sistem

1. **macOS**: macOS 14.0 (Sonoma) atau macOS 15+ (Sequoia).
2. **Perangkat**: MacBook Pro / Air (M1/M2/M3/M4) atau Mac dengan layar eksternal.
3. **Backend AI (Opsional)**: Layanan LLM apa pun yang kompatibel dengan format OpenAI API (seperti OpenAI resmi, Ollama, LM Studio, Groq, vLLM, OpenRouter, atau server API lokal lainnya).

---

## 🚀 Cara Pasang di MacBook (Instalasi Cepat)

Jika kamu mentransfer file `NilaiKinerja.app` (via AirDrop, Flashdisk, atau Network Share):

### 1. Salin Aplikasi ke Folder Applications
Pindahkan `NilaiKinerja.app` ke dalam folder **/Applications** (Aplikasi).

### 2. Berikan Izin Gatekeeper macOS (Cukup 1x)
Karena aplikasi didistribusikan secara internal tanpa sertifikat Apple Developer berbayar, buka **Terminal** dan jalankan perintah ini sekali saja untuk melepas tanda karantina macOS:

```bash
xattr -cr /Applications/NilaiKinerja.app
```

### 3. Buka Aplikasi
Buka aplikasi melalui Spotlight (`Cmd + Space` ketik `Nilai Kinerja`) atau jalankan via Terminal:

```bash
open /Applications/NilaiKinerja.app
```

---

## 🔒 Izin Akses macOS (Wajib Diaktifkan)

Agar aplikasi dapat mendeteksi kursor kursor di area notch dan menerima gesture drag-and-drop:

1. Buka **System Settings** (Pengaturan Sistem) ➔ **Privacy & Security** (Privasi & Keamanan).
2. Pilih menu **Accessibility** (Aksesibilitas).
3. Aktifkan centang/toggle untuk **Nilai Kinerja**.  
   *(Jika belum muncul di daftar, klik tanda `+` lalu pilih `NilaiKinerja.app` dari folder `/Applications`).*

---

## ⚙️ Pengaturan Endpoint AI (Opsional)

Jika ingin menggunakan fitur Asisten AI:
1. Buka panel NilaiKinerja, masuk ke menu **Pengaturan** (ikon gear di kanan atas).
2. Di bagian **Koneksi AI**, masukkan endpoint API yang kamu gunakan:
   - **Base URL**: Masukkan URL endpoint OpenAI-compatible milikmu  
     *(Contoh: `http://localhost:11434/v1` untuk Ollama, `http://localhost:1234/v1` untuk LM Studio, `https://api.openai.com/v1`, atau gateway custom).*
   - **API Key**: Masukkan API key jika diperlukan (bisa dikosongkan jika server lokal tidak memakai autentikasi).
   - **Model**: Pilih atau ketik nama model yang ingin digunakan.

---

## 🎮 Cara Penggunaan & Fitur Utama

### 1. Interaksi 3-State Notch
* **State 1 — Idle (Default):**  
  Menyatu dengan notch MacBook (hitam pekat) dihiasi garis tepi glowing halus. Robot dan teks tersembunyi agar layar bersih.
* **State 2 — Idle Hover (Preview 1 Detik):**  
  Dekatkan mouse ke notch ➔ notch mekar menjadi kapsul, menampilkan Mini Robot dan counter tugas.  
  - *Jika mouse keluar sebelum 1 detik:* Langsung surut kembali ke Idle.
  - *Tap/Klik Cepat:* Klik kapsul untuk langsung mekar tanpa menunggu 1 detik.
* **State 3 — Expanded (Panel Penuh):**  
  Tahan mouse di notch selama 1 detik penuh ➔ panel mekar ke bawah (lebar 640pt) menampilkan Dashboard Kinerja, Tugas, Form Kegiatan, dan Chat AI. Panel akan tertutup otomatis saat kursor ditinggalkan.

### 2. Drag & Drop Berkas ke Notch
Tarik berkas apa pun (PDF laporan, foto dokumentasi `.png`/`.jpg`, Word, Excel) langsung ke notch:
- Notch otomatis langsung mekar seketika.
- Form **Tambah Kegiatan** otomatis terisi (judul diambil dari nama berkas, durasi default 1 jam, dan berkas otomatis terlampir).
- Robot akan merayakan berkas yang berhasil diterima.

### 3. Asisten AI & Model Selector
- Akses menu chat via tab header atau shortcut `Cmd + 3`.
- Di bawah kolom input chat, terdapat dropdown **Model Selector** untuk berganti model AI dengan cepat.

### 4. Tombol Pintasan (Keyboard Shortcuts)
Saat panel terbuka:
- `Cmd + 1` : Home / Maskot Robot
- `Cmd + 2` : Daftar Kegiatan Hari Ini
- `Cmd + 3` : Asisten AI
- `Cmd + 4` : Form Tambah Kegiatan
- `Tab` / `Shift + Tab` : Pindah antar menu
- `←` / `→` : Navigasi layar

---

## 🛠️ Pemecahan Masalah (Troubleshooting)

| Kendala | Solusi |
|---|---|
| Notch tidak merespons hover mouse | Pastikan izin di **System Settings ➔ Privacy & Security ➔ Accessibility** sudah aktif. |
| Muncul pesan "App is damaged / cannot be opened" | Jalankan perintah `xattr -cr /Applications/NilaiKinerja.app` di Terminal untuk menghapus karantina macOS. |
| Panel tidak menutup otomatis | Panel sengaja tetap terbuka jika dibuka lewat klik ikon Menu Bar (mode Pin). Klik kembali ikon menu bar untuk menutupnya. |
| Restart aplikasi | Buka Terminal: `killall NilaiKinerja && open /Applications/NilaiKinerja.app` |

---

*(Catatan: Aplikasi ini dikembangkan untuk kebutuhan operasional internal ASN).*

---

## 📄 Lisensi & Legalitas
NilaiKinerja dan komponen animasi 3D Robot Head (`fayazara/robot-heads` oleh Fayaz Ahmed) dilisensikan secara penuh di bawah **MIT License**. Bebas didistribusikan, dimodifikasi, dan digunakan tanpa batasan aset karakter eksklusif.
