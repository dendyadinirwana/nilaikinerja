# NilaiKinerja — Plan

App notch untuk rekapitulasi laporan kinerja harian.
Referensi arsitektur: `~/dev/dynamicnotch` (DynamicNotch, GPL-3.0) — dibaca, tidak disalin.
Build: pure SwiftPM, tanpa Xcode (terverifikasi, lihat skill `macos-notch-app-without-xcode`).

## Keputusan yang sudah diambil

- Tracking: **timer nyambung + checkpoint**, bukan pop-up tetap 60 menit.
  Alasan: timer fixed = user harus rekap manual tiap jam = data palsu + kelelahan.
  Timer nyambung → rekapitulasi *derived* dari event log, akurat.
- Export: **harian + bulanan**, format .docx.
- Laporan: **table format** `No | Waktu | Kegiatan | Hasil | Dokumen Pendukung`.
  Alasan: format ini yang bisa langsung di-submit, dan kolomnya memetakan
  1:1 ke data yang sudah kita kumpulkan.

## YAGNI — sengaja tidak ada di v1

- Rekap mingguan (bisa dijawab dari filter tanggal bulanan)
- Custom range picker (v1: hari ini + bulan ini cukup)
- Rekap 15 menit (terlalu granular, menghasilkan data sampah)
- Multi-display notch switching (lo 1 monitor)
- Lock screen surface
- Now Playing / media (gw nurut lo nggak pilih)
- Sparkle updater, Lottie, localization 25 bahasa
- App icon catalog (pakai SF Symbol, tanpa asset catalog)

## Arsitektur

```
NilaiKinerja.app
├── Engine/          reuse dari DynamicNotch, ditulis ulang
│   ├── SkyLightBridge.swift    private framework → notch space
│   ├── NotchPanel.swift        NSPanel + NSHostingView
│   ├── NotchEngine.swift       state machine, event queue
│   └── NotchGeometry.swift     auxiliaryTopLeftArea, multi-display
├── Tracking/        inti use case
│   ├── SessionStore.swift      event log (start/stop/switch/annotate)
│   ├── IdleMonitor.swift       IOKit HID idle time
│   ├── MeetingDetector.swift   skip saat Zoom/Meet/Teams aktif
│   ├── AdaptiveTimer.swift     interval naik kalau sering di-skip
│   └── TitleHistory.swift      autocomplete judul pekerjaan
├── Capture/
│   ├── AttachmentStore.swift   copy file + thumbnail (bukan bookmark)
│   └── DropTargetView.swift    drop image/PDF ke panel
├── Report/
│   ├── DailyReport.swift       .docx harian
│   ├── MonthlyReport.swift     .docx agregasi
│   └── DocxWriter.swift        writer OOXML minimal, no dependency
├── Persistence/
│   ├── Database.swift          SQLite, WAL, migration
│   └── Migrations.swift
└── UI/
    ├── NotchCollapsedView.swift
    ├── NotchCheckpointView.swift
    ├── NotchTitleEditor.swift
    └── SettingsView.swift
```

## Data model

```sql
-- satu baris per task yang sedang jalan
CREATE TABLE session (
  id          INTEGER PRIMARY KEY,
  started_at  REAL NOT NULL,
  ended_at    REAL,
  title       TEXT,              -- boleh NULL, diisi nanti
  detail      TEXT,
  outcome     TEXT,              -- "hasil" untuk laporan
  ended_cause TEXT               -- manual|idle|meeting|day_end
);

CREATE TABLE attachment (
  id          INTEGER PRIMARY KEY,
  session_id  INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
  filename    TEXT NOT NULL,
  stored_path TEXT NOT NULL,     -- copy di app storage, bukan bookmark
  kind        TEXT NOT NULL,     -- image|pdf|other
  bytes       INTEGER NOT NULL,
  sha256      TEXT NOT NULL      -- dedup
);

-- audit trail: rekapitulasi bisa direvisi, jadi jangan hard delete
CREATE TABLE revision (
  id         INTEGER PRIMARY KEY,
  session_id INTEGER NOT NULL REFERENCES session(id) ON DELETE CASCADE,
  at         REAL NOT NULL,
  field      TEXT NOT NULL,
  old_value  TEXT,
  new_value  TEXT
);
```

`session` terpisah dari `revision` karena data laporan ASN sering direvisi
(ada koreksi, ada tambahan) dan lo butuh bukti apa yang diubah kapan.

## Sprint 1 — Engine notch (fondasi) — ✅ SELESAI

- [x] `Package.swift` + `build.sh` (swift build → bundle → codesign)
- [x] `NotchGeometry` — baca notch width/height, handle non-notched display
- [x] `SkyLightBridge` — space create, level 2147483647, delegate window
- [x] `NotchPanel` — NSPanel config, reanchor saat display berubah
- [x] `NotchViews` — collapsed capsule + expanded body
- [x] `RootView` + `WindowBridge` — seam antara AppKit dan SwiftUI

**Verifikasi:** `[App] launched — SkyLight: true, notch: 208x37, notched: true`.
Screenshot mengonfirmasi panel menempel di notch dengan UI yang benar.

## Sprint 2 — Tracking loop

- [x] `Database` + migration 001 (WAL, foreign keys, revision log)
- [x] `SessionStore` — CRUD + event + split + suggestions
- [x] `IdleMonitor` — `CGEventSource.secondsSinceLastEventType` (publik, bukan IOKit private)
- [x] `MeetingDetector` — running app via NSWorkspace + fullscreen check
- [x] `AdaptiveTimer` — 15 menit–3 jam, adjust by engagement/skip
- [x] `TrackingCoordinator` — seluruh policy tracking di satu file
- [x] Checkpoint form dengan title suggestions

**Verifikasi:** 43/43 selftest pass. Yang perlu dicek manual oleh user:
idle auto-pause setelah 5 menit, dan meeting suppression.

## Sprint 3 — Capture + Report

- [x] `AttachmentStore` — content-addressed copy + sha256 (idempotent)
- [x] `AttachmentDropView` — drop image/PDF ke panel
- [x] `DocxWriter` — OOXML native, tanpa dependency eksternal
- [x] `ReportBuilder.daily` — table `No | Waktu | Kegiatan | Hasil | Dokumen`
- [x] `ReportBuilder.monthly` — agregasi per hari

**Verifikasi:** unzip + XML parse OK. 5 rows × 5 cells, grid width 7370 twips.
Escaping `& < > "` teruji round-trip. **Belum diverifikasi di Word/Pages asli** —
butuh user buka sekali.

## Sprint 4 — Polish

- [ ] Settings: interval, jam kerja, snooze
- [ ] Login item (`SMAppService`)
- [ ] Kalender hari kerja (skip hari libur)
- [ ] Error state & empty state

## Risiko

| Risiko | Mitigasi |
|---|---|
| SkyLight API berubah di macOS update | Sudah pakai `dlsym` + guard, fallback ke `statusBar` level |
| Notif pop-up di tengah presentasi | MeetingDetector + idle |
| User789 abandon di hari ke-3 | Adaptive interval, minimal friction, jangan nag |
| Data hilang | SQLite WAL + revision log, bukan UserDefaults |
| .docx invalid | Validasi dengan unzip + XML parse tiap sprint |
| NDA/data sensitif di laptop | Semua lokal, tidak ada network call. Tidak ada telemetry. |