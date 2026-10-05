# Work Schedule Settings, Reminder System, Corner Add Button & 16px Typography Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Implement user-configurable work hours and workdays in Settings and WorkSchedule, add a customizable checkpoint reminder system with notification support, replace the full-width add button with an icon-only "+" button at the bottom-right corner, and elevate the entire app typography to a minimum of 16px body font with proportional spatial hierarchy.

**Architecture:**
1. **Work Schedule Configuration:** Add `workStartHour`, `workStartMinute`, `workEndHour`, `workEndMinute`, and `workdays` (`[Int]` where 1=Sun, 2=Mon...7=Sat) to `AppSettings`. Wire `WorkSchedule.window(for:calendar:)` to read from settings with fallback defaults (07:30–17:00, Mon–Fri).
2. **Reminder Engine:** Add `reminderEnabled`, `reminderIntervalMinutes` (default 60m), and `reminderSoundEnabled` to `AppSettings`. Connect `AdaptiveTimer` and `TrackingCoordinator` to respect these settings, sound an audible chime, post a macOS UserNotification / drop the checkpoint modal when due.
3. **Corner Add Button:** Replace the full-width `addActivityBar` in `NotchSurface.swift` with an icon-only "+" circular button (`36×36 pt`, accent blue fill, white bold plus) anchored strictly at the bottom-right corner (`HStack { Spacer(); Button(...) }`).
4. **16px Body Typography & Scale-up:** Upgrade all body typography to `>= 16pt` (`.font(.system(size: 16))`), activity titles to `16pt .semibold`, header titles to `18pt .bold`, metadata/subtitles to `13.5pt`, and button text to `15-16pt`. Increase row pitch (`rowPitch: 88pt`) and form field heights (`singleLine: 38pt`, `multiLine: 56pt`) so the 16pt typography breathes cleanly without clipping.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, UserNotifications, SelfTest suite.

---

### Task 1: Add Work Schedule & Reminder Configuration to `AppSettings`

**Objective:** Expand `AppSettings` to persist work hours (start/end), active workdays, and reminder settings in `UserDefaults`.

**Files:**
- Modify: `Sources/NilaiKinerja/Settings/AppSettings.swift`
- Test: `Sources/NilaiKinerja/SelfTest.swift`

**Step 1: Write settings keys and properties in `AppSettings.swift`**
Add keys and `@Published` properties:
- `workStartHour: Int` (default 7, range 0...23)
- `workStartMinute: Int` (default 30, range 0...59)
- `workEndHour: Int` (default 17, range 0...23)
- `workEndMinute: Int` (default 0, range 0...59)
- `workdays: [Int]` (default `[2, 3, 4, 5, 6]`, Calendar weekdays: 2=Mon...6=Fri)
- `reminderEnabled: Bool` (default `true`)
- `reminderIntervalMinutes: Int` (default `60`, range 15...180)
- `reminderSoundEnabled: Bool` (default `true`)

**Step 2: Add static shared accessor or pass instance**
Provide `AppSettings.shared` for background/tracking components:
```swift
@MainActor static let shared = AppSettings()
```

**Step 3: Build & verify compilation**
Run: `cd /Users/dendyadinirwana/dev/nilaikinerja && ./build.sh`
Expected: Build passes.

---

### Task 2: Connect `WorkSchedule` to Configurable Work Hours & Workdays

**Objective:** Enable `WorkSchedule.window(for:calendar:)` to dynamically check active workdays and working hours from settings, while preserving compatibility for isolated tests.

**Files:**
- Modify: `Sources/NilaiKinerja/Tracking/WorkSchedule.swift`
- Test: `Sources/NilaiKinerja/SelfTest.swift`

**Step 1: Update `WorkSchedule.window(for:calendar:)`**
Allow custom workdays and hours:
```swift
static var activeWorkdays: Set<Int> = [2, 3, 4, 5, 6]
static var startHour: Int = 7
static var startMinute: Int = 30
static var endHour: Int = 17
static var endMinute: Int = 0
```
Update `window(for:calendar:)` to check `activeWorkdays.contains(weekday)` and use `startHour/startMinute` and `endHour/endMinute`.

**Step 2: Run selftest to verify no regressions**
Run: `./dist/NilaiKinerja.app/Contents/MacOS/NilaiKinerja --selftest`
Expected: All 113 checks PASS.

---

### Task 3: Implement Reminder Settings & Trigger in `AdaptiveTimer` & `TrackingCoordinator`

**Objective:** Wire `AdaptiveTimer` and `TrackingCoordinator` to respect `reminderEnabled`, update interval to `reminderIntervalMinutes`, play chime sound, and drop the checkpoint prompt.

**Files:**
- Modify: `Sources/NilaiKinerja/Tracking/AdaptiveTimer.swift`
- Modify: `Sources/NilaiKinerja/Tracking/TrackingCoordinator.swift`

**Step 1: Add configuration hooks to `AdaptiveTimer`**
- Set `baseInterval = Double(settings.reminderIntervalMinutes * 60)`.
- If `!settings.reminderEnabled`, do not fire or stop timer.

**Step 2: Trigger sound & checkpoint in `TrackingCoordinator`**
- In `handleCheckpointDue()`:
  - Check `settings.reminderEnabled`.
  - If `settings.reminderSoundEnabled`, play system chime (`NSSound(named: "Ping")?.play()` or `NSSound.beep()`).
  - Set `panelState = .checkpoint`.

**Step 3: Build & verify**
Run: `./build.sh`

---

### Task 4: Replace Full-Width Add Button with Corner Icon "+" Button

**Objective:** Remove `addActivityBar` full-width card and implement a compact, floating/anchored `+` icon button strictly in the bottom-right corner (`pojok kanan bawah`).

**Files:**
- Modify: `Sources/NilaiKinerja/UI/NotchSurface.swift`
- Modify: `Sources/NilaiKinerja/Engine/NotchGeometry.swift` (adjust chrome height)

**Step 1: Update `listScreen` in `NotchSurface.swift`**
Replace `addActivityBar` with:
```swift
    private var cornerAddButton: some View {
        HStack {
            Spacer()
            Button {
                mode.screen = .add
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(hex: 0x2563EB)))
                    .shadow(color: Color(hex: 0x2563EB).opacity(0.4), radius: 6, y: 2)
            }
            .buttonStyle(NotchPressStyle())
            .help("Tambah kegiatan")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .padding(.top, 4)
    }
```

**Step 2: Update `NotchGeometry` height calculations**
Adjust `expandedChromeHeight` to account for the sleeker bottom corner button, ensuring the 3 rows fit cleanly.

---

### Task 5: Upgrade App Typography to >= 16px Body Font Across All Screens

**Objective:** Enforce minimum 16px body font across all rows, inputs, headers, and screens, adjusting layout geometry so nothing clips.

**Files:**
- Modify: `Sources/NilaiKinerja/UI/NotchSurface.swift`
- Modify: `Sources/NilaiKinerja/UI/SwipeRow.swift`
- Modify: `Sources/NilaiKinerja/UI/AddActivityForm.swift`
- Modify: `Sources/NilaiKinerja/UI/EditSessionForm.swift`
- Modify: `Sources/NilaiKinerja/UI/SettingsScreen.swift`
- Modify: `Sources/NilaiKinerja/Engine/NotchGeometry.swift`

**Font specifications:**
- Primary Body / Row Titles: `16pt, weight: .semibold`
- Form Text Fields / Text Editors: `16pt`
- Header Titles: `18pt, weight: .bold`
- Meta / Time Range / Subtitles: `13.5pt, weight: .medium`
- Section Headers: `12pt, weight: .bold`
- Field Labels: `13.5pt, weight: .medium`
- Action Buttons: `15-16pt, weight: .semibold`

**Geometry adjustments:**
- `NotchGeometry.rowPitch: 88` (was 76)
- Form input height: `38pt` (was 34pt)
- Multiline editor height: `56pt` (was 48pt)
- Form action buttons: `36pt` (was 32pt)

---

### Task 6: Build UI for Work Schedule & Reminder in `SettingsScreen.swift`

**Objective:** Add clean, interactive control sections in `SettingsScreen`: "WAKTU KERJA" and "PENGINGAT".

**Files:**
- Modify: `Sources/NilaiKinerja/UI/SettingsScreen.swift`

**UI Components:**
1. **WAKTU KERJA Section:**
   - Day toggles: `Sen`, `Sel`, `Rab`, `Kam`, `Jum`, `Sab`, `Min` with active highlight.
   - Jam Mulai: Stepper or clean time chips (e.g. `07:30`).
   - Jam Selesai: Stepper or clean time chips (e.g. `17:00`).
   - Summary caption: e.g. "5 hari kerja • 07:30 s/d 17:00 (9j 30m)".
2. **PENGINGAT Section:**
   - Toggle: `Aktifkan Pengingat Otomatis`.
   - Interval slider / preset chips: `30m`, `45m`, `60m`, `90m`, `120m`.
   - Toggle: `Bunyi Notifikasi`.

---

### Task 7: Build, Selftest, Install & Vision AI Verification

**Objective:** Run the full build, verify all 113 tests pass, install to `/Applications/NilaiKinerja.app`, and inspect all screens using Vision AI.

**Verification steps:**
1. `./build.sh`
2. `--selftest` (113/113 passed)
3. Copy to `/Applications/NilaiKinerja.app`
4. Capture screenshots:
   - `--demo-expanded`: Verify 16px body typography and bottom-right "+" button.
   - `--demo-settings`: Verify Waktu Kerja and Pengingat sections with >= 16px text.
   - `--demo-add-activity`: Verify standard 16px typography and 38pt/56pt fields.
   - `--demo-checkpoint`: Verify 16px body typography in checkpoint prompt.
