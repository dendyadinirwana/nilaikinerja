# Spesifikasi Desain: Tab "Tentang" & OTA Update Subsistem NilaiKinerja

**Tanggal:** 11 Oktober 2026  
**Penulis:** Dendy Adinirwana & Hermes Agent  
**Status:** Disetujui (Approved)  
**Target Rilis:** NilaiKinerja v1.1.0  
**Repositori Target:** `github.com/dendyadinirwana/nilaikinerja`  

---

## 1. Latar Belakang & Tujuan

NilaiKinerja telah berevolusi dari proof-of-concept menjadi aplikasi produktivitas kinerja ASN berbasis notch MacBook dengan karakter 3D terintegrasi dan antarmuka multi-tab. Dengan pergantian karakter ke `fayazara/robot-heads` yang berlisensi murni MIT, aplikasi ini kini 100% legal dan siap untuk didistribusikan ke perangkat internal lain.

Tujuan dari spesifikasi ini adalah:
1. Menambahkan tab ke-4 pada antarmuka Pengaturan: **"Tentang" (About)** yang menyajikan identitas aplikasi, status versi aktif, lisensi MIT, tautan repository, dan kontrol pembaruan.
2. Membangun subsistem **Over-The-Air (OTA) Update** native di macOS yang secara otomatis memeriksa rilis terbaru di GitHub Releases API (`api.github.com/repos/dendyadinirwana/nilaikinerja/releases/latest`).
3. Mendukung alur pembaruan in-app yang mulus (*In-App Seamless Auto-Updater*): mendownload `.zip` rilis, memvalidasi bundle, menimpa `/Applications/NilaiKinerja.app`, membersihkan karantina Gatekeeper (`xattr -cr`), dan merestart aplikasi.
4. Menyediakan otomasi rilis GitHub Actions (`.github/workflows/release.yml`) agar setiap push git tag `v*` otomatis mengompilasi dan mengunggah artifact rilis ke GitHub.

---

## 2. Arsitektur Komponen

```
┌─────────────────────────────────────────────────────────────────┐
│                          SettingsScreen                         │
│  [ Notch & Interaksi ] [ Asisten AI ] [ Kinerja ] [ Tentang ]   │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                          UpdateService                          │
│                      (@MainActor Observable)                    │
├─────────────────────────────────────────────────────────────────┤
│  - status: idle / checking / available / downloading / ready    │
│  - currentVersion: "1.0.0"                                      │
│  - latestRelease: GitHubRelease?                                │
│  - downloadProgress: Double (0.0 .. 1.0)                        │
│                                                                 │
│  Methods:                                                       │
│  - checkForUpdates(explicit: Bool)                              │
│  - downloadAndInstall()                                         │
│  - relaunchApp()                                                │
└──────────────┬──────────────────────────────────┬───────────────┘
               │                                  │
      (GitHub Releases API)             (File Manager & Ditto)
               │                                  │
               ▼                                  ▼
      api.github.com/.../latest         /Applications/NilaiKinerja.app
```

---

## 3. Spesifikasi UI: Tab "Tentang" (`SettingsScreen`)

Tab ke-4 diakses melalui tab switcher di `SettingsScreen`:
- Nama: `"Tentang"`
- Ikon: `info.circle`
- Identitas tab matching visual tanpa border stroke (menggunakan `matchedGeometryEffect`).

### 3.1. Elemen Antarmuka:
1. **Header Identitas Aplikasi:**
   - Ikon maskot 3D TV Robot Head (ukuran 48x48) dengan background kartu gelap halus.
   - Teks Judul: **NilaiKinerja**.
   - Subjudul: Versi saat ini (`v1.0.0`), membaca dinamis dari `Bundle.main.infoDictionary["CFBundleShortVersionString"]`.
   - Badge Status Versi:
     - Hijau: *"Versi Terbaru"* (jika versi sama dengan remote).
     - Biru: *"Pembaruan Tersedia"* (jika ada versi lebih tinggi).
2. **Kartu Pembaruan (Update Card):**
   - Menampilkan status pemeriksaan terakhir: *"Terakhir diperiksa: Hari ini, HH:mm"*.
   - Tombol Aksi (Tinggi standar `36pt`):
     - State Normal: Tombol *"Periksa Pembaruan"* (ikon `arrow.clockwise`).
     - State Checking: Spinner mini + teks *"Memeriksa ke GitHub..."*.
     - State Pembaruan Tersedia:
       - Kotak rincian: Menampilkan tag versi baru (misal `v1.0.1`), tanggal rilis, dan teks *Release Notes / Changelog* dalam scroll view kecil.
       - Tombol *"Unduh & Pasang Pembaruan"* (ikon `arrow.down.circle.fill`).
     - State Downloading: Bar progres unduhan (`ProgressView(value: progress)`).
     - State Ready to Relaunch: Tombol hijau *"Mulai Ulang Aplikasi"* (ikon `arrow.triangle.2.circlepath`).
3. **Pengaturan Otomatis:**
   - Toggle switch (rata kanan): **"Periksa Pembaruan Otomatis"**.
   - Nilai disimpan di `AppSettings.autoCheckUpdates` (default `true`).
   - Saat aktif, `UpdateService` menjalankan silent check di background 3 detik setelah aplikasi diluncurkan (`AppDelegate.applicationDidFinishLaunching`).
4. **Metadata & Tautan:**
   - Baris Repositori: Tautan klik ke `https://github.com/dendyadinirwana/nilaikinerja`.
   - Baris Lisensi: *"MIT License (Bebas Didistribusikan)"*.
   - Baris Pengembang: *"Kementerian Desa PDT — Dendy Adinirwana"*.

---

## 4. Spesifikasi Teknis `UpdateService`

### 4.1. Model Data GitHub API

```swift
struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let body: String?
    let publishedAt: String?
    let htmlUrl: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body
        case publishedAt = "published_at"
        case htmlUrl = "html_url"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}
```

### 4.2. Perbandingan Versi SemVer
Fungsi `isVersion(_ v1: String, newerThan v2: String) -> Bool`:
- Membersihkan prefiks non-angka (seperti "v" pada "v1.0.1" -> "1.0.1").
- Memecah versi berdasarkan titik `.` menjadi array integer: `[1, 0, 1]` vs `[1, 0, 0]`.
- Membandingkan major, minor, dan patch secara berurutan.

### 4.3. Download, Verifikasi, & Swapping Bundle
1. **Download:** Mengunduh asset `NilaiKinerja.zip` via `URLSessionDownloadDelegate` untuk memantau progres unduhan secara real-time.
2. **Staging:** Disimpan di `NSTemporaryDirectory()/NilaiKinerja-OTA-<uuid>/`.
3. **Ekstraksi:** Menggunakan tool macOS `/usr/bin/ditto -xk <zipPath> <stagingDir>`.
4. **Validasi:** Memastikan file `stagingDir/NilaiKinerja.app/Contents/MacOS/NilaiKinerja` ada dan executable.
5. **Relaunch Script:** Menulis skrip shell `/tmp/nk_relaunch_<pid>.sh`:
   ```bash
   #!/bin/bash
   # Menunggu proses lama mati
   while kill -0 $1 2>/dev/null; do sleep 0.15; done
   # Timpa bundle di folder /Applications
   rm -rf /Applications/NilaiKinerja.app
   /usr/bin/ditto "$2" /Applications/NilaiKinerja.app
   # Bersihkan karantina Gatekeeper
   /usr/bin/xattr -cr /Applications/NilaiKinerja.app
   # Luncurkan kembali aplikasi baru
   /usr/bin/open /Applications/NilaiKinerja.app
   # Hapus script sementara
   rm -f "$0"
   ```
6. Menjalankan skrip dengan `Process()` lalu memanggil `NSApp.terminate(nil)`.

---

## 5. Otomasi CI/CD: GitHub Actions Workflow

File `.github/workflows/release.yml` ditempatkan di root proyek:
- **Trigger:** Push tag dengan pola `v*` (contoh: `v1.0.1`, `v1.1.0`).
- **Runner:** `macos-14` (Apple Silicon M2).
- **Langkah-langkah:**
  1. `actions/checkout@v4`.
  2. Kompilasi aplikasi via `./build.sh release`.
  3. Mengompresi bundle aplikasi: `cd dist && zip -r -y NilaiKinerja.zip NilaiKinerja.app`.
  4. Publikasi rilis via `softprops/action-gh-release@v2` dengan melampirkan `dist/NilaiKinerja.zip` dan `generate_release_notes: true`.

---

## 6. Error Handling & Edge Cases

| Skenario | Penanganan |
|---|---|
| **Tidak ada koneksi internet / offline** | Menampilkan status error halus *"Gagal terhubung ke GitHub"*, tombol coba lagi tetap aktif, tidak mengganggu fungsi offline app. |
| **GitHub API Rate Limit (60 req/jam anonim)** | Menampilkan status *"Batas pemeriksaan tercapai, coba beberapa saat lagi"*. Menggunakan timestamp cache agar tidak spam request. |
| **Asset rilis `.zip` tidak ditemukan** | Jika rilis GitHub tidak memiliki asset zip, sistem fallback menyediakan tombol *"Buka Halaman Rilis di Browser"*. |
| **Gagal mengekstrak atau file zip korup** | Staging dihapus, status di-reset ke awal dengan pesan error *"Berkas pembaruan tidak valid"*. |
| **Aplikasi tidak berada di `/Applications`** | Script memeriksa lokasi instalasi aktif via `Bundle.main.bundleURL.path` dan menimpa direktori yang sesuai (default `/Applications/NilaiKinerja.app`). |

---

## 7. Strategi Pengujian (SelfTest)

Menambahkan unit test headless di `Sources/NilaiKinerja/SelfTest.swift`:
1. Uji SemVer comparison:
   - `1.0.1 > 1.0.0` ➔ `true`
   - `1.1.0 > 1.0.9` ➔ `true`
   - `2.0.0 > 1.9.9` ➔ `true`
   - `1.0.0 > 1.0.0` ➔ `false`
   - `1.0.0 > 1.0.1` ➔ `false`
   - Toleransi prefiks `v`: `v1.0.1 == 1.0.1`.
2. Uji parsing JSON release model dari mock payload GitHub.
3. Uji integrasi `AppSettings.autoCheckUpdates` (default `true`, toggle, dan persistensi).
4. Verifikasi seluruh 185 test lama tetap lolos (total 190+ checks).
