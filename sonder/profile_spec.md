# Profile Page — Complete Technical & Design Specification

> This document captures every detail of the Profile feature as of Feb 2026. It is intended to give a developer or LLM full context to modify, extend, or rebuild the profile without prior knowledge of the codebase.

---

## Table of Contents

1. [Purpose & Design Philosophy](#1-purpose--design-philosophy)
2. [File Map](#2-file-map)
3. [Data Models](#3-data-models)
4. [ProfileView (Main Screen)](#4-profileview-main-screen)
5. [Profile Header](#5-profile-header)
6. [Social Stats Section](#6-social-stats-section)
7. [Want to Go Link](#7-want-to-go-link)
8. [Hero Stat Section](#8-hero-stat-section)
9. [Rating Breakdown Section](#9-rating-breakdown-section)
10. [You Love Section](#10-you-love-section)
11. [Recent Activity Section](#11-recent-activity-section)
12. [Top Cities Photo Mosaic](#12-top-cities-photo-mosaic)
13. [View My Map Banner](#13-view-my-map-banner)
14. [EditProfileView](#14-editprofileview)
15. [ShareProfileCardView](#15-shareprofilecardview)
16. [OtherUserProfileView](#16-otheruserprofileview)
17. [OtherUserMapView](#17-otherusermapview)
18. [WantToGoListView](#18-wanttogolistview)
19. [FollowListView](#19-followlistview)
20. [SettingsView](#20-settingsview)
21. [Navigation Architecture](#21-navigation-architecture)
22. [Design System Usage](#22-design-system-usage)
23. [Supabase Schema & Queries](#23-supabase-schema--queries)
24. [Known Limitations & Future Work](#24-known-limitations--future-work)

---

## 1. Purpose & Design Philosophy

The Profile is **Tab 4** (index 3) in Sonder. It is the user's personal dashboard — a visual summary of their travel journey with stats, top cities, recent activity, and social connections.

### Design Principles
- **Personal celebration** — the profile celebrates the user's journey, not vanity metrics. Focus on places explored, not follower counts.
- **Warm journal aesthetic** — cream backgrounds, warmGray cards, terracotta accents. All sections are rounded cards on cream.
- **At-a-glance stats** — hero stat, rating breakdown bar, top cities mosaic give instant visual summary.
- **Social but not performative** — followers/following are present but not prominent. No like counts or engagement metrics.

### What the Profile Does NOT Have
- Public/private toggle (all profiles are public)
- Activity feed of own posts
- Achievement badges or gamification
- Profile cover/banner image (only avatar)

---

## 2. File Map

```
sonder/
├── Services/
│   └── ProfileStatsService.swift          # Computed stats: cities, countries, heatmap, taste DNA, rating breakdown
├── Models/
│   └── ProfileStats.swift                 # ProfileStats model for computed stat values
├── Views/
│   ├── Main/
│   │   └── MainTabView.swift              # Contains ProfileView, SettingsView, LogsView,
│   │                                      # FilteredLogsListView, LogRow, FilterChip,
│   │                                      # JourneyStatCard, WarmFlowLayoutTags, StatCard
│   ├── Profile/
│   │   ├── ProfileView.swift              # Main profile page (own profile)
│   │   ├── EditProfileView.swift          # Edit username, bio, avatar
│   │   ├── ShareProfileCardView.swift     # Generate & share profile card image
│   │   ├── TasteDNARadarChart.swift       # Radar chart for category taste profile
│   │   ├── OtherUserProfileView.swift     # View another user's profile (read-only)
│   │   ├── OtherUserMapView.swift         # View another user's logged places on a map
│   │   └── OtherUserCityLogsView.swift    # City logs for another user's profile
│   ├── WantToGo/
│   │   └── WantToGoListView.swift         # Want to Go list with Recent/City grouping
│   └── Social/
│       └── FollowListView.swift           # Followers/following list with tabs
```

**Note**: `ProfileView` and `SettingsView` are defined inside `MainTabView.swift` (not in separate files). This is a known tech debt item.

---

## 3. Data Models

### 3.1 User (SwiftData `@Model`)

```swift
@Model class User {
    var id: String                    // Supabase auth UUID
    var username: String
    var email: String?
    var bio: String?
    var avatarURL: String?            // Supabase Storage URL
    var isPublic: Bool
    var createdAt: Date
    var updatedAt: Date
}
```

### 3.2 Log, Place, Trip

See `journal_spec.md` for full definitions. The profile uses these to compute stats:
- `Log.userID` — filter to current user
- `Log.rating` — rating breakdown
- `Log.tags` — "You love" section
- `Log.placeID` → `Place.address` — city extraction
- `Log.photoURL` — city photo priority

### 3.3 WantToGoWithPlace

Used by `WantToGoListView`:

```swift
struct WantToGoWithPlace: Identifiable {
    let id: String
    let placeID: String
    let createdAt: Date
    let place: WantToGoPlace           // name, address, photoReference
    let sourceUser: WantToGoSourceUser? // username of who recommended it
}
```

### 3.4 FeedItem

Used by `OtherUserProfileView` and `OtherUserMapView` to display another user's logs. See `feed_spec.md` for full definition.

---

## 4. ProfileView (Main Screen)

`ProfileView` is defined in `MainTabView.swift` (~line 514). It is the root view for Tab 4.

### 4.1 Environment & Queries

```swift
@Environment(AuthenticationService.self) private var authService
@Environment(SyncEngine.self) private var syncEngine
@Environment(SocialService.self) private var socialService
@Environment(WantToGoService.self) private var wantToGoService
@Query private var allLogs: [Log]
@Query private var places: [Place]
```

### 4.2 Bindings (from MainTabView)

| Binding | Type | Purpose |
|---------|------|---------|
| `selectedTab` | `Binding<Int>` | Switch to other tabs (Journal, Explore) |
| `exploreFocusMyPlaces` | `Binding<Bool>` | Trigger Explore tab focus on personal pins |

### 4.3 State

| State | Type | Purpose |
|-------|------|---------|
| `showSettings` | `Bool` | Present SettingsView sheet |
| `showEditProfile` | `Bool` | Present EditProfileView sheet |
| `showShareProfile` | `Bool` | Present ShareProfileCardView sheet |
| `wantToGoCount` | `Int` | Count for Want to Go link subtitle |

### 4.4 View Structure (top to bottom in ScrollView)

```
NavigationStack > ScrollView > VStack(spacing: lg)
├── profileHeader            — avatar, username, bio, member since, Edit/Share buttons
├── socialStatsSection       — followers / following counts (tappable)
├── wantToGoLink             — bookmark card linking to WantToGoListView
├── (if has logs):
│   ├── heroStatSection      — big number: total places logged
│   ├── ratingBreakdownSection — stacked bar chart + legend
│   ├── youLoveSection       — top tags as tappable chips (if tags exist)
│   └── recentActivitySection — 3 most recent logs
├── (if >1 city):
│   └── cityOption7_PhotoMosaic — hero + grid of top cities
└── viewMyMapBanner          — "Your Map" link to Explore tab
```

### 4.5 Toolbar & Actions

- **Settings gear** (topBarTrailing) → presents `SettingsView` as sheet
- **Pull-to-refresh** → `syncEngine.forceSyncNow()` + `socialService.refreshCounts(for:)`
- **`.task`** → loads social counts on appear

---

## 5. Profile Header

### 5.1 Avatar

- 100×100pt circle, clipped
- Photo source priority: `authService.currentUser?.avatarURL` → gradient placeholder with first initial
- Tappable → opens EditProfileView
- Camera badge (terracotta circle) shown in bottom-right when no avatar photo exists
- Shadow: `.black.opacity(0.1), radius: 8, y: 4`
- White cream border ring (4pt)

### 5.2 Avatar Placeholder

```swift
Circle()
    .fill(LinearGradient(
        colors: [SonderColors.terracotta.opacity(0.3), SonderColors.ochre.opacity(0.2)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    ))
    .overlay {
        Text(username.prefix(1).uppercased())  // First initial
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .foregroundColor(SonderColors.terracotta)
    }
```

### 5.3 Text Content

- **Username**: `SonderTypography.largeTitle`, inkDark
- **Bio**: `SonderTypography.body`, inkMuted, centered, horizontal padding lg
- **Member since**: `SonderTypography.caption`, inkLight — "Journaling since {date}"

### 5.4 Action Buttons

Two capsule buttons side by side:
- **"Edit Profile"** (pencil icon): warmGray background, inkDark text → opens EditProfileView
- **"Share"** (share icon): terracotta.opacity(0.12) background, terracotta text → opens ShareProfileCardView

---

## 6. Social Stats Section

Horizontal layout with followers and following counts, separated by a dot divider.

```
HStack(spacing: xxl)
├── NavigationLink → FollowListView(.followers)
│   ├── Count (title font, or ProgressView if not loaded)
│   └── "Followers" label (caption)
├── Circle divider (4pt, inkLight)
└── NavigationLink → FollowListView(.following)
    ├── Count (title font, or ProgressView if not loaded)
    └── "Following" label (caption)
```

Counts come from `socialService.followerCount` / `socialService.followingCount`, loaded via `socialService.refreshCounts(for:)`.

---

## 7. Want to Go Link

A card-style NavigationLink to `WantToGoListView`:

```
HStack (warmGray background, radiusLg corners)
├── Bookmark icon (terracotta, on terracotta.opacity(0.15) square)
├── VStack
│   ├── "Want to Go" (headline)
│   └── "{count} saved" or "Save places to visit later" (caption)
└── Chevron
```

Count loaded via `wantToGoService.fetchWantToGoWithPlaces(for:)` in `.task`.

---

## 8. Hero Stat Section

Large centered stat card (warmGray background, radiusLg):

```
VStack
├── Log count (48pt, bold, serif) — e.g., "47"
├── "places logged" (headline, inkMuted)
├── "across {n} cities in {n} countries" (caption, inkLight) — only if >1
└── "{n} places this month" (terracotta pill) — momentum indicator, only if >0
```

### Computed Properties

- `logs` — `allLogs.filter { $0.userID == currentUser.id }`
- `userPlaces` — places that the user has logged (deduplicated by placeID)
- `uniqueCities` — extracted from place addresses
- `uniqueCountries` — extracted from place addresses
- `logsThisMonth` — logs where `createdAt` is in current calendar month

### City/Country Extraction

```swift
func extractCity(from address: String) -> String?
// Parses comma-separated address components
// City is typically 3rd-from-last component
// Falls back to first component for 2-component addresses

func extractCountry(from address: String) -> String?
// Last component of address, skipping zip codes and state abbreviations
```

---

## 9. Rating Breakdown Section

Visual breakdown of the user's ratings (warmGray card):

### Stacked Bar Chart

Horizontal `GeometryReader`-based bar with three segments:
- **Must-See** (`SonderColors.ratingMustSee`) — proportional width
- **Solid** (`SonderColors.ratingSolid`) — proportional width
- **Skip** (`SonderColors.ratingSkip`) — proportional width
- Each segment: minimum 8pt width, 12pt height, 4pt corner radius, 2pt spacing

### Legend Row

Three items: `{emoji} {count} {label}` for Must-See, Solid, Skip.

Section header: "YOUR RATINGS" (uppercase, tracked caption, inkMuted).

---

## 10. You Love Section

Shows top 6 most-used tags as tappable chips (warmGray card):

```
VStack
├── "YOU LOVE" header
└── FlowLayoutWrapper
    └── ForEach(topTags) → NavigationLink → FilteredLogsListView(title: tag, logs: logsForTag)
        └── Capsule chip: tag text + chevron (terracotta text, terracotta.opacity(0.12) bg)
```

- Only shown when `topTags` is non-empty
- Tags sorted by frequency (most used first), limited to 6
- Tapping a tag navigates to `FilteredLogsListView` showing all logs with that tag

### FilteredLogsListView

Simple list view (defined in MainTabView.swift ~line 1393):
- Navigation title = tag name
- Each row: rating emoji (36×36 colored square) + place name + address + date
- `warmGray` row background, cream page background

---

## 11. Recent Activity Section

Shows 3 most recent logs (warmGray card):

```
VStack
├── "RECENT ACTIVITY" header
├── ForEach(recentLogs) → NavigationLink → LogDetailView
│   ├── Rating emoji (36×36 colored square)
│   ├── Place name + relative date ("Today", "Yesterday", etc.)
│   └── Chevron
│   └── Divider (between items)
└── (if >3 logs): "See all {n} logs" button → switches to Journal tab (selectedTab = 2)
```

Relative date uses `log.createdAt.relativeDisplay` (a Date extension).

---

## 12. Top Cities Photo Mosaic

Shows top 5 cities by log count (warmGray card). Only displayed when `uniqueCities.count > 1`.

### Layout

```
VStack
├── "YOUR TOP CITIES" header
├── Hero card (top city) — full-width, 160pt height
│   ├── City photo or gradient fallback
│   ├── Gradient scrim (center → bottom, 65% black)
│   └── City name (22pt, bold, serif, white) + "{n} places logged"
└── 2-column LazyVGrid (remaining cities, up to 4)
    └── Each: 100pt height, photo + gradient + city name (14pt, serif) + count
```

All city cards are `NavigationLink` → `CityLogsView(title: city, logs: logsForCity)`.

### City Photo Resolution (`cityPhotoURL`)

Priority order:
1. User's own log photo (most personal) — most recent log with a photo in that city
2. Google Places photo of the most-logged place in the city — via `GooglePlacesService.photoURL(for:maxWidth:)`

### Gradient Fallbacks

When no photo is available, a themed gradient is used. 5 gradient pairs rotate by index:
1. Terracotta → Ochre
2. WarmBlue → Sage
3. DustyRose → Terracotta
4. Sage → WarmBlue
5. Ochre → DustyRose

---

## 13. View My Map Banner

Bottom card linking to the Explore tab with personal pins focused:

```
HStack (warmGray background, radiusLg)
├── Map icon (terracotta, on terracotta.opacity(0.15) square)
├── VStack
│   ├── "Your Map" (headline)
│   └── "{n} places logged" or "Start logging places..." (caption)
└── Chevron (only if has logs)
```

**On tap**: Sets `exploreFocusMyPlaces = true` and `selectedTab = 1` (switches to Explore tab). Disabled when no logs.

---

## 14. EditProfileView

`EditProfileView.swift` — sheet for editing profile. (283 lines)

### Fields

| Field | Type | Constraints |
|-------|------|-------------|
| `username` | `String` | Required, trimmed, no autocorrect, no auto-capitalize |
| `bio` | `String` | Optional, 150 character max, 3-5 line limit |
| Avatar | `PhotosPickerItem` → `UIImage` | Via system PhotosPicker |

### Layout

```
NavigationStack > ScrollView > VStack(spacing: xl)
├── Avatar section
│   ├── PhotosPicker trigger (circle, 100×100)
│   │   ├── Selected local image
│   │   ├── Remote avatar URL
│   │   └── Gradient placeholder with initial
│   └── "Tap to change photo" caption
├── Username section
│   ├── "USERNAME" label
│   └── TextField (warmGray background, radiusMd)
└── Bio section
    ├── "BIO" label + character counter ({n}/150)
    ├── TextField (multiline, warmGray background)
    └── Helper text: "Tell others what you love to explore"
```

### Save Flow

1. Upload avatar via `photoService.uploadPhoto(image, for: userID)` if changed
2. Update `User` model properties (username, bio, avatarURL)
3. Save to local ModelContext
4. Sync to Supabase via direct `users` table update
5. Haptic feedback (`.success`)
6. Dismiss

### Supabase Sync

Direct `UPDATE users SET username, bio, avatar_url, updated_at WHERE id = {userID}` — does NOT go through SyncEngine, uses a dedicated `syncUserToSupabase()` method.

---

## 15. ShareProfileCardView

`ShareProfileCardView.swift` — generates a shareable profile card image. (223 lines)

### Inputs

| Parameter | Type |
|-----------|------|
| `placesCount` | `Int` |
| `citiesCount` | `Int` |
| `countriesCount` | `Int` |
| `topTags` | `[String]` |
| `mustSeeCount` | `Int` |

### Card Layout

```
VStack (cream bg, radiusXl, 1pt warmGray border, shadow)
├── "sonder" branding text (terracotta, rounded)
├── Avatar (60×60 circle) + username + bio
├── Stats: Places / Cities / Countries (warmGray boxes)
├── "🔥 {n} must-see places discovered" (if >0)
└── Top 4 tags as terracotta capsule chips
```

### Share Flow

1. Renders the card view to `UIImage` via `ImageRenderer` at 3× scale (high res)
2. Presents `UIActivityViewController` via `ShareSheet` (UIViewControllerRepresentable)
3. Image is shared directly (no text or URL attached)

---

## 16. OtherUserProfileView

`OtherUserProfileView.swift` — read-only view of another user's profile. (432 lines)

### Input

`userID: String` — the user whose profile to display.

### Data Loading (`.task`)

1. Fetch user via `socialService.getUser(id:)`
2. Check follow status via `socialService.isFollowingAsync(userID:currentUserID:)`
3. Load follower/following counts via `socialService.getFollowerCount/getFollowingCount`
4. Load user's logs via `feedService.fetchUserLogs(userID:)`

### Layout

```
ScrollView
├── Loading state (ProgressView)
├── User found:
│   ├── profileHeader — avatar (88×88), @username, bio, "Exploring since {date}"
│   ├── statsSection — Followers / Following / Places (horizontal bar)
│   ├── followButton — "Follow" (terracotta) or "Following" (warmGray, with checkmark)
│   ├── Divider
│   └── logsSection — "Places" header + count, LazyVStack of OtherUserLogRow
└── User not found: ContentUnavailableView
```

### Follow Button

- **Not following**: Terracotta background, white text, "Follow" with plus icon
- **Following**: warmGray background, inkDark text, "Following" with checkmark
- Toggle calls `socialService.followUser/unfollowUser`, updates local count, haptic feedback

### Toolbar

- Map icon (topBarTrailing) → navigates to `OtherUserMapView(userID:username:logs:)`

### OtherUserLogRow

Each log row in the profile:
```
HStack (warmGray bg, radiusMd)
├── Photo thumbnail (60×60) — user photo or place photo or gradient placeholder
├── VStack
│   ├── Place name + rating emoji
│   ├── Address
│   └── Date
```

Tapping → `FeedLogDetailView(feedItem:)`

---

## 17. OtherUserMapView

`OtherUserMapView.swift` — read-only map of another user's logged places. (177 lines)

### Inputs

| Parameter | Type |
|-----------|------|
| `userID` | `String` |
| `username` | `String` |
| `logs` | `[FeedItem]` |

### Features

- Full-screen `Map` with `Marker` for each log
- Marker icon varies by rating: star.fill (mustSee), thumbsup.fill (solid), thumbsdown.fill (skip)
- Marker color: `SonderColors.ratingMustSee/ratingSolid/ratingSkip`
- Selection shows a bottom card with place photo, name, address, note preview
- Tapping the card → `FeedLogDetailView(feedItem:)`
- On appear: fits camera to all log coordinates with 1.5× span padding

---

## 18. WantToGoListView

`WantToGoListView.swift` — list of saved Want to Go places. (527 lines)

### Grouping Modes

```swift
enum WantToGoGrouping: String, CaseIterable {
    case recent = "Recent"    // Reverse chronological
    case city = "City"        // Grouped by extracted city name
}
```

Toggle via chip buttons at the top of the list.

### Layout

```
Group
├── Loading: ProgressView
├── Empty: bookmark icon + "No Saved Places" + helper text
└── Items:
    ├── Grouping picker (Recent / City chips)
    ├── List content (recent or city-grouped)
    └── (City mode, >1 city): CitySectionIndex on trailing edge
```

### WantToGoRow

Each item row:
```
HStack
├── Place photo (60×60, rounded)
├── VStack
│   ├── Place name (headline)
│   ├── Address (caption)
│   └── "from @{username}" (terracotta, 11pt) + date
├── Bookmark.fill button (terracotta) — unbookmark
└── Chevron
```

- Swipe-to-delete (trailing) with animated removal
- Tap → fetches place details → `PlacePreviewView` → can "Log It" → `RatePlaceView`
- After logging: auto-removes from Want to Go list

### CitySectionIndex

Right-edge scrollable index (like iOS Contacts):
- Shows 3-letter abbreviation of each city
- Drag gesture to quick-scroll to a city section
- Highlighted city: currently-dragged or topmost visible section
- Sensory feedback on city change
- WarmGray background pill, terracotta highlight

### City Extraction

Same address-parsing logic as ProfileView but with "Unknown" fallback instead of nil.

---

## 19. FollowListView

`FollowListView.swift` — followers/following list with segmented picker. (190 lines)

### Inputs

| Parameter | Type | Description |
|-----------|------|-------------|
| `userID` | `String` | User whose connections to show |
| `username` | `String` | For display in navigation title and empty states |
| `initialTab` | `Tab` | `.followers` or `.following` |

### Layout

```
VStack
├── Segmented Picker (Followers / Following)
└── TabView (page style, no index)
    ├── Tab: followers list
    │   ├── Loading: ProgressView
    │   ├── Empty: "No Followers" + message
    │   └── List of UserSearchRow
    └── Tab: following list
        ├── Loading: ProgressView
        ├── Empty: "Not Following Anyone" + message
        └── List of UserSearchRow
```

- Each row uses `UserSearchRow` (from Social/UserSearchView.swift)
- Tapping a user → navigates to `OtherUserProfileView(userID:)` via `navigationDestination(item:)`
- Data loaded in parallel via `TaskGroup`

---

## 20. SettingsView

`SettingsView` is defined in `MainTabView.swift` (~line 1528). Presented as a sheet from ProfileView.

### Sections

| Section | Contents |
|---------|----------|
| **Account** | Username (read-only), Email (tappable to edit) |
| **Notifications** | "Nearby Place Alerts" toggle (ProximityNotificationService) |
| **Privacy** | Privacy Policy link, Terms of Service link |
| **Data** | "Clear Cache" button (clears RecentSearch records) |
| **About** | Version number, Build number |
| **Sign Out** | Centered destructive button |

### Styling

- Forced `.environment(\.colorScheme, .light)` — ensures warm appearance
- `warmGray` row backgrounds, cream page background
- Section headers: terracotta, uppercase, tracked caption
- Tint: terracotta

### Alerts

| Alert | Trigger | Actions |
|-------|---------|---------|
| Sign Out | "Sign Out" button | Cancel / Sign Out (destructive) |
| Clear Cache | "Clear Cache" button | Cancel / Clear (destructive) |
| Edit Email | Email row tap | TextField + Cancel / Save |

### Email Edit

- Updates `user.email` locally
- Saves to ModelContext
- Syncs via `syncEngine.syncNow()`

### Cache Clear

- Fetches all `RecentSearch` records from SwiftData
- Deletes each one
- Saves context
- Does NOT clear logs, places, or other data

---

## 21. Navigation Architecture

```
MainTabView (Tab 4: Profile)
└── ProfileView
    ├── Settings gear → SettingsView [sheet]
    │   ├── Email edit [alert]
    │   ├── Sign out [alert]
    │   └── Clear cache [alert]
    ├── Avatar tap → EditProfileView [sheet]
    ├── "Edit Profile" button → EditProfileView [sheet]
    ├── "Share" button → ShareProfileCardView [sheet]
    │   └── Share button → UIActivityViewController [sheet]
    ├── Followers count → FollowListView(.followers)
    │   └── Tap user → OtherUserProfileView
    │       ├── Follow/unfollow button
    │       ├── Map icon → OtherUserMapView
    │       │   └── Tap pin card → FeedLogDetailView
    │       ├── Tap log → FeedLogDetailView
    │       └── Followers/Following → FollowListView (recursive)
    ├── Following count → FollowListView(.following)
    │   └── (same as above)
    ├── Want to Go link → WantToGoListView
    │   ├── Tap item → PlacePreviewView → RatePlaceView [fullScreenCover]
    │   └── Swipe to remove
    ├── Tag chip → FilteredLogsListView
    │   └── Tap log → LogDetailView
    ├── Recent log → LogDetailView
    ├── "See all logs" → switches to Journal tab (selectedTab = 2)
    ├── City card → CityLogsView
    │   ├── Tap trip header → TripDetailView
    │   └── Tap log → LogDetailView
    └── "Your Map" banner → switches to Explore tab (selectedTab = 1) with focusMyPlaces
```

---

## 22. Design System Usage

### Colors

| Usage | Token |
|-------|-------|
| Page background | `SonderColors.cream` |
| Card/section backgrounds | `SonderColors.warmGray` |
| Primary accent | `SonderColors.terracotta` |
| Text (primary) | `SonderColors.inkDark` |
| Text (secondary) | `SonderColors.inkMuted` |
| Text (tertiary) | `SonderColors.inkLight` |
| Avatar placeholder gradient | Terracotta 0.3 → Ochre 0.2 |
| Edit Profile button bg | `SonderColors.warmGray` |
| Share button bg | `SonderColors.terracotta.opacity(0.12)` |
| Tag chip bg | `SonderColors.terracotta.opacity(0.12)` |
| Momentum pill bg | `SonderColors.terracotta.opacity(0.1)` |
| Rating bar: must-see | `SonderColors.ratingMustSee` |
| Rating bar: solid | `SonderColors.ratingSolid` |
| Rating bar: skip | `SonderColors.ratingSkip` |
| Rating activity bg | `SonderColors.pinColor(for: rating).opacity(0.2)` |
| Follow button (not following) | `SonderColors.terracotta` bg, white text |
| Follow button (following) | `SonderColors.warmGray` bg, inkDark text |
| Settings section headers | `SonderColors.terracotta` |
| Sign out text | `SonderColors.dustyRose` |
| City gradient fallbacks | 5 rotating pairs (see section 12) |
| City name overlay | White text on black gradient scrim |
| Want to Go bookmark | `SonderColors.terracotta` |
| WTG source attribution | `SonderColors.terracotta` |

### Typography

| Usage | Token |
|-------|-------|
| Username (own profile) | `SonderTypography.largeTitle` |
| Username (other profile) | `SonderTypography.title` |
| Section headers | `SonderTypography.caption` (uppercase, tracked 0.5) |
| Card headlines | `SonderTypography.headline` |
| Body text | `SonderTypography.body` |
| Captions, dates | `SonderTypography.caption` |
| Hero stat number | `.system(size: 48, weight: .bold, design: .serif)` |
| "places logged" label | `SonderTypography.headline` |
| City hero name | `.system(size: 22, weight: .bold, design: .serif)` |
| City grid name | `.system(size: 14, weight: .bold, design: .serif)` |
| Momentum pill | `.system(size: 12, weight: .semibold)` |
| Action button text | `SonderTypography.subheadline`, fontWeight .medium |
| Rating legend | `.system(size: 13-14)` |

### Spacing

| Usage | Token |
|-------|-------|
| Page padding | `SonderSpacing.md` |
| Section spacing | `SonderSpacing.lg` |
| Card internal padding | `SonderSpacing.md` |
| Card corners | `SonderSpacing.radiusLg` |
| Photo corners | `SonderSpacing.radiusSm` |
| Avatar size (own) | 100×100pt |
| Avatar size (other) | 88×88pt |
| Share card avatar | 60×60pt |
| Photo thumbnails | 60×60pt |
| Social stats spacing | `SonderSpacing.xxl` |

### Shadows

| Usage | Style |
|-------|-------|
| Avatar | `.black.opacity(0.1), radius: 8, y: 4` |
| Share card | `.black.opacity(0.08), radius: 12, y: 4` |
| OtherUserMap bottom card | `.black.opacity(0.08), radius: 8, y: 2` |

---

## 23. Supabase Schema & Queries

### Tables Used

#### `users`
```sql
id TEXT PRIMARY KEY           -- Supabase auth UUID
username TEXT UNIQUE NOT NULL
email TEXT
bio TEXT
avatar_url TEXT
is_public BOOLEAN DEFAULT true
created_at TIMESTAMPTZ DEFAULT now()
updated_at TIMESTAMPTZ DEFAULT now()
```

#### `follows`
```sql
follower_id TEXT REFERENCES users(id)
following_id TEXT REFERENCES users(id)
created_at TIMESTAMPTZ DEFAULT now()
PRIMARY KEY (follower_id, following_id)
```

#### `want_to_go`
```sql
id TEXT PRIMARY KEY
user_id TEXT REFERENCES users(id)
place_id TEXT
source_user_id TEXT REFERENCES users(id)  -- who recommended it
created_at TIMESTAMPTZ DEFAULT now()
```

### Key Queries

**Update profile:**
```sql
UPDATE users
SET username = {username}, bio = {bio}, avatar_url = {avatarURL}, updated_at = now()
WHERE id = {userID}
```

**Get follower/following counts:**
```sql
SELECT COUNT(*) FROM follows WHERE following_id = {userID}  -- followers
SELECT COUNT(*) FROM follows WHERE follower_id = {userID}   -- following
```

**Follow/unfollow:**
```sql
INSERT INTO follows (follower_id, following_id) VALUES ({currentUserID}, {targetUserID})
DELETE FROM follows WHERE follower_id = {currentUserID} AND following_id = {targetUserID}
```

**Get followers/following lists:**
```sql
-- Followers: join to get user details
SELECT users.* FROM follows
JOIN users ON follows.follower_id = users.id
WHERE follows.following_id = {userID}

-- Following: join to get user details
SELECT users.* FROM follows
JOIN users ON follows.following_id = users.id
WHERE follows.follower_id = {userID}
```

**Fetch user's logs (for OtherUserProfileView):**
```sql
SELECT id, rating, photo_url, note, tags, created_at,
       users!logs_user_id_fkey(id, username, avatar_url, is_public),
       places!logs_place_id_fkey(id, name, address, lat, lng, photo_reference)
FROM logs
WHERE user_id = {userID}
ORDER BY created_at DESC
```

**Want to Go with places:**
```sql
SELECT want_to_go.*, places(id, name, address, photo_reference),
       users!want_to_go_source_user_id_fkey(id, username)
FROM want_to_go
WHERE user_id = {userID}
ORDER BY created_at DESC
```

---

## 24. Known Limitations & Future Work

### Current Limitations

1. **ProfileView and SettingsView are in MainTabView.swift** — a 1,775-line file. Should be extracted to separate files.
2. **City extraction is address-string parsing** — fragile, depends on comma-separated format. Different countries have different address formats.
3. **No profile privacy controls** — all profiles are public. No option to hide logs or go private.
4. **Avatar upload goes through PhotoService** — same bucket as log photos. No separate avatar bucket or size optimization.
5. **Profile sync is separate from SyncEngine** — `EditProfileView` directly updates Supabase via its own `syncUserToSupabase()` method, bypassing the normal sync pipeline.
6. **No offline profile editing** — profile edits require network connectivity for the Supabase update.
7. **Social counts don't live-update** — follower/following counts are fetched on appear and pull-to-refresh only.
8. **Share card is static** — rendered at time of share; doesn't include a link back to the profile.
9. **WantToGoListView city extraction duplicates ProfileView logic** — same parsing in two places.

### Future Improvements

- [ ] Extract ProfileView and SettingsView to separate files
- [ ] Use structured geocoding (CLGeocoder) instead of address string parsing for city/country
- [ ] Add profile privacy controls (public/private toggle, hide specific logs)
- [ ] Dedicated avatar storage bucket with automatic resizing
- [ ] Route profile updates through SyncEngine for offline support
- [ ] Supabase realtime subscription for follower count updates
- [ ] Dynamic share card with deep link back to user profile
- [ ] Profile achievements/milestones (e.g., "Logged 50 places!")
- [ ] Consolidate city extraction into a shared utility
- [ ] Apple Sign-In integration (required for App Store if other social logins exist)
