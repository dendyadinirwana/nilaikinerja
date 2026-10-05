# Character Revert (Sora / Mood Mates) & Form Field Height Consistency Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Revert the animated notch companion character back to "Sora" (Mood Mates `nimbo` SVG engine via `CharacterView`) and establish a strictly consistent, pixel-perfect field height and visual hierarchy across all form views in NilaiKinerja.

**Architecture:** 
1. Re-wire `NotchSurface.swift` collapsed capsule from `LiveCharacterView` (Skippy APNG) to `CharacterView` (WebKit-backed parametric SVG engine loading `character.html` with character `nimbo`).
2. Standardize form input tokens (`inputHeight: 34pt`, `multilineHeight: 48pt`, `cornerRadius: 8pt`, stroke and padding standards) across `AddActivityForm`, `EditSessionForm`, and `NotchSurface` (checkpoint form).
3. Modernize the time-picker section in `AddActivityForm` with encapsulated rounded shells matching the title and detail field styling.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, WebKit (Mood Mates engine), SelfTest suite.

---

### Task 1: Revert Capsule Companion Character to Sora (`CharacterView`)

**Objective:** Switch the collapsed capsule companion character in `NotchSurface.swift` from `LiveCharacterView` (Skippy APNG) back to `CharacterView` (`nimbo` in `character.html`).

**Files:**
- Modify: `Sources/NilaiKinerja/UI/NotchSurface.swift:174-192`
- Test: `Sources/NilaiKinerja/SelfTest.swift`

**Step 1: Check existing test assertions**
Verify `SelfTest.swift` already enforces `character.html`, engine entry point, and character module in the bundle.
Run: `/Applications/NilaiKinerja.app/Contents/MacOS/NilaiKinerja --selftest`
Expected: 113 checks PASS.

**Step 2: Update `NotchSurface.swift`**
Replace `LiveCharacterView` in `collapsedContent` with `CharacterView`:
```swift
    private var collapsedContent: some View {
        HStack(spacing: 0) {
            CharacterView(
                emotion: today.characterEmotion,
                character: "nimbo",
                isActive: true
            )
            .frame(
                width: collapsedSize.height * 0.96,
                height: collapsedSize.height * 0.8
            )
            .padding(.leading, 4)

            Spacer(minLength: 8)

            timerCluster
                .padding(.trailing, 10)
        }
    }
```
Remove unneeded `liveIcon` initialization if redundant, or leave dormant.

**Step 3: Build & verify compilation**
Run: `cd /Users/dendyadinirwana/dev/nilaikinerja && ./build.sh`
Expected: Build complete without errors.

---

### Task 2: Define Standard Form Field Design Tokens & Shell

**Objective:** Define a consistent standard shell and layout metrics for all form inputs across NilaiKinerja.

**Files:**
- Create/Modify: `Sources/NilaiKinerja/UI/FieldStyle.swift` or inline helper in form views.
- Standard specifications:
  - Single-line field height: `34 pt`
  - Multi-line field (detail/outcome) height: `48 pt`
  - Time-picker capsule height: `34 pt`
  - Corner radius: `8 pt`
  - Background: `Color.white.opacity(0.06)`
  - Border/Stroke: `Color.white.opacity(0.10)`, lineWidth `0.5 pt`
  - Horizontal padding: `10 pt`, vertical centering for single line, `8 pt` top padding for multiline.
  - Label: SF Pro, size `11 pt`, weight `.medium`, color `Color.white.opacity(0.70)`.

**Step 1: Write helper view modifier / struct `FormFieldShell`**
```swift
struct FormFieldShell<Content: View>: View {
    var minHeight: CGFloat = 34
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
    }
}
```

**Step 2: Build & verify test pass**
Run: `cd /Users/dendyadinirwana/dev/nilaikinerja && swift build`
Expected: Success.

---

### Task 3: Refactor `AddActivityForm.swift` for Field Height Consistency

**Objective:** Make `AddActivityForm` inputs strictly follow the 34pt / 48pt sizing grid, including encapsulated time fields.

**Files:**
- Modify: `Sources/NilaiKinerja/UI/AddActivityForm.swift`

**Step 1: Refactor time pickers**
Wrap "Dari" and "Sampai" in structured 34pt shell capsules matching the rest of the form:
```swift
    private func timeField(_ label: String, date: Binding<Date>) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            DatePicker("", selection: date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)
                .labelsHidden()
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white.opacity(0.10), lineWidth: 0.5)
                )
        )
    }
```

**Step 2: Refactor title field and detail field**
- Title field: Explicit `34 pt` container height with single-line `TextField`.
- Detail field: Explicit `48 pt` container height with `axis: .vertical` and `alignment: .topLeading`.
- Drop zone: Standardized `38 pt` height, consistent with field aesthetics.

**Step 3: Verify build**
Run: `cd /Users/dendyadinirwana/dev/nilaikinerja && ./build.sh`
Expected: Build complete.

---

### Task 4: Refactor `EditSessionForm.swift` for Field Height Consistency

**Objective:** Standardize `EditSessionForm` fields (`draft.title`, `draft.detail`, `draft.outcome`) to match the exact 34pt and 48pt dimensions.

**Files:**
- Modify: `Sources/NilaiKinerja/UI/EditSessionForm.swift`

**Step 1: Update field sizing**
- Title field: `34 pt` height with single-line `TextField`.
- Detail field: `48 pt` height with `axis: .vertical` and `alignment: .topLeading`.
- Outcome field: `48 pt` height with `axis: .vertical` and `alignment: .topLeading`.
- Summary capsule (read-only timestamp): Standardized `34 pt` height.

**Step 2: Verify build**
Run: `cd /Users/dendyadinirwana/dev/nilaikinerja && ./build.sh`
Expected: Build complete.

---

### Task 5: Refactor Checkpoint Form in `NotchSurface.swift`

**Objective:** Standardize the inline checkpoint modal in `NotchSurface.swift` (`form.title`, `form.detail`) to use the exact same 34pt and 48pt height and stroke styling.

**Files:**
- Modify: `Sources/NilaiKinerja/UI/NotchSurface.swift:641-667`

**Step 1: Update `labelledField`**
- `form.title`: `34 pt` height shell with `white.opacity(0.10)` stroke border.
- `form.detail`: `48 pt` height shell with `white.opacity(0.10)` stroke border.
- Section labels: font `11 pt`, weight `.medium`, color `white.opacity(0.70)`.

**Step 2: Verify build**
Run: `cd /Users/dendyadinirwana/dev/nilaikinerja && ./build.sh`
Expected: Build complete.

---

### Task 6: Run SelfTest Suite & Update Installed App

**Objective:** Ensure all 113 automated tests pass and install the updated binary to `/Applications/NilaiKinerja.app`.

**Files:**
- Deploy: `/Applications/NilaiKinerja.app`

**Step 1: Run headless test suite**
Run: `./dist/NilaiKinerja.app/Contents/MacOS/NilaiKinerja --selftest`
Expected: 113 checks PASS.

**Step 2: Copy to `/Applications` and verify signature**
Run:
```bash
rm -rf /Applications/NilaiKinerja.app && cp -R dist/NilaiKinerja.app /Applications/NilaiKinerja.app
codesign --verify /Applications/NilaiKinerja.app
```
Expected: Signature valid.

---

### Task 7: Visual Verification via Screencapture & Vision AI

**Objective:** Capture and inspect screenshots of the capsule (with Sora/Nimbo), Add Activity form, Edit Session form, and Checkpoint form to verify pixel-perfect height consistency.

**Files:**
- Inspect: `/tmp/notch_capsule_sora.png`, `/tmp/notch_add_consistent.png`, `/tmp/notch_edit_consistent.png`

**Step 1: Capture idle capsule**
Launch NilaiKinerja, capture capsule, verify Sora SVG rendering inside the notch.

**Step 2: Capture Add & Edit forms**
Launch with `--demo-add-activity`, screencapture, inspect with `vision_analyze` to confirm all fields align with the 34pt/48pt visual grid.
