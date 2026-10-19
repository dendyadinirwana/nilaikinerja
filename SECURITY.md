# Kebijakan Keamanan & Privasi (Security & Privacy Policy)

Keamanan dan privasi pengguna adalah prioritas fundamental dalam pengembangan **NilaiKinerja**.

---

## 🛡️ Komitmen Privasi Data Pengguna

NilaiKinerja dirancang dengan prinsip **Local-First & Zero-Telemetry**:

1. **Penyimpanan Lokal Murni (100% On-Device):**
   - Seluruh catatan kegiatan, durasi kerja, dan lampiran dokumen bukti kinerja disimpan secara eksklusif di mesin lokal pengguna (`~/Library/Application Support/NilaiKinerja/`).
   - Tidak ada sinkronisasi *cloud* otomatis tanpa izin eksplisit pengguna.
2. **Tanpa Pelacakan & Analisis Pihak Ketiga:**
   - Aplikasi tidak memuat modul analitik, pelacak sesi, *crash report collector* pihak ketiga, maupun skrip telemetri apa pun.
3. **Kerahasiaan Asisten AI:**
   - Fitur obrolan AI hanya menghubungi *endpoint* API yang ditentukan langsung oleh pengguna (misalnya runner lokal seperti Ollama/LM Studio atau penyedia yang dikonfigurasi).
   - Kunci API (jika ada) disimpan secara aman di konfigurasi lokal dan tidak pernah ditransmisikan ke peladen lain selain *endpoint* yang dipilih pengguna.
4. **Pembaruan In-App (OTA Update):**
   - Layanan pengecekan pembaruan hanya berkomunikasi secara read-only dengan GitHub Releases API publik (`api.github.com`) untuk memeriksa nomor versi rilis terbaru.

---

## 🚨 Melaporkan Kerentanan Keamanan

Jika Anda menemukan potensi kerentanan keamanan atau celah privasi dalam aplikasi NilaiKinerja:

1. **Jangan publikasikan melalui GitHub Issues publik.**
2. Silakan laporkan secara privat melalui fitur **Private Vulnerability Reporting** di repositori GitHub kami:
   - Masuk ke tab **Security** > **Report a vulnerability**.
3. Berikan deskripsi yang jelas mengenai celah yang ditemukan, langkah reproduksi, dan estimasi dampaknya.
4. Kami akan segera memverifikasi laporan Anda dan menerbitkan rilis perbaikan secepat mungkin.
