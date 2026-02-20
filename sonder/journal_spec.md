# Journal Page — Complete Technical & Design Specification

> This document captures every detail of the Journal feature as of Feb 2026. It is intended to give a developer or LLM full context to modify, extend, or rebuild the journal without prior knowledge of the codebase.

---

## Table of Contents

1. [Purpose & Design Philosophy](#1-purpose--design-philosophy)
2. [File Map](#2-file-map)
3. [Data Models](#3-data-models)
4. [TripService (Backend Integration)](#4-tripservice-backend-integration)
5. [JournalContainerView (Main Screen)](#5-journalcontainerview-main-screen)
6. [MasonryTripsGrid](#6-masonrytripsgrid)
7. [TripCard](#7-tripcard)
8. [TripDetailView](#8-tripdetailview)
9. [CityLogsView](#9-citylogsview)
10. [LogDetailView](#10-logdetailview)
11. [CreateEditTripView](#11-createedittripview)
12. [Shared Utilities](#12-shared-utilities)
13. [Navigation Architecture](#13-navigation-architecture)
14. [Design System Usage](#14-design-system-usage)
15. [Supabase Schema & Queries](#15-supabase-schema--queries)
16. [Known Limitations & Future Work](#16-known-limitations--future-work)

---

## 1. Purpose & Design Philosophy

The Journal is the user's **personal travel diary** — Tab 3 in Sonder. It shows all their trips in a Pinterest-style masonry grid connected by a decorative dotted trail line. Logs not assigned to any trip are collected in a collapsible "Not in a trip" section at the bottom.

### Design Principles
- **"Warm Journal" vibe** — cozy, nostalgic, intimate. Cream backgrounds, terracotta accents, soft shadows.
- **Trips are the primary organizing unit** — logs are grouped into trips; the journal page shows trips, not individual logs.
- **Visual storytelling** — cover photos, masonry layout, and zigzag trail create a scrapbook feel.
- **No clutter** — simple search bar, no complex filtering on the main page. Filtering is implicit via search text.

### What the Journal Does NOT Have
- Segment picker between "Trips" and "Logs" (removed — trips-only view)
- Rating/tag/trip filter chips (removed — search bar handles filtering)
- Grid/list view toggle (removed — masonry grid only)
- Social features (no likes, comments, sharing)

---

## 2. File Map

```
sonder/
├── Models/
│   ├── Trip.swift                      # SwiftData @Model for Trip
│   └── Log.swift                       # SwiftData @Model for Log
├── Services/
│   └── TripService.swift               # Trip CRUD, invitations, collaborators
├── Views/
│   ├── Journal/
│   │   ├── JournalContainerView.swift  # Main journal tab view
│   │   ├── MasonryTripsGrid.swift      # Masonry grid + zigzag trail + unassigned logs
│   │   ├── JournalShared.swift         # Shared types: sorting, column assignment, preferences
│   │   └── CityLogsView.swift          # City-specific logs grouped by trip (navigated from Profile)
│   ├── Trips/
│   │   ├── TripCard.swift              # Reusable trip card component
│   │   ├── TripDetailView.swift        # Full trip detail with timeline, map, story mode
│   │   └── CreateEditTripView.swift    # Create/edit trip form with photo upload
│   └── LogDetail/
│       └── LogDetailView.swift         # Editable log detail (rating, note, tags, trip, photo)
```

---

## 3. Data Models

### 3.1 Trip (SwiftData `@Model`)

```swift
@Model class Trip {
    var id: String                    // UUID string
    var name: String
    var tripDescription: String?
    var startDate: Date?
    var endDate: Date?
    var coverPhotoURL: String?
    var createdBy: String             // User ID of creator
    var collaboratorIDs: [String]     // User IDs with access
    var createdAt: Date
    var updatedAt: Date
}
```

### 3.2 Log (SwiftData `@Model`)

```swift
@Model class Log {
    var id: String
    var userID: String
    var placeID: String               // Google Place ID
    var tripID: String?               // Optional trip association
    var rating: Rating                // .skip | .solid | .mustSee
    var photoURL: String?
    var note: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
}
```

### 3.3 Rating Enum

```swift
enum Rating: String, Codable {
    case skip
    case solid
    case mustSee = "must_see"
}
```

Each rating has an `emoji` property and a display label.

### 3.4 Place (SwiftData `@Model`)

```swift
@Model class Place {
    var id: String                    // Google Place ID
    var name: String
    var address: String
    var lat: Double
    var lng: Double
    var photoReference: String?       // Google Places photo reference
    var coordinate: CLLocationCoordinate2D { get }
}
```

---

## 4. TripService (Backend Integration)

`TripService` is an `@Observable` `@MainActor` class injected via `@Environment`.

### 4.1 CRUD Operations

| Method | Description |
|--------|-------------|
| `createTrip(name:description:startDate:endDate:coverPhotoURL:createdBy:) -> Trip` | Creates trip locally + upserts to Supabase |
| `updateTrip(_ trip: Trip)` | Updates all fields locally + Supabase |
| `deleteTrip(_ trip: Trip)` | Unassigns all logs (sets `tripID = nil`), then deletes trip |
| `deleteTripAndLogs(_ trip: Trip, syncEngine: SyncEngine)` | Deletes all logs via `syncEngine.deleteLog(id:)`, then deletes trip |

### 4.2 Fetch Operations

| Method | Description |
|--------|-------------|
| `fetchTrips(for userID:) -> [Trip]` | Trips where user is creator OR collaborator |
| `fetchTrip(id:) -> Trip?` | Single trip by ID |
| `getLogsForTrip(_ tripID:) -> [Log]` | All logs associated with a trip |

### 4.3 Invitation System

| Method | Description |
|--------|-------------|
| `sendInvitation(to:for:from:)` | Creates pending invitation in Supabase |
| `fetchPendingInvitations(for:) -> [TripInvitation]` | Pending invitations for a user |
| `acceptInvitation(_ invitation:)` | Updates status + adds user as collaborator |
| `declineInvitation(_ invitation:)` | Updates status to declined |
| `getPendingInvitationCount(for:) -> Int` | Badge count for pending invitations |

### 4.4 Collaborator Management

| Method | Description |
|--------|-------------|
| `removeCollaborator(userID:from:)` | Removes user from `collaboratorIDs` |
| `leaveTrip(_ trip:userID:)` | Alias for `removeCollaborator` |
| `canEdit(trip:userID:) -> Bool` | Owner-only check |
| `hasAccess(trip:userID:) -> Bool` | Owner OR collaborator |

### 4.5 Log Association

| Method | Description |
|--------|-------------|
| `associateLog(_ log:with:)` | Sets `log.tripID`, syncs to Supabase |

### 4.6 Delete Behavior

Trip deletion presents a two-option alert:
- **"Delete Trip & Logs"** — deletes all logs in the trip via `syncEngine.deleteLog(id:)`, then deletes the trip
- **"Delete Trip, Keep Logs"** — sets `tripID = nil` on all logs (orphans them to "Not in a trip"), then deletes the trip

---

## 5. JournalContainerView (Main Screen)

`JournalContainerView.swift` — the root view for Tab 3.

### 5.1 Environment & Queries

```swift
@Environment(AuthenticationService.self) private var authService
@Environment(SyncEngine.self) private var syncEngine
@Environment(\.modelContext) private var modelContext
@Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]
@Query(sort: \Trip.createdAt, order: .reverse) private var allTrips: [Trip]
@Query private var places: [Place]
```

### 5.2 State

| State | Type | Purpose |
|-------|------|---------|
| `searchText` | `String` | Search bar text |
| `showCreateTrip` | `Bool` | Shows CreateEditTripView sheet |
| `selectedLog` | `Log?` | Navigates to LogDetailView |
| `selectedTrip` | `Trip?` | Navigates to TripDetailView |

### 5.3 Computed Data Pipeline

```
allLogs → userLogs (filtered to current user's ID)
allTrips → userTrips (filtered to creator OR collaborator, sorted reverse chronological)
                ↓
userTrips + searchText → filteredTrips (name/description search)
userLogs + searchText → filteredLogs (place name/address/note/tags search)
                ↓
            MasonryTripsGrid(trips: filteredTrips, filteredLogs: filteredLogs, ...)
```

**Trip sorting**: Uses `startDate` if available, otherwise `createdAt`. See `sortTripsReverseChronological()` in JournalShared.swift.

**Search filtering**:
- Trips: matches against `trip.name` and `trip.tripDescription`
- Logs: matches against place name, place address, note text, and tags (joined as space-separated string)

### 5.4 View Structure

```
NavigationStack
├── Group
│   ├── If empty (no logs + no trips): emptyState
│   └── Else: VStack
│       ├── searchBar
│       └── MasonryTripsGrid(trips:allLogs:places:filteredLogs:...)
├── .background(SonderColors.cream)
├── .onTapGesture → dismiss keyboard
├── .navigationTitle("Journal")
├── .toolbar → "+" button (topBarTrailing) → showCreateTrip
├── .sheet → CreateEditTripView(mode: .create)
├── .navigationDestination(item: selectedLog) → LogDetailView
└── .navigationDestination(item: selectedTrip) → TripDetailView
```

### 5.5 Empty State

Two variants:
- **Syncing**: ProgressView + "Syncing your journal..."
- **Empty**: Book icon + "Your Journal Awaits" + instructional text

### 5.6 Search Bar

- HStack with magnifying glass icon + TextField + clear button (X when text is non-empty)
- `warmGray` background, `radiusMd` rounded corners
- Placeholder: "Search trips..."
- Keyboard dismissal: `.onTapGesture` on the parent sends `resignFirstResponder`

### 5.7 Toolbar

Single toolbar item: **"+"** button in `topBarTrailing` position
- Terracotta colored
- Presents `CreateEditTripView(mode: .create)` as a sheet

---

## 6. MasonryTripsGrid

`MasonryTripsGrid.swift` — Pinterest-style two-column grid with zigzag trail.

### 6.1 Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| `trips` | `[Trip]` | Already sorted most-recent-first |
| `allLogs` | `[Log]` | All logs (for counting per trip) |
| `places` | `[Place]` | All places (for unassigned log display) |
| `filteredLogs` | `[Log]` | Search-filtered logs (for unassigned section) |
| `selectedTrip` | `Binding<Trip?>` | Navigation binding |
| `selectedLog` | `Binding<Log?>` | Navigation binding |
| `deleteLog` | `(Log) -> Void` | Delete callback |
| `searchText` | `String` | Auto-expands unassigned section when non-empty |

### 6.2 Column Assignment Algorithm

Uses a **greedy shortest-column** algorithm (`assignMasonryColumns()` in JournalShared.swift):

1. Maintain running height for left (column 0) and right (column 1)
2. For each trip in order, assign to the shorter column
3. Add estimated card height + spacing to that column's total

Height estimation (`estimateCardHeight(for:)`):
- Base: 80pt (compact cover photo)
- +24pt (info section padding)
- +22pt (name + owner badge)
- +30pt if trip has description
- +18pt if trip has start date
- +18pt (stats row)

### 6.3 Zigzag Trail (`ZigzagTrailView`)

A `Canvas` view rendered as a background behind the masonry grid:

- **Line**: Smooth bezier curve through card centers, dashed (6on/4off), 1.5pt width, terracotta at 30% opacity
- **Dots**: Filled circles at each card center (5pt radius for first, 4pt for others), terracotta at 50% opacity
- Uses `CardFramePreference` (PreferenceKey) to collect card frames from GeometryReaders
- Cards report their frame in the `"trailGrid"` named coordinate space

### 6.4 "Not in a Trip" Section

- Collapsible section for logs where `tripID == nil`
- Header: "NOT IN A TRIP" (uppercase, tracked 0.5pt) + count + chevron
- Collapsed by default
- **Auto-expands when `searchText` changes to non-empty** (via `.onChange`)
- Expanded: shows `JournalLogRow` for each unassigned log
- Tapping a log sets `selectedLog` → navigates to LogDetailView

### 6.5 Empty State

If no trips and no unassigned logs:
- Suitcase icon (40pt) + "No trips yet" + instructional text

---

## 7. TripCard

`TripCard.swift` — reusable card component used in MasonryTripsGrid.

### 7.1 Inputs

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `trip` | `Trip` | — | Trip data |
| `logCount` | `Int` | — | Number of logs in trip |
| `isOwner` | `Bool` | — | Shows owner badge if false |
| `compact` | `Bool` | `false` | Shorter cover photo height |

### 7.2 Layout

```
VStack(spacing: 0)
├── Cover Photo Section
│   ├── If has photo: DownsampledAsyncImage (height: compact ? 80 : 120)
│   └── Else: gradient placeholder (terracotta → ochre, 0.3/0.2 opacity)
├── Info Section (padding: sm)
│   ├── Trip name (headline, lineLimit 2)
│   ├── If !isOwner: owner badge (person icon + "Shared")
│   ├── Description preview (caption, lineLimit 2)
│   ├── Date range (caption, inkMuted)
│   └── Stats row: log count + collaborator indicator
```

### 7.3 Styling

- `warmGray` background, `radiusLg` corners
- Soft shadow: `.black.opacity(0.05), radius: 4, y: 2`
- Cover photo clips to top corners only via `.clipShape` on the card

---

## 8. TripDetailView

`TripDetailView.swift` — full trip detail with timeline, map, and story mode. (689 lines)

### 8.1 Key Sections

1. **Story Hero Header**: Full-width cover photo with trip name overlay, date range, gradient scrim
2. **Stats Bar**: Horizontal stats — place count, day count, rating breakdown (mustSee/solid/skip counts)
3. **Map Section**: MapKit view with polyline route connecting logged places in chronological order, numbered pin markers
4. **Timeline**: Day-grouped log cards (`MomentCard`) in chronological order

### 8.2 MomentCard (nested)

Each log is displayed as a "moment" card:
- Photo (full width, rounded)
- Place name + rating pill
- Note text
- Tags
- Date
- Tap → opens LogDetailView

### 8.3 Story Mode

Tap the story header → `TripStoryPageView` presented as full-screen cover:
- Swipeable full-screen pages, one per log
- Photo background with text overlay
- Auto-advance timer option

### 8.4 Edit Actions

- **Edit button** (toolbar): opens `CreateEditTripView(mode: .edit(trip))` as sheet. Owner only.
- **Collaborators button**: opens `TripCollaboratorsView` sheet
- **Cover photo**: long-press or edit to change via `EditableImagePicker`

### 8.5 Navigation

- `LogDetailView` — tap a moment card
- `CreateEditTripView` — edit button (sheet)
- `TripCollaboratorsView` — collaborators button (sheet)
- `TripStoryPageView` — tap story hero (full-screen cover)

---

## 9. CityLogsView

`CityLogsView.swift` — navigated to from Profile's city photo mosaic. Shows all logs in a specific city, grouped by trip.

### 9.1 Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| `title` | `String` | City name (used as navigation title) |
| `logs` | `[Log]` | All logs in that city |

### 9.2 Data Pipeline

```
logs → Dictionary(grouping:) by tripID
     → sections: [(trip: Trip?, logs: [Log])]
     → sorted by most recent log date within each group
     → untripped logs (tripID == nil) appended at bottom
```

**Important**: Untripped logs use `logs.filter { $0.tripID == nil }` (not dictionary nil-key lookup, which has Swift double-optional issues).

### 9.3 Stats Header

Capsule showing: `"{n} places · {n} must-see · {date range}"`
- Date range: `"Feb 2026"` if all same month, or `"Jan 2026 – Feb 2026"` if spanning months

### 9.4 Trip Section Layout

Each trip group is a card:
```
VStack (warmGray background, radiusLg corners, soft shadow)
├── Trip Header (tappable → TripDetailView)
│   ├── Cover photo circle (40pt)
│   ├── Trip name + date range + log count
│   └── Chevron
└── Log Cards (per log)
    ├── Photo thumbnail (80×80, radiusSm)
    ├── Place name
    ├── Rating pill (emoji + label, colored capsule)
    ├── Note snippet (2 lines)
    └── Date
```

**"No Trip" section**: Same card layout but with "No Trip" header text instead of trip details.

### 9.5 Navigation

- Tap trip header → `TripDetailView(trip:)`
- Tap log card → `LogDetailView(log:place:)` (only if Place is found; falls back to "Unknown Place" display-only)

---

## 10. LogDetailView

`LogDetailView.swift` — editable detail view for a single log. (763 lines)

### 10.1 Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| `log` | `Log` | The log to view/edit |
| `place` | `Place` | Associated place (read-only) |
| `onDelete` | `(() -> Void)?` | Callback before deletion |

### 10.2 Editable Fields

| Field | Type | Notes |
|-------|------|-------|
| `rating` | `Rating` | 3 emoji buttons (must-see, solid, skip) |
| `note` | `String` | 280 character limit with counter |
| `tags` | `[String]` | Via `TagInputView` component |
| `selectedTripID` | `String?` | Trip association picker |
| `selectedImage` / `currentPhotoURL` | Photo state | Upload via PhotoService |

### 10.3 Trip Picker

- Shows up to 3 most recently used trips as scrollable chips
- "More" button → `AllTripsPickerSheet` (sheet)
- "New Trip" button → inline trip creation
- Selected trip highlighted with terracotta

### 10.4 Save Flow

1. Upload photo if changed (via `PhotoService`)
2. Update `Log` model properties
3. Save to local ModelContext
4. `syncEngine.syncNow()` to push to Supabase
5. Show "Saved" toast (checkmark + text in capsule) for ~1 second
6. Haptic feedback (`UINotificationFeedbackGenerator.success`)

### 10.5 Delete Flow

- "Delete Log" button (red, destructive)
- Confirmation alert: "This cannot be undone"
- Calls `syncEngine.deleteLog(id:)`
- Calls `onDelete?()` callback
- Dismisses view

### 10.6 Unsaved Changes

- `hasChanges` computed property tracks differences from original log
- Custom back button with discard warning alert if changes exist
- Alert: "You have unsaved changes" → "Discard" / "Keep Editing"

---

## 11. CreateEditTripView

`CreateEditTripView.swift` — form for creating or editing a trip. (405 lines)

### 11.1 Mode

```swift
enum TripFormMode {
    case create
    case edit(Trip)
}
```

### 11.2 Fields

| Field | Type | Notes |
|-------|------|-------|
| `name` | `String` | Required (trimmed, non-empty) |
| `tripDescription` | `String` | Optional |
| `startDate` | `Date?` | Optional, graphical DatePicker |
| `endDate` | `Date?` | Optional, constrained to >= startDate |
| `coverPhotoURL` | `String?` | Via EditableImagePicker + PhotoService upload |

### 11.3 Form Layout

```
NavigationStack > Form
├── Section: Cover Photo
│   ├── Photo preview (150pt height)
│   │   ├── Local image (if just selected)
│   │   ├── Remote URL (if editing existing)
│   │   └── Gradient placeholder
│   └── Buttons: "Add/Change Photo" + "Remove" (if photo exists)
├── Section "Name": TextField
├── Section "Description (Optional)": TextField (3-6 lines)
├── Section "Dates (Optional)":
│   ├── Start Date row (Add/display/clear + graphical picker)
│   └── End Date row (same, constrained to >= start)
└── Section (edit only): "Delete Trip" button (destructive)
```

### 11.4 Save Flow

1. Trim name, validate non-empty
2. If editing: update trip properties + `tripService.updateTrip()`
3. If creating: `tripService.createTrip()`
4. Haptic feedback (`.success`)
5. If editing: show "Saved" toast → dismiss after 1s
6. If creating: dismiss immediately

### 11.5 Delete Alert

Two-option confirmation:
- **"Delete Trip & Logs"** (destructive) → `tripService.deleteTripAndLogs(trip, syncEngine:)`
- **"Delete Trip, Keep Logs"** → `tripService.deleteTrip(trip)` (sets logs' `tripID = nil`)
- **"Cancel"**

### 11.6 Photo Upload

1. `EditableImagePicker` sheet for photo selection + cropping
2. On selection: immediately starts upload via `photoService.uploadPhoto(image, for: userID)`
3. Shows loading overlay on photo preview during upload
4. Sets `coverPhotoURL` on completion

---

## 12. Shared Utilities

`JournalShared.swift` contains types shared across journal views.

### 12.1 CardFramePreference

PreferenceKey for collecting card frames in the masonry grid. Keyed by chronological index.

```swift
struct CardFramePreference: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
```

### 12.2 Trip Sorting

```swift
func sortTripsReverseChronological(_ trips: [Trip]) -> [Trip]
```

Sorts by `startDate` if available, otherwise by `createdAt`. Most recent first.

### 12.3 Masonry Column Assignment

```swift
struct MasonryColumnAssignment {
    let trip: Trip
    let index: Int     // chronological index
    let column: Int    // 0 = left, 1 = right
}

func assignMasonryColumns(trips:spacing:estimateHeight:) -> [MasonryColumnAssignment]
```

Greedy shortest-column balancing algorithm. Preserves input order.

---

## 13. Navigation Architecture

```
MainTabView (Tab 3: Journal)
└── JournalContainerView
    ├── "+" toolbar button → CreateEditTripView(mode: .create) [sheet]
    ├── Tap trip card → TripDetailView
    │   ├── Tap moment card → LogDetailView
    │   │   ├── Trip picker → AllTripsPickerSheet [sheet]
    │   │   └── "New Trip" → inline creation
    │   ├── Edit button → CreateEditTripView(mode: .edit) [sheet]
    │   │   └── Delete Trip → two-option alert
    │   ├── Collaborators → TripCollaboratorsView [sheet]
    │   └── Story header → TripStoryPageView [fullScreenCover]
    └── Tap unassigned log → LogDetailView
        └── (same sub-navigation as above)

ProfileView (City Mosaic)
└── Tap city → CityLogsView
    ├── Tap trip header → TripDetailView (same as above)
    └── Tap log card → LogDetailView (same as above)
```

**Navigation methods used:**
- `.navigationDestination(item:)` — for `LogDetailView` and `TripDetailView` from JournalContainerView
- `NavigationLink` — for trip headers and log cards in CityLogsView
- `.sheet(isPresented:)` — for CreateEditTripView, ExploreFilterSheet, AllTripsPickerSheet
- `.fullScreenCover(item:)` — for TripStoryPageView, RatePlaceView

---

## 14. Design System Usage

### Colors

| Usage | Token |
|-------|-------|
| Page background | `SonderColors.cream` |
| Card backgrounds | `SonderColors.warmGray` |
| Log card inner background | `SonderColors.cream.opacity(0.6)` |
| Search bar background | `SonderColors.warmGray` |
| Primary accent | `SonderColors.terracotta` |
| Text (primary) | `SonderColors.inkDark` |
| Text (secondary) | `SonderColors.inkMuted` |
| Text (tertiary) | `SonderColors.inkLight` |
| Trail line | Terracotta at 30% opacity |
| Trail dots | Terracotta at 50% opacity |
| Rating pill: must-see | `SonderColors.pinColor(for: .mustSee)` (terracotta) |
| Rating pill: solid | `SonderColors.pinColor(for: .solid)` (sage) |
| Rating pill: skip | `SonderColors.pinColor(for: .skip)` (inkLight) |
| Rating pill background | Same color at 15% opacity |
| Cover placeholder gradient | Terracotta 0.3 → Ochre 0.2 |

### Typography

| Usage | Token |
|-------|-------|
| Navigation title | System (set by `.navigationTitle`) |
| Trip/place names | `SonderTypography.headline` |
| Body text | `SonderTypography.body` |
| Captions, dates, stats | `SonderTypography.caption` |
| Section headers | `SonderTypography.caption` (uppercase, tracked) |
| Place name in log card | `.system(size: 14, weight: .semibold)` |
| Rating pill text | `.system(size: 12, weight: .medium)` |
| Date text | `.system(size: 12)` |

### Spacing

| Usage | Token |
|-------|-------|
| Page horizontal padding | `SonderSpacing.md` |
| Card internal padding | `SonderSpacing.sm` |
| Grid column gap | `SonderSpacing.sm` |
| Grid row gap | `SonderSpacing.sm` |
| Search bar padding | `SonderSpacing.sm` |
| Card corners | `SonderSpacing.radiusLg` |
| Photo corners | `SonderSpacing.radiusSm` or `SonderSpacing.radiusMd` |
| Bottom spacer | 80pt (for FAB clearance) |

### Shadows

| Usage | Style |
|-------|-------|
| Trip cards | `.black.opacity(0.05), radius: 4, y: 2` |
| Trip section cards (CityLogsView) | `.black.opacity(0.05), radius: 4, y: 2` |
| Saved toast | `SonderShadows.softOpacity, radius: softRadius, y: softY` |

### Animations

| Trigger | Animation |
|---------|-----------|
| Unassigned section expand/collapse | `.easeInOut(duration: 0.2)` |
| Saved toast appear/disappear | `.easeInOut(duration: 0.25)` |

---

## 15. Supabase Schema & Queries

### Tables

#### `trips`
```sql
id TEXT PRIMARY KEY
name TEXT NOT NULL
description TEXT
start_date TIMESTAMPTZ
end_date TIMESTAMPTZ
cover_photo_url TEXT
created_by TEXT REFERENCES users(id)
collaborator_ids TEXT[]
created_at TIMESTAMPTZ DEFAULT now()
updated_at TIMESTAMPTZ DEFAULT now()
```

#### `logs`
```sql
id TEXT PRIMARY KEY
user_id TEXT REFERENCES users(id)
place_id TEXT REFERENCES places(id)
trip_id TEXT REFERENCES trips(id)
rating TEXT NOT NULL               -- 'skip' | 'solid' | 'must_see'
photo_url TEXT
note TEXT
tags TEXT[]
created_at TIMESTAMPTZ DEFAULT now()
updated_at TIMESTAMPTZ DEFAULT now()
```

#### `trip_invitations`
```sql
id TEXT PRIMARY KEY
trip_id TEXT REFERENCES trips(id)
inviter_id TEXT REFERENCES users(id)
invitee_id TEXT REFERENCES users(id)
status TEXT DEFAULT 'pending'      -- 'pending' | 'accepted' | 'declined'
created_at TIMESTAMPTZ DEFAULT now()
```

### Key Queries

**Create trip:**
```sql
INSERT INTO trips (id, name, description, start_date, end_date, cover_photo_url, created_by, collaborator_ids)
VALUES (...)
ON CONFLICT (id) DO UPDATE SET ...
```

**Fetch user's trips:**
```sql
SELECT * FROM trips
WHERE created_by = {userID}
   OR collaborator_ids @> ARRAY[{userID}]
ORDER BY created_at DESC
```

**Delete trip (keep logs):**
```sql
-- Step 1: Unassign logs
UPDATE logs SET trip_id = NULL WHERE trip_id = {tripID}
-- Step 2: Delete trip
DELETE FROM trips WHERE id = {tripID}
```

**Delete trip and logs:**
```sql
-- Step 1: Delete each log via SyncEngine (handles local + remote)
-- Step 2: Delete trip
DELETE FROM trips WHERE id = {tripID}
```

---

## 16. Known Limitations & Future Work

### Current Limitations

1. **No drag-to-reorder** — trips are always sorted by date; no manual ordering.
2. **Masonry height estimation is approximate** — column balancing may be slightly uneven if actual rendered heights differ from estimates (e.g., long names wrapping).
3. **No trip search within CityLogsView** — only the main journal has search.
4. ~~**JournalSegment enum is unused**~~ — DELETED (2026-02-17).
5. **500-log query limit** — TripService fetches are capped by Supabase pagination defaults.
6. **No trip templates or duplication** — can't clone a trip structure.
7. **Collaborator editing is owner-only** — collaborators can view but not edit trip metadata.

### Future Improvements

- [ ] Pin clustering for trips with many logs on the map section
- [ ] Trip sharing via deep links
- [ ] Trip templates (duplicate an existing trip's structure)
- [ ] Drag-to-reorder logs within a trip timeline
- [ ] Export trip as PDF/image for sharing
- [x] ~~Clean up `JournalSegment` enum and `JournalView.swift` legacy code~~ (deleted 2026-02-17)
- [ ] Offline trip creation (currently requires Supabase connectivity)
