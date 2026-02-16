# Explore Page — Complete Technical & Design Specification

> This document captures every detail of the Explore (Map) feature as of Feb 2026. It is intended to give a developer or LLM full context to modify, extend, or rebuild the explore map without prior knowledge of the codebase.

---

## Table of Contents

1. [Purpose & Design Philosophy](#1-purpose--design-philosophy)
2. [File Map](#2-file-map)
3. [Data Models](#3-data-models)
4. [ExploreMapService (Backend Integration)](#4-exploremapservice-backend-integration)
5. [ExploreMapView (Main Screen)](#5-exploremapview-main-screen)
6. [Map Pins](#6-map-pins)
7. [Bottom Cards](#7-bottom-cards)
8. [Filter System](#8-filter-system)
9. [Friends Loved Carousel](#9-friends-loved-carousel)
10. [Map Helpers](#10-map-helpers)
11. [Navigation Architecture](#11-navigation-architecture)
12. [Design System Usage](#12-design-system-usage)
13. [Supabase Schema & Queries](#13-supabase-schema--queries)
14. [Known Limitations & Future Work](#14-known-limitations--future-work)

---

## 1. Purpose & Design Philosophy

The Explore page is **Tab 1** — the default landing screen of Sonder. It shows a full-screen map with pins representing places the user has logged, places their friends have logged, and places on their "Want to Go" list.

### Design Principles
- **Discovery through friends** — see where your friends have been, what they loved, and explore new places through trusted recommendations.
- **Three toggleable layers** — "Mine", "Friends", "Saved" (Want to Go) can be independently toggled to show/hide.
- **Smart overlap handling** — when the user and friends have both logged the same place, a single "combined" pin appears instead of stacking two pins.
- **Warm journal aesthetic** — cream backgrounds, terracotta accents, rounded corners, soft shadows. Consistent with the rest of the app.
- **No clutter** — pins are visually distinct by type. Bottom cards appear only when a pin is selected. A "Friends Loved" carousel provides passive discovery when nothing is selected.

### What the Explore Page Does NOT Have
- Search for new places (that's handled by the Log flow / Google Places search)
- Directions or routing
- Real-time friend locations
- Clustering of dense pins (each pin is individually rendered)

---

## 2. File Map

```
sonder/
├── Models/
│   └── ExploreMapItem.swift           # LogSnapshot, UnifiedMapPin, ExploreMapPlace, ExploreMapFilter
├── Services/
│   └── ExploreMapService.swift        # Friends data loading, pin computation, filtering
├── Views/
│   └── Map/
│       ├── ExploreMapView.swift       # Main map view (Tab 1), all state, data loading, navigation
│       ├── UnifiedMapPinView.swift    # Pin renderers: LogPinView, CombinedMapPinView, WantToGoTab
│       ├── ExploreMapPinView.swift    # Friends-only pin with avatar(s) and badges
│       ├── WantToGoMapPin.swift       # Standalone bookmark pin for Want to Go places
│       ├── UnifiedBottomCard.swift    # Context-aware bottom card for unified pins
│       ├── ExploreBottomCard.swift    # Bottom card for explore/friends pins (legacy)
│       ├── WantToGoBottomCard          # (Defined inline in ExploreMapView.swift) Bottom card for WTG pins
│       ├── ExploreFilterSheet.swift   # Filter sheet UI with all filter controls
│       ├── FriendsLovedCarousel.swift # Horizontal carousel for friends-loved places
│       └── MapHelpers.swift           # MapStyleOption enum, MKCoordinateRegion extension
```

---

## 3. Data Models

All models are in `ExploreMapItem.swift`.

### 3.1 LogSnapshot

A value-type snapshot of a `Log` (SwiftData model). Used instead of live `Log` references to prevent "detached backing data" crashes when logs are deleted while pins are displayed.

```swift
struct LogSnapshot: Equatable {
    let id: String
    let rating: Rating        // .skip | .solid | .mustSee
    let photoURL: String?
    let note: String?
    let createdAt: Date
    let tags: [String]

    init(from log: Log)       // Copies all fields from a live Log
}
```

### 3.2 UnifiedMapPin

The core pin type. An enum with three cases representing who logged a place:

```swift
enum UnifiedMapPin: Identifiable {
    case personal(logs: [LogSnapshot], place: Place)
    case friends(place: ExploreMapPlace)
    case combined(logs: [LogSnapshot], place: Place, friendPlace: ExploreMapPlace)
}
```

**Computed properties** (all cases):
| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | `"personal-{placeID}"`, `"friends-{placeID}"`, or `"combined-{placeID}"` |
| `placeID` | `String` | The Google Place ID |
| `coordinate` | `CLLocationCoordinate2D` | From the `Place` model |
| `placeName` | `String` | Human-readable place name |
| `photoReference` | `String?` | Google Places photo reference for the pin thumbnail |
| `userRating` | `Rating?` | User's own rating (nil for friends-only) |
| `friendCount` | `Int` | Number of distinct friends who logged this place |
| `isFriendsLoved` | `Bool` | True when 2+ friends rated must-see |
| `visitCount` | `Int` | Number of user's logs at this place |
| `bestRating` | `Rating` | Highest rating across user + friends |
| `latestDate` | `Date` | Most recent log date across all data |

### 3.3 ExploreMapPlace

Groups multiple `FeedItem`s sharing the same `place_id` for friends' map display:

```swift
struct ExploreMapPlace: Identifiable {
    let id: String                          // place_id
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let photoReference: String?
    var logs: [FeedItem]                    // All friend logs at this place
}
```

**Computed properties:**
- `users: [FeedItem.FeedUser]` — deduplicated users
- `friendCount: Int` — count of distinct friends
- `bestRating: Rating` — highest rating across all logs
- `hasNote: Bool` — true if any friend wrote a note
- `isFriendsLoved: Bool` — true when 2+ friends rated must-see
- `latestDate: Date` — most recent log date

### 3.4 ExploreMapFilter

Mutable value type holding all filter state:

```swift
struct ExploreMapFilter: Equatable {
    var rating: RatingFilter = .all
    var categories: Set<CategoryFilter> = []       // Empty = all categories
    var recency: RecencyFilter = .allTime
    var showWantToGo: Bool = true
    var showMyPlaces: Bool = true
    var showFriendsPlaces: Bool = true
    var selectedFriendIDs: Set<String> = []         // Empty = all friends
}
```

**Nested enums:**

#### RatingFilter
| Case | Label | Matches |
|------|-------|---------|
| `.all` | "All" | Any rating |
| `.solidPlus` | "Solid+" | `.solid` or `.mustSee` |
| `.mustSeeOnly` | "Must-See" | `.mustSee` only |

#### CategoryFilter
| Case | Label | Icon | Keywords (partial) |
|------|-------|------|--------------------|
| `.food` | "Food" | `fork.knife` | restaurant, sushi, pizza, burger... |
| `.coffee` | "Coffee" | `cup.and.saucer` | coffee, cafe, espresso... |
| `.nightlife` | "Nightlife" | `moon.stars` | bar, pub, club, brewery... |
| `.outdoors` | "Outdoors" | `leaf` | park, trail, hike, beach... |
| `.shopping` | "Shopping" | `bag` | shop, store, mall, boutique... |
| `.attractions` | "Attractions" | `building.columns` | museum, gallery, theater... |

Each `CategoryFilter` has:
- `placeTypes: Set<String>` — Google Place type IDs
- `keywords: [String]` — for name-based matching when place types aren't available

Category matching is keyword-based: `matchesCategories(placeName:)` checks if the lowercased place name contains any keyword from any active category.

#### RecencyFilter
| Case | Label | Cutoff |
|------|-------|--------|
| `.lastMonth` | "Last Month" | 1 month ago |
| `.lastYear` | "Last Year" | 1 year ago |
| `.allTime` | "All Time" | No cutoff |

**Filter helper properties:**
- `isActive: Bool` — true if any non-default filter is set
- `activeCount: Int` — number of active filter dimensions (defined in ExploreFilterSheet.swift extension)
- `activeLabels: [String]` — human-readable labels for active filters

### 3.5 MapPinTag

Lightweight `Hashable` type for SwiftUI `Map`'s selection binding:

```swift
enum MapPinTag: Hashable {
    case unified(String)   // UnifiedMapPin.id
    case wantToGo(String)  // WantToGoMapItem.id
}
```

### 3.6 WantToGoMapItem

Represents a "Want to Go" item on the map (places not yet logged):

```swift
struct WantToGoMapItem: Identifiable {
    let id: String
    let placeID: String
    let placeName: String
    let placeAddress: String?
    let photoReference: String?
    let coordinate: CLLocationCoordinate2D
}
```

---

## 4. ExploreMapService (Backend Integration)

`ExploreMapService` is an `@Observable` `@MainActor` class injected via `@Environment`.

### 4.1 State

```swift
var placesMap: [String: ExploreMapPlace] = [:]  // placeID → ExploreMapPlace
var isLoading = false
var hasLoaded = false
var error: String?
```

### 4.2 Key Methods

#### `loadFriendsPlaces(for currentUserID: String) async`
1. Fetches IDs of users the current user follows from `follows` table
2. Queries `logs` table for all logs by those users, joining `users` and `places` tables
3. Converts to `[FeedItem]`, groups by `place_id` into `placesMap`
4. Limited to 500 logs

**Supabase query:**
```
FROM logs
SELECT id, rating, photo_url, note, tags, created_at,
       users!logs_user_id_fkey(id, username, avatar_url, is_public),
       places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference)
WHERE user_id IN (followingIDs)
ORDER BY created_at DESC
LIMIT 500
```

#### `computeUnifiedPins(personalLogs: [Log], places: [Place]) -> [UnifiedMapPin]`
Merges personal logs with friends' places:
1. Groups personal logs by `placeID`, snapshots each `Log` into `LogSnapshot`
2. Sorts each group by `createdAt` descending
3. Computes set intersection/difference of personal vs friend place IDs
4. Creates `.combined` pins for overlap, `.personal` for user-only, `.friends` for friend-only

#### `filteredUnifiedPins(pins:filter:bookmarkedPlaceIDs:) -> [UnifiedMapPin]`
Applies all filters:
1. **Layer visibility**: Checks `showMyPlaces`, `showFriendsPlaces` flags. Combined pins may be downgraded to `.personal` or `.friends` if one layer is hidden.
2. **Friend ID filtering**: If `selectedFriendIDs` is non-empty, only shows friends' logs from those specific users.
3. **Bookmarked places**: Always shown regardless of layer visibility if in `bookmarkedPlaceIDs`.
4. **Rating filter**: Checks `bestRating` against filter
5. **Recency filter**: Checks `latestDate` against cutoff
6. **Category filter**: Keyword matching on place name

#### `friendsLovedPlaces() -> [ExploreMapPlace]`
Returns places where `isFriendsLoved` is true (2+ friends rated must-see).

#### `allFriends: [FeedItem.FeedUser]`
Computed property returning all unique friends who have logged at least one place, sorted alphabetically by username.

---

## 5. ExploreMapView (Main Screen)

`ExploreMapView.swift` — the main view for Tab 1.

### 5.1 Environment & Queries

```swift
@Environment(ExploreMapService.self) private var exploreMapService
@Environment(AuthenticationService.self) private var authService
@Environment(LocationService.self) private var locationService
@Environment(WantToGoService.self) private var wantToGoService
@Environment(GooglePlacesService.self) private var placesService
@Environment(PlacesCacheService.self) private var cacheService

@Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]
@Query private var places: [Place]
```

### 5.2 State

| State | Type | Purpose |
|-------|------|---------|
| `cameraPosition` | `MapCameraPosition` | Current map camera; defaults to `.userLocation(fallback:)` |
| `mapSelection` | `MapPinTag?` | Currently selected pin tag |
| `showDetail` | `Bool` | Triggers navigation to `LogDetailView` |
| `detailLogID` / `detailPlace` | `String?` / `Place?` | Selected log for detail navigation |
| `mapStyle` | `MapStyleOption` | Current map style (minimal/standard/hybrid/imagery) |
| `filter` | `ExploreMapFilter` | All active filters |
| `wantToGoMapItems` | `[WantToGoMapItem]` | Want to Go items loaded for map display |
| `showFilterSheet` | `Bool` | Shows the filter bottom sheet |
| `selectedFeedItem` | `FeedItem?` | Navigates to `FeedLogDetailView` for friend's log |
| `selectedPlaceDetails` | `PlaceDetails?` | Navigates to `PlacePreviewView` for WTG places |
| `placeToLog` | `Place?` | Triggers `RatePlaceView` full-screen cover |
| `isLoadingDetails` | `Bool` | Shows loading overlay when fetching place details |
| `hasLoadedOnce` | `Bool` | Prevents re-fitting pins on every appear |
| `visibleRegion` | `MKCoordinateRegion?` | Tracks visible map region for photo prefetching |

### 5.3 External Bindings

| Binding | Source | Purpose |
|---------|--------|---------|
| `focusMyPlaces: Binding<Bool>?` | `ProfileView` | When set to true, shows only personal pins |
| `hasSelection: Binding<Bool>?` | `MainTabView` | Reports whether a pin is selected (hides FAB) |

### 5.4 View Structure

```
NavigationStack
├── Map (full screen)
│   ├── UserAnnotation
│   ├── ForEach(annotatedPins) → Annotation with UnifiedMapPinView
│   └── ForEach(standaloneWantToGoItems) → Annotation with WantToGoMapPin
├── .overlay(top) → layerChips (Mine / Friends / Saved)
├── .overlay(bottom) → bottomContent
│   ├── If pin selected: UnifiedBottomCard or WantToGoBottomCard
│   └── If no selection + friends loved: FriendsLovedCarousel
├── .toolbar(leading) → Filter button with badge count
├── .toolbar(trailing) → Map style menu
├── .sheet → ExploreFilterSheet
├── .navigationDestination → LogDetailView (personal logs)
├── .navigationDestination → FeedLogDetailView (friend logs)
├── .navigationDestination → PlacePreviewView (WTG places)
└── .fullScreenCover → RatePlaceView (log a WTG place)
```

### 5.5 Computed Properties (Data Pipeline)

```
allLogs → personalLogs (filtered to current user)
                ↓
personalLogs + places → computeUnifiedPins() → unifiedPins
                                                    ↓
                            unifiedPins + filter → filteredUnifiedPins() → filteredPins
                                                                              ↓
                                                    filteredPins + wantToGoPlaceIDs → annotatedPins
                                                                                         ↓
                                                                                    Map Annotations

wantToGoMapItems - unifiedPins.placeIDs → standaloneWantToGoItems (separate bookmark pins)
```

### 5.6 Data Loading (`.task`)

1. Syncs Want to Go list via `wantToGoService.syncWantToGo(for:)`
2. Loads friends' places via `exploreMapService.loadFriendsPlaces(for:)`
3. Loads WTG map items via `wantToGoService.fetchWantToGoForMap(for:)`
4. On first load: fits camera to all pins, backfills missing photo references
5. Prefetches pin photos for visible viewport

### 5.7 Pin Selection Behavior

- **Tap a pin**: Map's built-in selection sets `mapSelection`. Camera pans/zooms to center the pin above the bottom card.
- **Tap selected pin again**: `simultaneousGesture` clears selection (Map doesn't always handle deselect).
- **Selection invalidation**: Multiple `onChange` handlers check `selectionIsValid` when data changes (logs deleted, filters changed, WTG items removed). Invalid selections are auto-cleared.
- **Camera zoom behavior**:
  - If zoomed out (city-level, span > 0.15°): zooms to neighborhood level (~3km)
  - If already zoomed in: pans without changing zoom
  - Camera offset shifts center down by 18% of span to keep pin above bottom card

### 5.8 Photo Prefetching

`prefetchPinPhotos()` pre-downloads place photos for pins in/near the current viewport:
- Only processes pins within 1.5x the visible region
- Caps at 20 photo references per batch
- Downloads at 112px width, downsamples to 56pt × screen scale
- Uses `ImageDownsampler.cache` (shared `NSCache`)
- Runs on `.utility` priority detached tasks

### 5.9 Focus Mode

Triggered by `ProfileView` via `focusMyPlaces` binding:
- Sets `showMyPlaces = true`, `showFriendsPlaces = false`
- Does NOT reposition camera — keeps user's current view
- Resets the binding to `false` immediately

### 5.10 Want to Go → Log Flow

When a user taps a WTG pin → taps the bottom card → views `PlacePreviewView` → taps "Log It":
1. Place is cached locally via `cacheService.cachePlace(from:)`
2. `RatePlaceView` is presented as full-screen cover
3. On completion: dismisses cover, clears selection, removes from WTG list

---

## 6. Map Pins

### 6.1 UnifiedMapPinView (`UnifiedMapPinView.swift`)

Router view that renders the appropriate pin style based on `UnifiedMapPin` type:

- **`.personal`**: Renders `LogPinView`
- **`.friends`**: Renders `ExploreMapPinView`
- **`.combined`**: Renders `CombinedMapPinView`

All pin views receive an `isWantToGo: Bool` to optionally show a bookmark badge.

#### LogPinView (Personal Pins)
- **Circle** (28pt) with place photo loaded via `GooglePlacesService.photoURL(for:maxWidth:)` + `DownsampledAsyncImage`
- **Ring color** based on rating: terracotta for `.mustSee`, sage for `.solid`, inkLight for `.skip`
- **Visit count badge** (top-right, 14pt circle): shows count if > 1 visit, uses same ring color
- **Pointer triangle** below the circle pointing to exact location
- **WantToGoTab** badge: bookmark icon overlay when `isWantToGo` is true

#### ExploreMapPinView (Friends-Only Pins)
Two variants based on friend count:
- **Single friend**: 28pt circle with friend's avatar, bordered with rating color
- **Multiple friends**: Overlapping avatars (up to 3), count badge showing total
- **Badges** (bottom-right, 14pt):
  - Heart badge when `isFriendsLoved` (2+ must-see ratings)
  - Text bubble badge when `hasNote`
  - Bookmark badge when `isWantToGo`

#### CombinedMapPinView
- Left side: personal photo circle with rating ring (same as LogPinView)
- Right side: friend avatar(s) overlapping, slightly offset
- Combined into a single annotation so they don't visually stack

#### WantToGoMapPin (`WantToGoMapPin.swift`)
- Simple 28pt circle with cream background
- Bookmark.fill icon in `wantToGoPin` color
- Used for standalone WTG pins (places not in any unified pin)

### 6.2 Pin Scaling
All pins scale to 1.25× when selected, with a 0.15s easeOut animation.

---

## 7. Bottom Cards

### 7.1 UnifiedBottomCard (`UnifiedBottomCard.swift`)

Shown when a unified pin is selected. Renders different content based on pin type:

#### Personal Card (`personalCard()`)
- **Single log**: Place photo (56pt), place name, rating pill, note snippet, date, chevron
- **Multiple logs**: Place name header + scrollable list of log rows (photo, rating, date)
- Tap navigates to `LogDetailView`

#### Friends Card (`friendsCard()`)
- Place photo (56pt), place name, friend count label
- "Friends Loved" badge if `isFriendsLoved`
- Scrollable friend review cards showing: avatar, username, rating pill, note snippet
- Tap a friend review → navigates to `FeedLogDetailView`
- "Focus on {username}" button → filters map to that friend only

#### Combined Card (`combinedCard()`)
- "You" section: same as personal card
- "Friends" section: same as friends card
- Separated by a subtle divider

**Common features:**
- Drag indicator capsule at top
- Drag-to-dismiss gesture (threshold: 80pt translation or 150pt predicted)
- Dismiss button (X) in top-right
- Cream background at 0.95 opacity, radiusLg corners, soft shadow
- Transition: `.move(edge: .bottom).combined(with: .opacity)`

### 7.2 WantToGoBottomCard (in `ExploreMapView.swift`)

Shown when a standalone WTG pin is selected:
- Place photo (56pt), place name, address
- "On your Want to Go list" label with bookmark icon
- `WantToGoButton` to remove from list
- Chevron indicating tappability
- Tap → fetches place details → navigates to `PlacePreviewView`
- Same drag-to-dismiss behavior as UnifiedBottomCard

### 7.3 ExploreBottomCard (`ExploreBottomCard.swift`)

Legacy bottom card for the old explore-only map. May still be referenced but largely superseded by `UnifiedBottomCard`.

---

## 8. Filter System

### 8.1 ExploreFilterSheet (`ExploreFilterSheet.swift`)

Presented as a `.medium` / `.large` detent sheet from the filter toolbar button.

**Sections (top to bottom):**

1. **Layers** — Toggle switches for "My Places" and "Friends' Places"
2. **Friend Picker** — Appears when Friends layer is on. Horizontal scroll of friend avatar chips. Tapping a friend toggles their ID in `selectedFriendIDs`. "All" chip clears the selection.
3. **Categories** — Grid of category chips (Food, Coffee, Nightlife, Outdoors, Shopping, Attractions). Multiple can be selected. "All" chip clears category filter.
4. **Rating** — Segmented-style: All / Solid+ / Must-See
5. **Time Period** — Segmented-style: Last Month / Last Year / All Time
6. **Want to Go** — Toggle switch to show/hide WTG pins

**Bottom toolbar:**
- "Reset" button — clears all filters to defaults
- Active filter count badge on the filter toolbar button

### 8.2 Filter Badge (Toolbar)

The filter button in ExploreMapView's toolbar shows:
- Outline icon when no filters active
- Filled icon + count badge (terracotta circle with white number) when filters are active

### 8.3 Filter Application

Filters are applied reactively. `ExploreMapFilter` is `Equatable`, so any change triggers SwiftUI re-evaluation of `filteredPins` → `annotatedPins` → Map re-render. An `onChange(of: filter)` handler also checks if the current selection is still valid.

---

## 9. Friends Loved Carousel

`FriendsLovedCarousel.swift` — shown at the bottom when **no pin is selected** and there are friends-loved places.

### Layout
- Horizontal `ScrollView` with snap behavior
- Each card: place photo (48pt), place name, "{n} friends loved this" label, heart icon
- Tapping a card selects the corresponding unified pin on the map

### Data Source
`exploreMapService.friendsLovedPlaces()` — returns all `ExploreMapPlace` where `isFriendsLoved` is true.

---

## 10. Map Helpers

`MapHelpers.swift` contains:

### MapStyleOption

```swift
enum MapStyleOption: CaseIterable {
    case minimal    // .standard(pointsOfInterest: .excludingAll)
    case standard   // .standard()
    case hybrid     // .hybrid
    case imagery    // .imagery
}
```

Each case has `name: String`, `icon: String` (SF Symbol), and `style: MapStyle` properties.

Selectable from the toolbar menu (top-right ellipsis button).

### MKCoordinateRegion Extension

`init(coordinates: [CLLocationCoordinate2D])` — computes the bounding box for a set of coordinates with a 20% padding. Used by `fitAllPins()` on first load.

---

## 11. Navigation Architecture

```
ExploreMapView
├── Tap personal pin → UnifiedBottomCard (personal) → Tap → LogDetailView
├── Tap friends pin → UnifiedBottomCard (friends) → Tap friend review → FeedLogDetailView
│                                                   → Focus on friend → filter map
├── Tap combined pin → UnifiedBottomCard (combined) → Tap own log → LogDetailView
│                                                    → Tap friend review → FeedLogDetailView
├── Tap WTG pin → WantToGoBottomCard → Tap → PlacePreviewView → "Log It" → RatePlaceView
├── Tap Friends Loved card → selects unified pin → shows UnifiedBottomCard
└── Filter button → ExploreFilterSheet (sheet)
```

**Navigation methods used:**
- `.navigationDestination(isPresented:)` — for `LogDetailView` (uses `showDetail` + `detailLogID` + `detailPlace`)
- `.navigationDestination(item:)` — for `FeedLogDetailView` (via `selectedFeedItem`) and `PlacePreviewView` (via `selectedPlaceDetails`)
- `.fullScreenCover(item:)` — for `RatePlaceView` (via `placeToLog`)
- `.sheet(isPresented:)` — for `ExploreFilterSheet`

---

## 12. Design System Usage

### Colors
| Usage | Token |
|-------|-------|
| Card backgrounds | `SonderColors.cream.opacity(0.95)` |
| Chip backgrounds (active) | `SonderColors.terracotta` |
| Chip backgrounds (inactive) | `SonderColors.warmGray.opacity(0.9)` |
| Chip text (active) | `.white` |
| Chip text (inactive) | `SonderColors.inkMuted` |
| Pin ring: must-see | `SonderColors.terracotta` |
| Pin ring: solid | `SonderColors.sage` |
| Pin ring: skip | `SonderColors.inkLight` |
| Want to Go pin | `SonderColors.wantToGoPin` |
| Friends loved badge | `SonderColors.terracotta` |
| Loading overlay | `SonderColors.terracotta` tint |
| Filter badge | White text on `SonderColors.terracotta` circle |

### Typography
| Usage | Token |
|-------|-------|
| Place names | `SonderTypography.headline` |
| Captions, addresses | `SonderTypography.caption` |
| Chip labels | `.system(size: 13, weight: .medium, design: .rounded)` |

### Spacing
| Usage | Token |
|-------|-------|
| Card padding | `SonderSpacing.md` |
| Chip spacing | `SonderSpacing.xs` |
| Card corners | `SonderSpacing.radiusLg` |
| Pin corners | `SonderSpacing.radiusSm` |

### Shadows
- Card shadow: `.black.opacity(0.08), radius: 8, y: 2`
- Chip shadow: `.black.opacity(0.08), radius: 4, y: 2`

---

## 13. Supabase Schema & Queries

### Tables Used

#### `follows`
```sql
follower_id TEXT  -- user who follows
following_id TEXT -- user being followed
```

#### `logs` (joined with `users` and `places`)
```sql
id TEXT PRIMARY KEY
user_id TEXT REFERENCES users(id)
place_id TEXT REFERENCES places(id)
rating TEXT        -- 'skip' | 'solid' | 'must_see'
photo_url TEXT
note TEXT
tags TEXT[]
created_at TIMESTAMPTZ
```

#### `places`
```sql
id TEXT PRIMARY KEY          -- Google Place ID
name TEXT
address TEXT
lat DOUBLE PRECISION
lng DOUBLE PRECISION
photo_reference TEXT         -- Google Places photo reference
```

### Query: Load Friends' Places

```sql
SELECT
    id, rating, photo_url, note, tags, created_at,
    users!logs_user_id_fkey(id, username, avatar_url, is_public),
    places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference)
FROM logs
WHERE user_id IN ({followingIDs})
ORDER BY created_at DESC
LIMIT 500
```

### Query: Get Following IDs

```sql
SELECT following_id FROM follows WHERE follower_id = {currentUserID}
```

---

## 14. Known Limitations & Future Work

### Current Limitations
1. **No pin clustering** — dense areas (e.g., downtown in a well-traveled city) can have overlapping pins that are hard to tap.
2. **Category filtering is keyword-based** — relies on place name matching rather than Google Place types, which can miss or misclassify places.
3. **500-log cap on friends' data** — users following many active friends may not see all data.
4. **No real-time updates** — friends' places are loaded once on appear and when `wantToGoService.items.count` changes. No Supabase realtime subscription.
5. **Photo prefetching is viewport-based** — photos for pins outside the current view aren't prefetched, causing a flash when scrolling to new areas.
6. **No offline support** — friends' data requires network; personal pins work offline via SwiftData.

### Future Improvements
- [ ] Pin clustering for dense areas (MapKit's native clustering or custom)
- [ ] Use Google Place types for category filtering instead of keyword matching
- [ ] Supabase realtime subscription for friends' new logs
- [ ] Paginated loading of friends' data beyond 500 logs
- [ ] Map search (search for a place and fly to it)
- [ ] "Nearby" discovery mode showing pins within walking distance
- [ ] Share a pin or place via deep link
