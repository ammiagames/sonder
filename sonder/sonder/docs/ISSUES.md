# Sonder - Non-Blocking Issues & Code Quality

Last updated: 2026-02-16

---

## Summary

| Severity | Count | Category |
|----------|-------|----------|
| Severity | Count | Category | Status |
|----------|-------|----------|--------|
| ~~High~~ | ~~2~~ | ~~Deprecated APIs~~ | FIXED |
| High | 1 | Silent auth failure | |
| Medium | 10 | Force unwraps (non-Calendar) | 5 FIXED, 5 remaining |
| Medium | 78 | `try?` silent error swallowing | |
| Medium | 81 | `print()` statements in production code | 6 were `#Preview` only |
| Low | 998 | `.foregroundColor()` deprecated | |
| Low | 2 | TODO markers | |
| Low | 10 | Large files (500+ lines) | |
| Low | 1 | Dead code | |
| Medium | 6 | Concurrency / actor isolation | |
| Medium | 3 | Duplicate code patterns | |
| Low | 10+ | Magic numbers / inline colors | |
| Low | 3 | Naming conventions | |

---

## 1. Deprecated APIs

### ~~1a. `UIWindowScene.windows` (deprecated iOS 16+)~~ FIXED

Replaced `windowScene.windows.first` with `windowScene.keyWindow` in 2 files:

| File | Line | Status |
|------|------|--------|
| `Services/AuthenticationService.swift` | 138 | FIXED |
| `Views/Journal/JournalView.swift` | 617 | FIXED |

### 1b. `.foregroundColor()` (deprecated iOS 17+)

998 occurrences across 82 files. Replace with `.foregroundStyle()`.

**Biggest offenders:**

| File | Count |
|------|-------|
| `Views/Main/MainTabView.swift` | 81 |
| `Views/Profile/ProfileView.swift` | 82 |
| `Views/Feed/FeedItemCardStyles.swift` | 41 |
| `Views/Share/LogShareCardStyles.swift` | 38 |
| `Views/Trips/TripDetailView.swift` | 37 |

**Fix:** Global find-and-replace `.foregroundColor(` with `.foregroundStyle(`. Both take the same `Color` argument. Test after replacing since `.foregroundStyle` also accepts `ShapeStyle` which can cause type inference ambiguity in some cases.

---

## 2. Silent Auth Failure

### `AuthenticationView.swift:64` - `try?` on Apple Sign-In

```swift
try? await authService.signInWithApple(credential: credential)
```

If sign-in fails, the user sees nothing. Should catch and display an error.

**Fix:**
```swift
do {
    try await authService.signInWithApple(credential: credential)
} catch {
    // Show error alert to user
    signInError = error.localizedDescription
}
```

---

## 3. Force Unwraps

### 3a. Risky force unwraps (should fix)

| File | Line | Code | Risk | Fix |
|------|------|------|------|-----|
| `sonderApp.swift` | 51 | `.withDesign(.serif)!` | Crash on launch if font unavailable | Use `?? .preferredFontDescriptor(withTextStyle:)` fallback |
| `sonderApp.swift` | 52 | `.withDesign(.serif)!` | Same | Same |
| `Services/ProfileStatsService.swift` | 267 | `sortedDays.last!` | Crash if empty array | Use `guard let last = sortedDays.last else { return }` |
| `Services/ProfileStatsService.swift` | 518 | `cityPlaceSets.max(...)!` | Crash if empty dict | Already guarded by `count >= 2` but use `guard let` |
| `Services/GooglePlacesService.swift` | 353 | `URL(string: ...)!` | Crash on malformed URL | Use `guard let url = URL(string:)` |
| `Views/Feed/FeedCardStyle.swift` | 43 | `all.firstIndex(of: self)!` | Logically safe but unnecessary | Use `guard let` |
| `Config/SupabaseConfig.swift` | 13 | `URL(string: "https://...")!` | Static URL, effectively safe | Acceptable |
| `sonderApp.swift` | 84 | `fatalError("Could not init ModelContainer")` | Intentional - app can't run without SwiftData | Acceptable |

### ~~3b. Nil-check-then-force-unwrap pattern~~ FIXED

Replaced `if x == nil || x!` with safe `if let` patterns in all 5 locations:

| File | Line | Code | Status |
|------|------|------|--------|
| `Views/Logging/RatePlaceView.swift` | 49 | `map[tripID]!` → `if let existing` | FIXED |
| `Views/Logging/AddDetailsView.swift` | 66 | `map[tripID]!` → `if let existing` | FIXED |
| `Views/LogDetail/LogDetailView.swift` | 64 | `map[tripID]!` → `if let existing` | FIXED |
| `Views/Trips/TripWrappedView.swift` | 56 | `best!.note.count` → `if let b = best` | FIXED |
| `Views/Main/MainTabView.swift` | 518 | `selectedTagFilter!` → `.map { } ?? true` | FIXED |

### 3c. Calendar date arithmetic force unwraps (low risk, acceptable)

These are `calendar.date(byAdding:)!` calls which are effectively guaranteed to succeed with standard Gregorian calendar. Present in all heatmap views and several service files. Not worth refactoring.

| File | Lines |
|------|-------|
| `Views/Profile/CalendarHeatmapView.swift` | 123, 130, 138 |
| `Views/Profile/HeatmapIsometricView.swift` | 181, 186, 194 |
| `Views/Profile/HeatmapSeasonalView.swift` | 149, 154, 162 |
| `Views/Profile/HeatmapDotGardenView.swift` | 167, 172, 180 |
| `Views/Profile/HeatmapStreakGlowView.swift` | 238, 243, 251 |
| `Views/Profile/HeatmapInteractiveView.swift` | 211, 216, 224 |
| `Views/Profile/HeatmapAuraView.swift` | 201, 206, 214 |
| `Views/Profile/HeatmapRadialView.swift` | 143, 169 |
| `Views/Profile/HeatmapShowcaseView.swift` | 88, 130 |
| `Services/ProfileStatsService.swift` | 266 |

---

## 4. `try?` Silent Error Swallowing

78 occurrences across 25 files. Most are in `catch` blocks that already `print()` the error, but some silently discard results.

### High priority (user-facing operations that should show errors):

| File | Line | Operation |
|------|------|-----------|
| `Views/Authentication/AuthenticationView.swift` | 64 | Apple Sign-In |
| `Views/Main/MainTabView.swift` | 900 | Sign out |
| `Services/WantToGoService.swift` | 230, 238 | Supabase network calls |

### Medium priority (data operations where failures should be logged):

| File | Lines | Operation |
|------|-------|-----------|
| `Services/SyncEngine.swift` | 521, 726, 732, 773, 784, 791, 801, 811 | ModelContext saves, Supabase operations |
| `Views/LogDetail/LogDetailView.swift` | 679, 705, 715 | Log saves |
| `Views/Logging/AddDetailsView.swift` | 133, 681, 691, 739, 749, 783, 791 | Photo/log saves |
| `Views/Logging/RatePlaceView.swift` | 179, 400, 413, 447 | Log creation |

### Low priority (acceptable uses):

- `try? Task.sleep(...)` - intentional, sleep cancellation is expected
- `Services/PlacesCacheService.swift` - cache operations are best-effort

---

## 5. `print()` Statements in Production Code

87 `print()` calls across production source files. These should be replaced with `os.Logger` or removed before release.

### Debug logging (most impactful files):

| File | Count | Notes |
|------|-------|-------|
| `Services/SyncEngine.swift` | 14 | Network status, sync progress, errors |
| `Views/Logging/SearchPlaceView.swift` | 7 | `[Nearby]` debug logging |
| `Services/FeedService.swift` | 6 | Feed loading errors |
| `Services/SocialService.swift` | 4 | Follow errors |
| `Views/Trips/TripCollaboratorsView.swift` | 5 | Collaborator errors |
| `Services/ProximityNotificationService.swift` | 5 | Permission/notification errors |
| `Services/WantToGoService.swift` | 4 | Deferred sync errors |
| `Views/Profile/EditProfileView.swift` | 4 | Profile save/sync |
| `Views/Profile/OtherUserProfileView.swift` | 3 | User loading errors |

### ~~Placeholder/stub prints~~ NOT AN ISSUE

All 6 flagged prints are inside `#Preview` blocks, which are stripped from production builds. No changes needed.

| File | Line | Code | Status |
|------|------|------|--------|
| `Views/Components/FloatingActionButton.swift` | 44 | `print("FAB tapped")` | `#Preview` only |
| `Views/Components/PlaceSearchRow.swift` | 270 | `print("Delete tapped")` | `#Preview` only |
| `Views/Logging/PlacePreviewView.swift` | 401 | `print("Log tapped")` | `#Preview` only |
| `Views/Components/RatingButton.swift` | 117, 120, 123 | `print("Skip/Solid/Must-See tapped")` | `#Preview` only |
| `Views/Logging/LogConfirmationView.swift` | 195, 201, 203 | `print("Dismissed")` | `#Preview` only |
| `Views/Logging/CreateCustomPlaceView.swift` | 240 | `print("Created place: ...")` | `#Preview` only |

**Fix:** Replace meaningful error logging with `os.Logger`:
```swift
import os
private let logger = Logger(subsystem: "com.sonder", category: "SyncEngine")

// Before
print("Push sync error: \(error)")

// After
logger.error("Push sync error: \(error)")
```

Remove placeholder prints entirely.

---

## 6. TODO Markers

| File | Line | Note |
|------|------|------|
| `Services/AuthenticationService.swift` | 13 | `// TODO: Test Sign in with Apple when we have a paid Apple Developer account ($99/year)` |
| `Views/Authentication/AuthenticationView.swift` | 56 | `// TODO: Test Sign in with Apple when we have paid Apple Developer account` |

---

## 7. Large Files (candidates for extraction)

| File | Lines | Suggestion |
|------|-------|------------|
| `Views/Profile/ProfileView.swift` | 1,418 | Extract sections (stats, insights, settings) into subviews |
| `Views/Trips/TripDetailView.swift` | 1,156 | Extract route map, stop card, export into separate files |
| `Views/Feed/FeedItemCardStyles.swift` | 1,034 | Already organized by style - could split into one file per style |
| `Views/Map/ExploreMapView.swift` | 1,016 | Extract filter sheet, bottom card, pin views |
| `Views/Journal/JournalView.swift` | 855 | Extract share sheet, filter logic |
| `Views/Share/LogShareCardStyles.swift` | 842 | Split into one file per share style |
| `Views/LogDetail/LogDetailView.swift` | 841 | Extract edit form, photo section |
| `Views/Main/MainTabView.swift` | 832 | Extract LogsView and SettingsView into own files |
| `Services/SyncEngine.swift` | 771 | Extract push/pull logic into separate helpers |
| `Views/Logging/AddDetailsView.swift` | 728 | Extract photo picker, tag input sections |

---

## 8. Dead Code

| File | Lines | Description |
|------|-------|-------------|
| `Views/Trips/Export/TripExportFilmStrip.swift` | all | Defined but never used - no `.filmStrip` case in `ExportStyle` enum |

---

## 9. Debug Code in Production

| File | Line | Description |
|------|------|-------------|
| `Services/AuthenticationService.swift` | 30-33 | `debugBypassAuth` flag (currently `false` in both DEBUG and release) |
| `Views/Authentication/AuthenticationView.swift` | 39-54 | `#if DEBUG` "Debug Sign In" button - OK for dev, ensure stripped in release |

These are properly gated behind `#if DEBUG` / hardcoded `false`, so they won't affect production. Just ensure the `debugBypassAuth` flag is never accidentally set to `true`.

---

## 10. Concurrency / Actor Isolation

Several service classes lack `@MainActor` but vend mutable state to Views. Under Swift 6 strict concurrency this will produce errors.

| File | Class | Issue |
|------|-------|-------|
| `Services/SocialService.swift` | `SocialService` | No `@MainActor`, properties mutated from `Task` closures |
| `Services/WantToGoService.swift` | `WantToGoService` | No actor isolation, `items: [WantToGo]` mutated from async contexts |
| `Services/TripService.swift` | `TripService` | No actor annotation |
| `Services/ExploreMapService.swift` | `ExploreMapService` | No `@MainActor` |
| `Services/PlacesCacheService.swift` | `PlacesCacheService` | No actor isolation |
| `Services/PhotoService.swift` | `PhotoService` | `activeBatches` mutated from unstructured `Task` with no isolation |

**Compare with:** `FeedService` which correctly uses `@MainActor @Observable`.

**Fix:** Add `@MainActor` to service classes that vend state to Views, or mark individual state properties with `@MainActor`.

### `FeedService` infinite tasks never cancelled

`Services/FeedService.swift` lines 366-386: Two `Task { for await change in ... }` blocks iterate infinite async sequences with no cancellation. If `subscribeToRealtime` is called multiple times (e.g. sign-out/sign-in cycle), tasks pile up.

**Fix:** Store tasks and cancel on unsubscribe:
```swift
private var realtimeLogTask: Task<Void, Never>?
private var realtimeTripTask: Task<Void, Never>?
```

### `SyncEngine` public mutable state

`Services/SyncEngine.swift` lines 182, 185: `var isSyncing` and `var isOnline` are publicly writable — Views could accidentally mutate sync state.

**Fix:** `private(set) var isSyncing = false`

---

## 11. Duplicate Code

### 11a. Place selection in `SearchPlaceView.swift`

`Views/Logging/SearchPlaceView.swift` lines ~467-530: Four nearly identical functions (`selectPrediction`, `selectNearbyPlace`, `selectRecentSearch`, cached variant) all do:
```swift
isLoadingDetails = true
guard let details = await placesService.getPlaceDetails(placeId: X.placeId) else { ... }
selectedDetails = details
showPreview = true
```

**Fix:** Extract `func selectPlace(byID placeId: String) async`.

### 11b. Heatmap date grid logic

7 heatmap views all implement identical week-grid generation with the same `calendar.date(byAdding:)!` pattern.

**Fix:** Extract to a shared `HeatmapDateGrid` helper.

### 11c. `RemoteLog`/`RemoteTrip` at file scope

`Services/SyncEngine.swift` lines 14, 116: Internal Codable types defined at file scope visible to the whole module.

**Fix:** Nest inside `SyncEngine` or mark `private`.

---

## 12. Magic Numbers & Inline Colors

### Colors duplicated outside `SonderTheme.swift`

| File | Line | Issue |
|------|------|-------|
| `sonderApp.swift` | 40-43, 63 | `UIColor(red: 0.98, green: 0.96, ...)` duplicates `SonderColors.cream` |
| `Views/Journal/JournalPolaroidView.swift` | 191-192 | `Color(red: 0.80, green: 0.45, ...)` duplicates `SonderColors.terracotta` |
| `Views/Journal/MasonryTripsGrid.swift` | 233-234 | Same near-duplicate terracotta |
| `Views/Trips/TripWrappedView.swift` | 130-135 | Multiple inline `Color(red:...)` values |
| `Views/Trips/TripDetailView.swift` | 1879-1884 | Inline time-of-day color tuples |

**Fix:** Expose `UIColor` variants from `SonderTheme.swift` for UIKit contexts. Reference `SonderColors` everywhere else.

### Hardcoded frame dimensions

| File | Lines | Values |
|------|-------|--------|
| `Views/Share/ShareLogView.swift` | 282, 294 | `1080 x 1350` (Instagram ratio) — name as constant |
| `Views/Trips/TripPostcardStack.swift` | 53, 120, 237 | `320 x 440` repeated 3 times |

---

## 13. Naming Conventions

| File | Line | Issue | Fix |
|------|------|-------|-----|
| `sonderApp.swift` | 13 | `struct sonderApp` lowercase type name | Rename to `SonderApp` |
| `Services/ProfileStatsService.swift` | 13 | Caseless `enum ProfileStatsService` used as namespace but named like a service class | Rename to `ProfileStatsCalculator` or convert to `struct` |
| `Services/AuthenticationService.swift` | 30-33 | `#if DEBUG` / `#else` branches both set `debugBypassAuth = false` — dead conditional | Remove `#if`/`#else`, keep single declaration |

---

## Recommended Fix Order

1. ~~**Quick wins (30 min):** Fix nil-check-then-force-unwrap pattern (5 locations), fix `UIWindowScene.windows` deprecation (2 locations), remove placeholder `print()` stubs (6 locations)~~ **DONE** — all 5 force-unwraps refactored, 2 deprecated APIs fixed, placeholder prints confirmed `#Preview`-only
2. **Auth safety (15 min):** Add error handling to Apple Sign-In `try?` and sign-out `try?`
3. **Force unwrap safety (30 min):** Add fallbacks for `withDesign(.serif)!`, `sortedDays.last!`, `cityPlaceSets.max(...)!`, URL construction
4. **Concurrency safety (1 hr):** Add `@MainActor` to service classes, cancel FeedService realtime tasks, add `private(set)` to SyncEngine state
5. **Logging cleanup (1-2 hrs):** Replace `print()` with `os.Logger` across all services and views
6. **Deprecation sweep (2-3 hrs):** Replace `.foregroundColor()` with `.foregroundStyle()` across all 82 files
7. **Duplicate code (30 min):** Extract shared place selection helper, shared heatmap date grid helper
8. **Inline colors (30 min):** Replace hardcoded `Color(red:...)` / `UIColor(red:...)` with `SonderColors` references
9. **File size (ongoing):** Extract large views into smaller components as you touch those files
10. **Dead code (5 min):** Delete `TripExportFilmStrip.swift` or add `.filmStrip` to `ExportStyle`
