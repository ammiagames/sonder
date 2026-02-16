# Feed Page — Complete Technical & Design Specification

> This document captures every detail of the Feed feature as of Feb 2026. It is intended to give a developer or LLM full context to modify, extend, or rebuild the feed without prior knowledge of the codebase.

---

## Table of Contents

1. [Purpose & Design Philosophy](#1-purpose--design-philosophy)
2. [File Map](#2-file-map)
3. [Data Models](#3-data-models)
4. [FeedService (Backend Integration)](#4-feedservice-backend-integration)
5. [FeedView (Main Screen)](#5-feedview-main-screen)
6. [FeedItemCard (Log Cards)](#6-feeditemcard-log-cards)
7. [TripFeedCard (Trip Cards)](#7-tripfeedcard-trip-cards)
8. [FeedLogDetailView (Log Detail)](#8-feedlogdetailview-log-detail)
9. [Supporting Components](#9-supporting-components)
10. [Navigation Architecture](#10-navigation-architecture)
11. [Design System Usage](#11-design-system-usage)
12. [Supabase Schema & Queries](#12-supabase-schema--queries)
13. [Known Limitations & Future Work](#13-known-limitations--future-work)

---

## 1. Purpose & Design Philosophy

The Feed shows **logs and trips from people the current user follows**. It is the social discovery surface of Sonder.

### Design Principles (from `sonder_ui_ux.md`)
- **"Warm Journal" vibe** — cozy, nostalgic, intimate. Not performative or algorithmic.
- **No vanity metrics** — no like counts, no follower leaderboards.
- **Friend recommendations feel like whispered secrets** — "@username" attribution builds trust.
- **Warm over cold** — soft colors, rounded corners, gentle shadows. No stark whites or blacks.
- **Celebrate the places, not the poster.**

### What the Feed Does NOT Have
- Likes / reactions / comments
- Algorithmic ranking (pure reverse chronological)
- Infinite scroll with aggressive pagination (capped at 100 items in memory)
- Public discovery — only shows content from followed users

---

## 2. File Map

```
sonder/
├── Models/
│   └── FeedItem.swift              # All feed DTOs: FeedItem, FeedTripItem, FeedEntry, response types
├── Services/
│   └── FeedService.swift           # Feed loading, pagination, realtime subscriptions
├── Views/
│   └── Feed/
│       ├── FeedView.swift          # Main feed screen + FeedLogDetailView + FeedTripDestination
│       ├── FeedItemCard.swift       # Card component for individual log entries
│       └── TripFeedCard.swift       # Card component for trip entries
```

### Dependencies (other files the feed relies on)
- `Services/SocialService.swift` — follow relationships, user search
- `Services/WantToGoService.swift` — bookmark/save places
- `Models/Follow.swift` — SwiftData model for follow relationships
- `Models/WantToGo.swift` — SwiftData model for saved places
- `Views/Social/UserSearchView.swift` — "Find Friends" sheet
- `Views/Profile/OtherUserProfileView.swift` — user profile navigation target
- `Views/Components/WantToGoButton.swift` — bookmark toggle button
- `Views/Components/DownsampledAsyncImage.swift` — performant image loading
- `Theme/SonderTheme.swift` — `SonderColors`, `SonderTypography`, `SonderSpacing`, `SonderShadows`
- `Config/GooglePlacesConfig.swift` — `GooglePlacesService.photoURL(for:maxWidth:)` for place photos

---

## 3. Data Models

All defined in `Models/FeedItem.swift`. These are **not** SwiftData models — they are plain Codable DTOs assembled from joined Supabase queries.

### FeedItem (Single Log)
```swift
struct FeedItem: Identifiable, Codable, Hashable {
    let id: String          // Same as the log ID
    let log: FeedLog
    let user: FeedUser
    let place: FeedPlace
}
```

Convenience extensions:
- `var rating: Rating` — converts `log.rating` string to `Rating` enum (fallback: `.solid`)
- `var createdAt: Date` — shorthand for `log.createdAt`
- Conforms to `Hashable` (by `id`) for SwiftUI navigation

### FeedLog
```swift
struct FeedLog: Codable {
    let id: String
    let rating: String          // "must_see", "solid", or "skip"
    let photoURL: String?       // User's uploaded photo (Supabase Storage URL)
    let note: String?           // User's text note
    let tags: [String]          // e.g. ["coffee", "date night"]
    let createdAt: Date
}
```
CodingKeys: `photo_url`, `created_at`

### FeedUser
```swift
struct FeedUser: Codable {
    let id: String
    let username: String
    let avatarURL: String?      // Profile photo URL
    let isPublic: Bool          // Whether profile is publicly visible
}
```
CodingKeys: `avatar_url`, `is_public`

### FeedPlace
```swift
struct FeedPlace: Codable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let photoReference: String? // Google Places photo reference (NOT a URL — needs GooglePlacesService.photoURL())
}
```
CodingKeys: `lat`, `lng`, `photo_reference`

### FeedTripItem (Trip Card)
```swift
struct FeedTripItem: Identifiable {
    let id: String
    let name: String
    let coverPhotoURL: String?
    let startDate: Date?
    let endDate: Date?
    let user: FeedItem.FeedUser
    let logs: [LogSummary]          // Up to all logs in the trip
    let latestActivityAt: Date      // Most recent log's createdAt

    struct LogSummary: Identifiable {
        let id: String
        let photoURL: String?
        let rating: String
        let placeName: String
        let placePhotoReference: String?
        let createdAt: Date
    }

    var dateRangeDisplay: String?   // Computed: "MMM d – MMM d" or "From MMM d" or nil
}
```

### FeedEntry (Unified Feed Type)
```swift
enum FeedEntry: Identifiable {
    case trip(FeedTripItem)
    case log(FeedItem)

    var id: String          // "trip-{id}" or "log-{id}"
    var sortDate: Date      // For chronological sorting
}
```

### Supabase Response Types

**FeedLogResponse** — raw response from logs query with joins:
- All fields from `FeedLog` plus `tripID: String?`
- `user` (key: `"users"`) and `place` (key: `"places"`) from foreign key joins
- Has `toFeedItem() -> FeedItem` conversion method

**FeedTripResponse** — raw response from trips query:
- `id`, `name`, `coverPhotoURL`, `startDate`, `endDate`, `createdBy`
- `user` (key: `"users"`) from foreign key join

**TripLogWithTripID** — private struct for logs belonging to trips:
- `id`, `rating`, `photoURL`, `createdAt`, `tripID`, `place`

### Date.relativeDisplay Extension
Defined in `FeedItem.swift`. Returns human-readable relative time:
- `< 60s` → "Just now"
- `< 60m` → "Xm ago"
- `< 24h` → "Xh ago"
- `< 7d` → "Xd ago"
- `≥ 7d` → abbreviated date (e.g. "Feb 5, 2026")

---

## 4. FeedService (Backend Integration)

**File:** `Services/FeedService.swift`
**Class:** `@MainActor @Observable final class FeedService`

### Initialization
```swift
init(modelContext: ModelContext)
```
Also uses `SupabaseConfig.client` internally.

### State Properties
| Property | Type | Description |
|----------|------|-------------|
| `feedEntries` | `[FeedEntry]` | The current feed content (trips + logs mixed) |
| `isLoading` | `Bool` | Whether a fetch is in progress |
| `hasMore` | `Bool` | Whether more pages exist |
| `newPostsAvailable` | `Bool` | Set by realtime when new logs arrive |
| `lastFetchedDate` | `Date?` | Pagination cursor (private) |
| `pageSize` | `25` | Items per page (private) |
| `maxItemsInMemory` | `100` | Sliding window cap (private) |
| `realtimeChannel` | `RealtimeChannelV2?` | Supabase realtime connection (private) |

### Core Methods

#### `loadFeed(for currentUserID: String) async`
1. Guards against concurrent loading
2. Fetches `followingIDs` from `follows` table
3. If no following → sets empty feed, returns
4. Fetches logs via `fetchFeedLogs()` — **required** (throws on failure)
5. Fetches trips via `fetchTripFeedItems()` — **non-fatal** (catch → empty array)
6. Collects all log IDs that appear in trip cards (`tripLogIDs`)
7. Filters logs to only include standalone ones (no `tripID` or not in any trip card)
8. Merges standalone logs + trip entries, sorts by `sortDate` descending
9. Updates `feedEntries`, `lastFetchedDate`, `hasMore`

#### `loadMoreFeed(for currentUserID: String) async`
- Pagination using `lastFetchedDate` as cursor
- Only fetches more **logs** (trips are fully loaded on initial fetch)
- Filters out trip-associated logs
- Appends to `feedEntries`
- **Sliding window**: if count exceeds 100, removes oldest items from front

#### `refreshFeed(for currentUserID: String) async`
- Delegates to `loadFeed()` (full reload)

#### `fetchFeedLogs(followingIDs:before:) -> [FeedLogResponse]` (private)
Supabase query:
```sql
SELECT id, rating, photo_url, note, tags, created_at, trip_id,
       users!logs_user_id_fkey(id, username, avatar_url, is_public),
       places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference)
FROM logs
WHERE user_id IN (followingIDs)
  [AND created_at < cursor]   -- only for pagination
ORDER BY created_at DESC
LIMIT 25
```

#### `fetchTripFeedItems(followingIDs:) -> [FeedTripItem]` (private)
Two queries:
1. Fetch trips (up to 50) from followed users, ordered by `updated_at DESC`
2. Fetch all logs for those trip IDs
3. Group logs by `trip_id`, skip trips with 0 logs
4. Build `FeedTripItem` with `LogSummary` array

#### `getFollowingIDs(for:) -> [String]` (private)
```sql
SELECT following_id FROM follows WHERE follower_id = userID
```

#### Realtime

**`subscribeToRealtimeUpdates(for:) async`**
- Creates channel named `"feed-{currentUserID}"`
- Subscribes to `INSERT` events on the `logs` table
- When a new log arrives from a followed user → sets `newPostsAvailable = true`

**`unsubscribeFromRealtimeUpdates() async`**
- Removes the channel from Supabase client

**`showNewPosts(for:) async`**
- Clears `newPostsAvailable` flag
- Calls `loadFeed()` to refresh

#### Utility Methods

**`fetchFeedItem(logID:) -> FeedItem?`** — fetch a single log by ID with full joins
**`fetchUserLogs(userID:) -> [FeedItem]`** — fetch all logs from a specific user (used by `OtherUserProfileView`)

---

## 5. FeedView (Main Screen)

**File:** `Views/Feed/FeedView.swift`
**Struct:** `FeedView: View`

### Environment Dependencies
- `AuthenticationService` — current user ID
- `SyncEngine` — online status, syncing indicator
- `FeedService` — feed data and loading state
- `WantToGoService` — bookmark status
- `SocialService` — (injected but used by child views)

### State
- `showUserSearch: Bool` — toggles UserSearchView sheet
- `selectedUserID: String?` — navigation to OtherUserProfileView
- `selectedFeedItem: FeedItem?` — navigation to FeedLogDetailView
- `selectedTripID: String?` — navigation to FeedTripDestination

### Tab Bar Integration
```swift
// In MainTabView.swift
FeedView()
    .tabItem { Label("Feed", systemImage: "bubble.left.and.bubble.right") }
    .tag(0)
```
Note: `typealias SocialFeedView = FeedView` exists for backward compatibility.

### Layout Structure

```
NavigationStack
├── toolbar
│   ├── topBarLeading: ProgressView (if syncing/loading)
│   └── topBarTrailing: magnifyingglass button → showUserSearch
├── sheet: UserSearchView()
├── navigationDestination: OtherUserProfileView(userID:)
├── navigationDestination: FeedLogDetailView(feedItem:)
├── navigationDestination: FeedTripDestination(tripID:)
│
├── IF feedEntries.isEmpty && !isLoading:
│   └── ScrollView (refreshable)
│       └── emptyState
│
└── ELSE:
    └── feedContent (ScrollView, refreshable)
        ├── offlineBanner (if !syncEngine.isOnline)
        ├── newPostsBanner (if newPostsAvailable)
        ├── ForEach(feedEntries):
        │   ├── .trip → TripFeedCard
        │   └── .log → FeedItemCard
        └── ProgressView (if loading more)
```

### Empty State
- Icon: `person.2` (48pt, `inkLight`)
- Title: "No Posts Yet" (`SonderTypography.title`, `inkDark`)
- Subtitle: "Follow friends to see their logs here" (`body`, `inkMuted`)
- CTA: "Find Friends" button (terracotta capsule, white text)
- Top padding: `SonderSpacing.xxl`

### Offline Banner
- Icon: `wifi.slash` (16pt medium)
- Text: "You're offline. Changes will sync when connected."
- Background: `ochre` at 15% opacity
- Text color: `ochre`
- Corner radius: `radiusMd`

### New Posts Banner
- Icon: `arrow.up` (12pt semibold) + "New posts available" (caption, semibold)
- Background: `terracotta`, text: white
- Shape: Capsule with terracotta shadow (30% opacity, radius 8, y 4)
- Tapping calls `feedService.showNewPosts(for:)`

### Data Loading (`.task` modifier)
```swift
func loadInitialData() async {
    await feedService.loadFeed(for: userID)
    await wantToGoService.syncWantToGo(for: userID)
    await feedService.subscribeToRealtimeUpdates(for: userID)
}
```

### Want to Go Toggle
- Checks: `wantToGoService.isInWantToGo(placeID:userID:)`
- Toggles: `wantToGoService.toggleWantToGo(placeID:userID:placeName:placeAddress:photoReference:sourceLogID:)`
- Haptic: `UIImpactFeedbackGenerator(style: .light)`

---

## 6. FeedItemCard (Log Cards)

**File:** `Views/Feed/FeedItemCard.swift`
**Struct:** `FeedItemCard: View`

### Inputs
| Param | Type | Description |
|-------|------|-------------|
| `feedItem` | `FeedItem` | The log data |
| `isWantToGo` | `Bool` | Whether this place is bookmarked |
| `onUserTap` | `() -> Void` | Callback when user header is tapped |
| `onPlaceTap` | `() -> Void` | Callback when photo/card is tapped |
| `onWantToGoTap` | `() -> Void` | Callback when bookmark button is tapped |

### Card Layout (top to bottom, VStack spacing: 0)

#### 1. User Header
- Horizontal: avatar (36px circle) + username
- Avatar: `DownsampledAsyncImage` or gradient placeholder with first letter
- Avatar placeholder gradient: `terracotta(0.3)` → `ochre(0.2)`, topLeading→bottomTrailing
- Font: `SonderTypography.headline`, color: `inkDark`
- Padding: horizontal `md`, vertical `sm`
- Entire header is a `Button` calling `onUserTap`

#### 2. Photo Section (conditional — only if `hasPhoto`)
- `hasPhoto` = `log.photoURL != nil || place.photoReference != nil`
- Priority: user photo → Google Places photo → gradient placeholder
- Height: **220px**, full width, clipped
- Google Places URL: `GooglePlacesService.photoURL(for: ref, maxWidth: 600)`
- Gradient placeholder: same as avatar gradient with `photo` SF Symbol (largeTitle, terracotta 50%)
- Entire photo is a `Button` calling `onPlaceTap`

#### 3. Content Section
- **Place name**: `SonderTypography.headline`, `inkDark`, 2-line limit
- **Address**: `SonderTypography.caption`, `inkMuted`, 1-line limit
- **Rating emoji**: `.title2` font, right-aligned in HStack
- **Note** (if present): `SonderTypography.body`, `inkMuted`, 3-line limit
- **Tags** (if present): horizontal ScrollView of capsule chips
  - Font: `SonderTypography.caption`, color: `terracotta`
  - Background: `terracotta` at 10% opacity
  - Padding: horizontal `xs`, vertical 4px
  - Spacing between chips: `xxs`
- Padding: horizontal `md`, top `md`

#### 4. Footer Section
- Left: relative time (`SonderTypography.caption`, `inkLight`)
- Right: bookmark button (`bookmark` or `bookmark.fill`, 18pt)
  - Color: `terracotta` if saved, `inkLight` if not
- Padding: horizontal `md`, vertical `md`

### Card Styling
- Background: `SonderColors.warmGray`
- Corner radius: `SonderSpacing.radiusLg` (16px)
- Shadow: `SonderShadows.soft` (black 8% opacity, radius 8, y 4)

---

## 7. TripFeedCard (Trip Cards)

**File:** `Views/Feed/TripFeedCard.swift`
**Struct:** `TripFeedCard: View`

### Inputs
| Param | Type | Description |
|-------|------|-------------|
| `tripItem` | `FeedTripItem` | The trip data with log summaries |
| `onUserTap` | `() -> Void` | Callback when user header is tapped |
| `onTripTap` | `() -> Void` | Callback when card is tapped |

### Card Layout (top to bottom, VStack spacing: 0)

#### 1. User Header
- Same as FeedItemCard but with subtitle "trip" under username
- Subtitle: `SonderTypography.caption`, `inkMuted`

#### 2. Hero Image (220px height)
- Priority chain: trip cover photo → first log's user photo → first log's place photo → gradient placeholder
- Gradient placeholder: same terracotta/ochre gradient with `suitcase` SF Symbol

#### 3. Thumbnail Grid (conditional — only if >1 log)
- Shows up to **4** log thumbnails
- Height: **72px** each, equal width via `maxWidth: .infinity`
- Spacing: **2px** between thumbnails
- Each thumbnail priority: user photo → place photo → small gradient placeholder
- Small gradient placeholder has `mappin` SF Symbol (caption, terracotta 40%)

#### 4. Content Section
- **Trip name**: `SonderTypography.headline`, `inkDark`, 2-line limit
- **Date range** (if available): calendar icon + "MMM d – MMM d" label
- **Log count**: list.bullet icon + "X logs" label
- Both labels: `SonderTypography.caption`, `inkMuted`
- Padding: horizontal `md`, top `md`

#### 5. Footer Section
- Left only: relative time of latest activity
- `SonderTypography.caption`, `inkLight`
- Padding: horizontal `md`, vertical `md`

### Card Styling
- Same as FeedItemCard (warmGray, radiusLg, soft shadow)
- **Entire card is tappable** via `.onTapGesture(perform: onTripTap)`

---

## 8. FeedLogDetailView (Log Detail)

**File:** `Views/Feed/FeedView.swift` (defined in same file as FeedView)
**Struct:** `FeedLogDetailView: View`

This is a **read-only** detail view for viewing a friend's log. (The user's own logs use `LogDetailView` which has edit/delete capabilities.)

### Input
- `feedItem: FeedItem`

### Layout (ScrollView, VStack spacing: 0)

#### Photo Section (250px height)
- Priority: user photo → Google Places photo → gradient placeholder
- Same placeholder styling as FeedItemCard

#### Content Sections (VStack spacing: `lg`, padding: `lg`)
Each section separated by a 1px `warmGray` divider.

1. **Place Section**: mappin icon + address (`caption`, `inkMuted`)
2. **Rating Section**: "Rating" label + emoji + display name (e.g. "Must See")
3. **Note Section** (conditional): "Note" label + full text
4. **Tags Section** (conditional): "Tags" label + `FlowLayoutTags` component
5. **Meta Section**:
   - "Logged by" + tappable `@username` (NavigationLink → OtherUserProfileView)
   - "Date" + long-format date

### Toolbar
- `topBarTrailing`: `WantToGoButton` (bookmark toggle)

### Navigation
- Title: place name (inline display mode)

---

## 9. Supporting Components

### FeedTripDestination
**File:** `Views/Feed/FeedView.swift`
Bridges `tripID: String` to `TripDetailView(trip:)` by fetching the Trip from SwiftData:
```swift
let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })
trip = try? modelContext.fetch(descriptor).first
```
Shows a `ProgressView` while loading.

### WantToGoButton
**File:** `Views/Components/WantToGoButton.swift`
- Small version: icon-only bookmark toggle (20pt)
- Large version (`WantToGoButtonLarge`): full-width button with "Want to Go" / "Saved" label
- Both use `WantToGoService.toggleWantToGo()` with haptic feedback
- Loading state shows `ProgressView`

### UserSearchView
**File:** `Views/Social/UserSearchView.swift`
- Presented as a sheet from the feed's toolbar search button
- Search bar + results list
- Uses `SocialService.searchUsers(query:)` with case-insensitive partial matching
- Navigates to `OtherUserProfileView` on user selection

### DownsampledAsyncImage
**File:** `Views/Components/DownsampledAsyncImage.swift`
```swift
DownsampledAsyncImage(
    url: URL?,
    targetSize: CGSize,
    contentMode: ContentMode = .fill,  // optional
    @ViewBuilder placeholder: () -> Placeholder
)
```
Convenience init without placeholder (uses `Color` as placeholder type).

### FlowLayoutTags
Used in `FeedLogDetailView` for tag display. Defined elsewhere in the codebase (referenced from `MainTabView.swift` and `LogDetailView.swift`).

---

## 10. Navigation Architecture

```
FeedView (NavigationStack)
│
├── sheet: UserSearchView
│   └── navigationDestination: OtherUserProfileView
│
├── navigationDestination($selectedUserID): OtherUserProfileView
│   └── (has its own navigation for logs → FeedLogDetailView)
│
├── navigationDestination($selectedFeedItem): FeedLogDetailView
│   └── toolbar: WantToGoButton
│   └── NavigationLink: OtherUserProfileView (from "Logged by" section)
│
└── navigationDestination($selectedTripID): FeedTripDestination
    └── TripDetailView (full trip detail with all logs)
```

### Navigation Triggers
| User Action | State Change | Destination |
|-------------|-------------|-------------|
| Tap user avatar/name on any card | `selectedUserID = user.id` | OtherUserProfileView |
| Tap photo/card on log card | `selectedFeedItem = feedItem` | FeedLogDetailView |
| Tap anywhere on trip card | `selectedTripID = tripItem.id` | FeedTripDestination → TripDetailView |
| Tap search icon in toolbar | `showUserSearch = true` | UserSearchView (sheet) |
| Tap "Find Friends" in empty state | `showUserSearch = true` | UserSearchView (sheet) |

---

## 11. Design System Usage

### Colors
| Usage | Token |
|-------|-------|
| Page background | `SonderColors.cream` |
| Card background | `SonderColors.warmGray` |
| Primary text | `SonderColors.inkDark` |
| Secondary text | `SonderColors.inkMuted` |
| Tertiary text (dates, timestamps) | `SonderColors.inkLight` |
| Accent / interactive | `SonderColors.terracotta` |
| Tag background | `SonderColors.terracotta` at 10% opacity |
| Offline banner background | `SonderColors.ochre` at 15% opacity |
| Avatar placeholder gradient | `terracotta(0.3)` → `ochre(0.2)` |
| Photo placeholder gradient | Same as avatar |

### Typography
| Usage | Token |
|-------|-------|
| Card place name | `SonderTypography.headline` |
| Body text / notes | `SonderTypography.body` |
| Labels, addresses, timestamps | `SonderTypography.caption` |
| Empty state title | `SonderTypography.title` |
| Username in header | `SonderTypography.headline` |

### Spacing
| Usage | Token | Value |
|-------|-------|-------|
| Card padding | `SonderSpacing.md` | 16px |
| Inner element spacing | `SonderSpacing.xs` / `sm` | 8px / 12px |
| Section padding | `SonderSpacing.lg` | 20px |
| Card corner radius | `SonderSpacing.radiusLg` | 16px |
| Inner corner radius | `SonderSpacing.radiusMd` | 12px |

### Shadows
All cards use: `SonderShadows.soft` — black 8% opacity, radius 8, y-offset 4

### Sizing Constants
| Element | Size |
|---------|------|
| Avatar | 36 × 36 px |
| Card photo height | 220px |
| Detail photo height | 250px |
| Thumbnail grid height | 72px |
| Thumbnail spacing | 2px |
| Bookmark icon | 18pt (card), 20pt (detail) |
| Max thumbnails in trip card | 4 |

---

## 12. Supabase Schema & Queries

### Tables Referenced

**`logs`** — user place logs
- `id`, `user_id`, `place_id`, `rating`, `photo_url`, `note`, `tags`, `trip_id`, `created_at`
- Foreign keys: `logs_user_id_fkey` → `users`, `logs_place_id_fkey` → `places`

**`users`** — user profiles
- `id`, `username`, `avatar_url`, `is_public`

**`places`** — cached place data
- `id`, `name`, `address`, `lat`, `lng`, `photo_reference`

**`trips`** — user trips
- `id`, `name`, `cover_photo_url`, `start_date`, `end_date`, `created_by`, `updated_at`
- Foreign key: `trips_created_by_fkey` → `users`

**`follows`** — follow relationships
- `follower_id`, `following_id`

### Key Queries

**Feed logs** (with joins):
```
logs.select("id, rating, photo_url, note, tags, created_at, trip_id,
    users!logs_user_id_fkey(id, username, avatar_url, is_public),
    places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference)")
.in("user_id", followingIDs)
.order("created_at", ascending: false)
.limit(25)
```

**Feed trips** (with user join):
```
trips.select("id, name, cover_photo_url, start_date, end_date, created_by,
    users!trips_created_by_fkey(id, username, avatar_url, is_public)")
.in("created_by", followingIDs)
.order("updated_at", ascending: false)
.limit(50)
```

**Trip logs** (with place join):
```
logs.select("id, rating, photo_url, created_at, trip_id,
    places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference)")
.in("trip_id", tripIDs)
.order("created_at", ascending: false)
```

**Following IDs:**
```
follows.select("following_id").eq("follower_id", userID)
```

### Realtime Subscription
- Channel name: `"feed-{currentUserID}"`
- Event: `INSERT` on `logs` table (public schema)
- Filters: client-side check that `user_id` is in `followingIDs`
- Action: sets `newPostsAvailable = true`

---

## 13. Known Limitations & Future Work

### Current Limitations
1. **No pagination trigger in UI** — `loadMoreFeed()` exists but is never called from `FeedView`. Would need an `onAppear` trigger on the last item or a "Load More" button.
2. **Trips are not paginated** — all trips (up to 50) are loaded at once on initial fetch.
3. **No offline feed** — feed data is not cached locally in SwiftData. If offline, feed is empty.
4. **Realtime only detects new logs** — new trips, trip edits, or log edits don't trigger the banner.
5. **No comment/reaction system** — by design (aligns with "not performative" philosophy).
6. **FlowLayoutTags** component is defined outside the Feed directory and shared with LogDetailView.
7. **Google Places photos require API key** — `GooglePlacesService.photoURL(for:maxWidth:)` constructs a URL using the key in `GooglePlacesConfig.swift`. This is a REST API call, not the native SDK.

### Potential Improvements
- Add pagination trigger (infinite scroll or explicit "Load More")
- Cache feed items in SwiftData for offline viewing
- Add realtime subscription for trip updates
- Add pull-to-refresh animation feedback
- Consider "Want to Go" count on places (social proof without vanity metrics)
