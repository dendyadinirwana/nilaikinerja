# Panduan Berkontribusi (Contributing Guide)

Terima kasih telah tertarik untuk berkontribusi pada **NilaiKinerja**! Proyek ini bersifat *open-source* di bawah lisensi MIT. Kami menyambut kontribusi berupa perbaikan bug, penambahan fitur, peningkatan performa, maupun dokumentasi.

---

## 🛠️ Prasyarat & Lingkungan Pengembangan

- **Sistem Operasi:** macOS 14.0 (Sonoma) atau yang lebih baru (macOS Sequoia didukung penuh).
- **Toolchain:** Swift 5.9+ (tersedia melalui Xcode Command Line Tools: `xcode-select --install`).
- **Prinsip Arsitektur:** **Zero External Package Dependencies**. Seluruh antarmuka dan sistem dibangun menggunakan SwiftPM murni, AppKit, dan SwiftUI native tanpa *framework* pihak ketiga yang berat.

---

## 🚀 Alur Kerja Pembangunan (Build Workflow)

Proyek ini dilengkapi skrip pembangunan mandiri `build.sh`:

```bash
# 1. Clone repositori
git clone https://github.com/dendyadinirwana/nilaikinerja.git
cd nilaikinerja

# 2. Kompilasi dan kemas aplikasi (Release mode)
./build.sh release

# Aplikasi yang telah dikompilasi dan di-codesign ad-hoc akan tersedia di:
# dist/NilaiKinerja.app
```

---

## 🧪 Pengujian Mandiri (Self-Test Suite)

Sebelum mengirimkan kontribusi atau membuat *pull request*, pastikan seluruh rangkaian tes verifikasi internal lolos:

```bash
# Menjalankan seluruh unit test logika, persistence, drop handler, dan UI state
./dist/NilaiKinerja.app/Contents/MacOS/NilaiKinerja --selftest

# Menjalankan verifikasi konektivitas dan pipeline streaming AI (jika server AI aktif)
./dist/NilaiKinerja.app/Contents/MacOS/NilaiKinerja --selftest-ai
```

---

## 📐 Standar Desain & Kode

1. **Standardisasi Dimensi Antarmuka:**
   - Seluruh tombol aksi utama (CTA) dan bidang input teks satu baris memiliki tinggi standar **`36pt`**.
   - Tab bar dan kontrol navigasi menggunakan gaya solid pill tanpa border stroke yang bertumpuk.
2. **Isolasi Event & Non-Interferensi Sistem:**
   - Panel notch **dilarang membajak** event mouse atau drag sistem macOS di luar batas visual notch/panel aktif (`hitTest` wajib mengembalikan `nil` di luar rect interaktif).
   - Operasi berkas di Finder dan Desktop pengguna harus tetap berfungsi 100% normal.
3. **Keamanan & Privasi Data:**
   - Jangan pernah menyertakan API key, token rahasia, kredensial privat, atau path sistem lokal pada kode, komentar, maupun sampel data pengujian.
   - Gunakan `ProcessInfo.processInfo.environment` atau konfigurasi UI pengguna untuk parameter sensitif.
4. **Verifikasi Magic-Bytes Berkas:**
   - Setiap fitur penanganan berkas wajib melewati inspeksi tanda tangan biner (`FileContentValidator`) guna mencegah file executable terselubung.

---

## 🔀 Mengajukan Pull Request (PR)

1. Buat *branch* fitur atau perbaikan dari `main`:
   ```bash
   git checkout -b feature/nama-fitur-baru
   # atau
   git checkout -b fix/deskripsi-perbaikan
   ```
2. Lakukan *commit* dengan pesan yang deskriptif dan jelas.
3. Jalankan `./build.sh release` dan pastikan `--selftest` lolos 100%.
4. Buka *Pull Request* ke repositori utama dengan menjelaskan perubahan yang dilakukan serta hasil pengujian.
