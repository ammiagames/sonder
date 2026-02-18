# Sonder - Non-Blocking Issues & Code Quality

Last updated: 2026-02-17

---

## Summary

| Severity | Count | Category | Status |
|----------|-------|----------|--------|
| ~~High~~ | ~~2~~ | ~~Deprecated APIs~~ | FIXED |
| High | 1 | Silent auth failure | |
| Medium | 5 | Force unwraps (non-Calendar) | |
| Medium | ~102 | `try?` silent error swallowing | |
| Medium | ~55 | `print()` statements in production code | |
| Low | ~398 | `.foregroundColor()` deprecated | |
| Low | 10 | Large files (500+ lines) | |
| Low | 1 | Dead code | |
| Medium | 6 | Concurrency / actor isolation | |
| Medium | 3 | Duplicate code patterns | |
| Low | 10+ | Magic numbers / inline colors | |
| Low | 3 | Naming conventions | |

---

## 1. Deprecated APIs

### ~~1a. `UIWindowScene.windows` (deprecated iOS 16+)~~ FIXED

Replaced `windowScene.windows.first` with `windowScene.keyWindow` in 2 files.

### 1b. `.foregroundColor()` (deprecated iOS 17+)

~398 occurrences across ~40 files. Replace with `.foregroundStyle()`.

**Biggest offenders:**

| File | Count |
|------|-------|
| `Views/Profile/ProfileView.swift` | 82 |
| `Views/Share/LogShareCardStyles.swift` | 38 |
| `Views/Trips/TripDetailView.swift` | 37 |
| `Views/Map/UnifiedBottomCard.swift` | 29 |
| `Views/Logging/AddDetailsView.swift` | 26 |

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
| `Services/ProfileStatsService.swift` | 265 | `sortedDays.last!` | Crash if empty array | Use `guard let last = sortedDays.last else { return }` |
| `Services/ProfileStatsService.swift` | 518 | `cityPlaceSets.max(...)!` | Crash if empty dict | Already guarded by `count >= 2` but use `guard let` |
| `Services/GooglePlacesService.swift` | 353 | `URL(string: ...)!` | Crash on malformed URL | Use `guard let url = URL(string:)` |

### ~~3b. Nil-check-then-force-unwrap pattern~~ FIXED

All 5 locations refactored to safe `if let` patterns.

### 3c. Calendar date arithmetic force unwraps (low risk, acceptable)

These are `calendar.date(byAdding:)!` calls which are effectively guaranteed to succeed with standard Gregorian calendar. Present in all heatmap views and several service files. Not worth refactoring.

---

## 4. `try?` Silent Error Swallowing

~102 occurrences across ~30 files. Most are in `catch` blocks that already `print()` the error, but some silently discard results.

### High priority (user-facing operations that should show errors):

| File | Line | Operation |
|------|------|-----------|
| `Views/Authentication/AuthenticationView.swift` | 64 | Apple Sign-In |
| `Views/Main/MainTabView.swift` | ~900 | Sign out |
| `Services/WantToGoService.swift` | 230, 238 | Supabase network calls |

### Medium priority (data operations where failures should be logged):

| File | Lines | Operation |
|------|-------|-----------|
| `Services/SyncEngine.swift` | multiple (10) | ModelContext saves, Supabase operations |
| `Views/LogDetail/LogDetailView.swift` | multiple (5) | Log saves |
| `Views/Logging/AddDetailsView.swift` | multiple (7) | Photo/log saves |
| `Views/Logging/RatePlaceView.swift` | multiple (4) | Log creation |
| `Services/PlacesCacheService.swift` | multiple (18) | Cache operations (best-effort, low priority) |

### Low priority (acceptable uses):

- `try? Task.sleep(...)` - intentional, sleep cancellation is expected
- `Services/PlacesCacheService.swift` - cache operations are best-effort

---

## 5. `print()` Statements in Production Code

~55 `print()` calls across ~15 production source files. These should be replaced with `os.Logger` or removed before release.

### Debug logging (most impactful files):

| File | Count | Notes |
|------|-------|-------|
| `Services/SyncEngine.swift` | 16 | Network status, sync progress, errors |
| `Views/Logging/SearchPlaceView.swift` | 7 | `[Nearby]` debug logging |
| `Services/FeedService.swift` | 6 | Feed loading errors |
| `Services/ProximityNotificationService.swift` | 5 | Permission/notification errors |
| `Views/Trips/TripCollaboratorsView.swift` | 5 | Collaborator errors |
| `Services/SocialService.swift` | 4 | Follow errors |
| `Services/WantToGoService.swift` | 4 | Deferred sync errors |
| `Services/GooglePlacesService.swift` | 4 | API errors |

**Fix:** Replace meaningful error logging with `os.Logger`:
```swift
import os
private let logger = Logger(subsystem: "com.sonder", category: "SyncEngine")

// Before
print("Push sync error: \(error)")

// After
logger.error("Push sync error: \(error)")
```

---

## 6. TODO Markers

None remaining in Swift source files. Previously had 2 TODOs about Apple Sign-In testing — both removed.

---

## 7. Large Files (candidates for extraction)

| File | Lines | Suggestion |
|------|-------|------------|
| `Views/Trips/TripDetailView.swift` | 2,146 | Extract route map, stop card, export, moment cards into separate files |
| `Views/Profile/ProfileView.swift` | 1,143 | Extract sections (stats, cities mosaic, settings) into subviews |
| `Views/Map/ExploreMapView.swift` | 1,072 | Extract filter sheet, bottom card, pin views |
| `Services/SyncEngine.swift` | 976 | Extract push/pull logic into separate helpers |
| `Views/Trips/ShareTripView.swift` | 911 | Extract export styles, preview, configuration |
| `Views/Logging/AddDetailsView.swift` | 907 | Extract photo picker, tag input sections |
| `Views/Journal/JournalPolaroidView.swift` | 907 | Extract polaroid card, vintage effects |
| `Views/LogDetail/LogDetailView.swift` | 868 | Extract edit form, photo section |
| `Views/Share/LogShareCardStyles.swift` | 842 | Split into one file per share style |
| `Views/Feed/FeedLogDetailView.swift` | 660 | Extract sections into subviews |

---

## 8. Dead Code

| File | Lines | Description | Status |
|------|-------|-------------|--------|
| ~~`Views/Journal/JournalView.swift`~~ | ~~855~~ | ~~Replaced by `JournalContainerView`~~ | DELETED |
| ~~`Views/Map/ExploreBottomCard.swift`~~ | ~~153~~ | ~~Replaced by `UnifiedBottomCard`~~ | DELETED |
| ~~`Views/Trips/TripPostcardStack.swift`~~ | ~~333~~ | ~~Never referenced~~ | DELETED |
| ~~`Views/Trips/TripCinematicView.swift`~~ | ~~364~~ | ~~Never referenced~~ | DELETED |
| ~~`Views/Trips/TripPhotoWall.swift`~~ | ~~302~~ | ~~Never referenced~~ | DELETED |
| ~~`Views/Trips/TripWrappedView.swift`~~ | ~~393~~ | ~~Never referenced~~ | DELETED |
| ~~`Views/Trips/TripBookView.swift`~~ | ~~348~~ | ~~Never referenced~~ | DELETED |
| ~~`Views/Trips/TripHighlightReel.swift`~~ | ~~197~~ | ~~Never referenced~~ | DELETED |
| ~~`JournalSegment` enum~~ | ~~4~~ | ~~Unused in `JournalShared.swift`~~ | DELETED |
| `Views/Trips/Export/TripExportFilmStrip.swift` | all | Defined but never used — no `.filmStrip` case in `ExportStyle` enum | |

**Total deleted:** ~2,953 lines of dead code removed (2026-02-17).

---

## 9. Debug Code in Production

| File | Line | Description |
|------|------|-------------|
| `Services/AuthenticationService.swift` | 34-36 | `debugBypassAuth` flag (currently `false` in both DEBUG and release) |
| `Views/Authentication/AuthenticationView.swift` | 39-54 | `#if DEBUG` "Debug Sign In" button — OK for dev, ensure stripped in release |

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

`Services/FeedService.swift`: Two `Task { for await change in ... }` blocks iterate infinite async sequences with no cancellation. If `subscribeToRealtime` is called multiple times (e.g. sign-out/sign-in cycle), tasks pile up.

**Fix:** Store tasks and cancel on unsubscribe:
```swift
private var realtimeLogTask: Task<Void, Never>?
private var realtimeTripTask: Task<Void, Never>?
```

### `SyncEngine` public mutable state

`Services/SyncEngine.swift`: `var isSyncing` and `var isOnline` are publicly writable — Views could accidentally mutate sync state.

**Fix:** `private(set) var isSyncing = false`

---

## 11. Duplicate Code

### 11a. `extractCity(from:)` — 4 separate implementations

The city extraction logic is implemented independently in 4 places with diverging behavior:

| File | Line | Return Type | Notes |
|------|------|-------------|-------|
| `ProfileView.swift` | 1072 | `String?` | Returns `nil` on failure |
| `WantToGoListView.swift` | 268 | `String` | Returns `"Unknown"`, has extra state/zip heuristic |
| `ProfileStatsService.swift` | 359 | `String?` (static) | Identical to ProfileView — ideal canonical location |
| `ShareLogView.swift` | 267 | `String` | Different algorithm entirely (`parts[1]` vs `parts[count-3]`) |

**Fix:** Use `ProfileStatsService.extractCity(from:)` as the single source of truth. Delete the other 3 implementations.

### 11b. Place selection in `SearchPlaceView.swift`

`Views/Logging/SearchPlaceView.swift`: Four nearly identical functions (`selectPrediction`, `selectNearbyPlace`, `selectRecentSearch`, cached variant) all repeat the same pattern.

**Fix:** Extract `func selectPlace(byID placeId: String) async`.

### 11c. Heatmap date grid logic

7 heatmap views all implement identical week-grid generation with the same `calendar.date(byAdding:)!` pattern.

**Fix:** Extract to a shared `HeatmapDateGrid` helper.

### 11d. `RemoteLog`/`RemoteTrip` at file scope

`Services/SyncEngine.swift`: Internal Codable types defined at file scope visible to the whole module.

**Fix:** Nest inside `SyncEngine` or mark `private`.

---

## 12. Magic Numbers & Inline Colors

### Colors duplicated outside `SonderTheme.swift`

| File | Line | Issue |
|------|------|-------|
| `sonderApp.swift` | 40-43, 63 | `UIColor(red: 0.98, green: 0.96, ...)` duplicates `SonderColors.cream` |
| `Views/Journal/JournalPolaroidView.swift` | 151-189+ | Multiple inline `Color(red:...)` values |
| `Views/Journal/MasonryTripsGrid.swift` | 233-234 | Near-duplicate of `SonderColors.terracotta` |
| `Views/Trips/TripDetailView.swift` | 1804-1809 | Inline time-of-day color tuples |
| `Views/Trips/Export/TripExportConfig.swift` | 70-172 | ~60 inline `Color(red:...)` values (export theme palettes) |
| `Views/Journal/JournalBoardingPassView.swift` | 102-374 | ~10 inline color values |
| `Views/Feed/FeedLogDetailView.swift` | 203-204 | Inline gradient colors |

**Fix:** Expose `UIColor` variants from `SonderTheme.swift` for UIKit contexts. Reference `SonderColors` everywhere else. For export themes, consider a `TripExportColors` namespace.

### Hardcoded frame dimensions

| File | Lines | Values |
|------|-------|--------|
| `Views/Share/ShareLogView.swift` | 282, 294 | `1080 x 1350` (Instagram ratio) — name as constant |

---

## 13. Naming Conventions

| File | Line | Issue | Fix |
|------|------|-------|-----|
| `sonderApp.swift` | 13 | `struct sonderApp` lowercase type name | Rename to `SonderApp` |
| `Services/ProfileStatsService.swift` | 13 | Caseless `enum ProfileStatsService` used as namespace but named like a service class | Rename to `ProfileStatsCalculator` or convert to `struct` |
| `Services/AuthenticationService.swift` | 34-36 | `#if DEBUG` / `#else` branches both set `debugBypassAuth = false` — dead conditional | Remove `#if`/`#else`, keep single declaration |

---

## Recommended Fix Order

1. ~~**Quick wins (30 min):** Fix nil-check-then-force-unwrap pattern (5 locations), fix `UIWindowScene.windows` deprecation (2 locations)~~ **DONE**
2. ~~**Dead code cleanup (5 min):** Delete 8 unused files + JournalSegment enum~~ **DONE** — 2,953 lines removed
3. **Auth safety (15 min):** Add error handling to Apple Sign-In `try?` and sign-out `try?`
4. **Force unwrap safety (30 min):** Add fallbacks for `withDesign(.serif)!`, `sortedDays.last!`, `cityPlaceSets.max(...)!`, URL construction
5. **Concurrency safety (1 hr):** Add `@MainActor` to service classes, cancel FeedService realtime tasks, add `private(set)` to SyncEngine state
6. **Duplicate code (30 min):** Consolidate `extractCity` to one implementation, extract shared place selection helper
7. **Logging cleanup (1-2 hrs):** Replace `print()` with `os.Logger` across all services and views
8. **Deprecation sweep (2-3 hrs):** Replace `.foregroundColor()` with `.foregroundStyle()` across all ~40 files
9. **Inline colors (30 min):** Replace hardcoded `Color(red:...)` / `UIColor(red:...)` with `SonderColors` references
10. **File size (ongoing):** Extract large views into smaller components as you touch those files
11. **Remaining dead code (5 min):** Delete `TripExportFilmStrip.swift` or add `.filmStrip` to `ExportStyle`
