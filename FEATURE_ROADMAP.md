# Sonder Feature Roadmap

## Project Context

### What is Sonder?
Sonder is a social place-logging iOS app where users rate and save places they visit (restaurants, cafes, attractions), organize them into trips, and discover places through friends' recommendations. Think of it as a personal travel journal meets social discovery.

### Tech Stack
- **Frontend**: SwiftUI, iOS 17+
- **Local Storage**: SwiftData (Apple's new persistence framework)
- **Backend**: Supabase (PostgreSQL + Auth + Realtime + Storage)
- **Location**: CoreLocation + Google Places API (REST, migrating to SDK)
- **Architecture**: MVVM-ish with `@Observable` services injected via SwiftUI Environment

### Current State (What's Built)

#### Completed Features
- **Authentication**: Email/password sign-in via Supabase Auth
- **Place Search**: Google Places autocomplete + nearby search
- **Logging Flow**: Search place → Preview → Add rating/photo/note/tags → Save
- **Personal Map**: View your logged places on a map with rating-colored pins
- **Trips**: Create trips, add logs to trips, trip detail view
- **Profile**: User stats, settings, avatar
- **Offline-First Sync**: SyncEngine with pending/failed states, network monitoring
- **Photo Upload**: Compression + Supabase Storage upload with retry queue
- **Social Layer (Complete)**:
  - Follow/unfollow users
  - Feed showing friends' logs (with trip cards, realtime updates)
  - User search
  - Want to Go list (bookmark places from friends' logs)
  - Other user profiles with map view
- **Explore Map (Complete)**:
  - Friends Activity Map with unified pins (personal + friends + combined)
  - Three toggleable layers (Mine / Friends / Saved)
  - Filter system (rating, category, recency, per-friend)
  - Friends Loved carousel
  - Ken Burns camera animation for pin selection
  - Map snapshot overlay for tab switching
- **Photo Suggestions**: Camera roll spatial index for location-based photo suggestions
- **Trip Exports**: Multiple export formats (journal, postcard, route map, collage, receipt)
- **Trip Collaboration**: Invitations, shared trips, collaborator management
- **Onboarding Flow**: Welcome, profile setup, first log, find friends
- **Proximity Notifications**: Alerts when near Want to Go places

#### Key Models (SwiftData)
| Model | Purpose |
|-------|---------|
| `User` | User profile (id, username, email, avatarURL, bio, isPublic) |
| `Place` | Cached place data (id, name, address, lat/lng, types, photoReference) |
| `Log` | A user's review (id, userID, placeID, rating, photoURLs, note, tags, tripID, syncStatus) |
| `Trip` | Trip container (id, name, description, dates, collaboratorIDs, createdBy) |
| `TripInvitation` | Trip collaboration invite (tripID, inviterID, inviteeID, status) |
| `Follow` | Follow relationship (followerID, followingID) |
| `WantToGo` | Saved/bookmarked place (userID, placeID, sourceLogID) |
| `RecentSearch` | Search history cache |
| `FeedItem` | Decoded feed entry (log + user + place, not persisted) |
| `ExploreMapItem` | Map pin types: LogSnapshot, UnifiedMapPin, ExploreMapPlace, filters |
| `ProfileStats` | Computed profile statistics |
| `PhotoLocationIndex` | Spatial index of camera roll photo locations (SwiftData) |

#### Key Services (`@Observable`, injected via Environment)
| Service | Purpose |
|---------|---------|
| `AuthenticationService` | Sign in/out, session management, current user state |
| `GooglePlacesService` | Place search, autocomplete, details, photos (REST API) |
| `LocationService` | CoreLocation wrapper, current location |
| `PlacesCacheService` | SwiftData cache for places + recent searches |
| `PhotoService` | Image compression, Supabase Storage upload queue |
| `SyncEngine` | Offline-first sync, pending count, network monitoring |
| `FeedService` | Load friends' feed, pagination, Supabase Realtime subscriptions |
| `SocialService` | Follow/unfollow, user search, follower counts |
| `WantToGoService` | Save/unsave places to Want to Go list |
| `TripService` | Trip CRUD, invitations, collaborator management |
| `ExploreMapService` | Friends' place data, unified pin computation, filtering |
| `ProfileStatsService` | Computed profile stats (cities, countries, heatmap, taste DNA) |
| `ProximityNotificationService` | Geofence alerts near Want to Go places |
| `PhotoSuggestionService` | Camera roll permission + location-based photo suggestions |
| `PhotoIndexService` | Spatial index of camera roll photos (SwiftData + Photos framework) |

#### Project Structure
```
sonder/
├── sonder/
│   ├── Models/            # SwiftData models + value types
│   ├── Services/          # @Observable services (15 services)
│   ├── Views/
│   │   ├── Authentication/ # Sign in/up views
│   │   ├── Components/    # Reusable UI (PlacePhotoView, TagInputView, SplashView, etc.)
│   │   ├── Feed/          # Social feed (FeedView, FeedItemCard, TripFeedCard, FeedLogDetailView)
│   │   ├── Journal/       # Journal tab (JournalContainerView, MasonryTripsGrid, Polaroid, BoardingPass)
│   │   ├── Logging/       # Log flow (SearchPlace, PlacePreview, RatePlace, AddDetails)
│   │   ├── LogDetail/     # View/edit existing log
│   │   ├── Main/          # MainTabView, tab navigation
│   │   ├── Map/           # Explore map (ExploreMapView, UnifiedBottomCard, pins, filters)
│   │   ├── Onboarding/    # First-launch onboarding flow (4 steps)
│   │   ├── Profile/       # User profile, other user profiles, edit profile
│   │   ├── Share/         # Log share cards (multiple visual styles)
│   │   ├── Social/        # User search, follow lists
│   │   ├── Trips/         # Trip list, detail, creation, story mode, exports
│   │   └── WantToGo/      # Saved places list
│   ├── Theme/             # SonderColors, SonderTypography, SonderSpacing
│   ├── Config/            # SupabaseConfig, GoogleConfig, GooglePlacesConfig
│   └── sonderApp.swift    # App entry, service injection, splash screen
├── sonderTests/           # Unit tests (Swift Testing framework, 105 tests)
└── docs/                  # Technical specs and design docs
```

#### Design System
All UI uses centralized theming from `SonderTheme.swift`:
- `SonderColors` - cream, terracotta, ochre, sage, ink variants, rating colors
- `SonderTypography` - title, headline, body, subheadline, caption
- `SonderSpacing` - xs, sm, md, lg, xl, xxl, radius values

#### Supabase Tables
- `users` - User profiles (synced from auth.users)
- `places` - Place data
- `logs` - User reviews/logs
- `trips` - Trip containers
- `trip_invitations` - Pending trip invites
- `follows` - Follow relationships
- `want_to_go` - Bookmarked places

### Running the App
1. Open `sonder.xcodeproj` in Xcode
2. Select iOS Simulator (iPhone 16 Pro recommended)
3. Build and run (Cmd+R)

### Running Tests
```bash
# From project root (105 tests, ~0.3s)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project sonder.xcodeproj -scheme sonder \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:sonderTests -parallel-testing-enabled NO
```

### Important Notes for Development
- **SwiftData + Testing**: Always keep strong reference to `ModelContainer` in tests (weak reference causes crashes)
- **@Observable Pattern**: Services use `@Observable` macro; UI reads properties directly, mutations trigger updates
- **Supabase Auth**: Check `authService.currentUser` before any authenticated operations
- **SyncEngine**: Use `startAutomatically: false` in tests to avoid network/timer side effects

---

## Feature Roadmap

Features below are prioritized by user value and development complexity.

---

## Phase 1: Friends Activity Map (Explore) — COMPLETE

**Status: BUILT**

The Explore tab (Tab 2) is a full social discovery map with:
- **Unified pins**: Personal, friends, and combined pins with smart overlap merging
- **Three toggleable layers**: Mine / Friends / Saved (Want to Go)
- **Filter system**: Rating, category (keyword-based), recency, per-friend filtering
- **Friends Loved carousel**: Places where 2+ friends rated must-see
- **Ken Burns camera animation**: Smooth frame-by-frame pan for pin selection
- **Map snapshot overlay**: Static snapshot during tab switches to prevent jarring reloads
- **Bottom cards**: Context-aware detail cards with drag-to-dismiss

See `explore_spec.md` for complete technical specification.

### Remaining Work
- [ ] Pin clustering for dense areas (no clustering currently)
- [ ] Category filtering via Google Place types (currently keyword-based)
- [ ] Supabase Realtime subscription for friends' new logs

---

## Phase 2: Shareable Trip Links

**Priority: HIGH**
**Enables: Viral growth, easier collaboration**

### Overview
Generate shareable links for trips that work across platforms with rich previews and flexible permissions.

### Core Features

#### 2.1 Deep Links
- Format: `sonder.app/trip/{trip_id}` or `sonder://trip/{trip_id}`
- **App installed**: Opens directly to trip view
- **App not installed**: Web preview page with App Store link
- Universal Links (Apple) / App Links (future Android)

#### 2.2 Permission Levels
- **View-only**: See trip details, places, collaborators (default for shared links)
- **Collaborator invite**: Can add/edit places, requires authentication
- Link creator can revoke access anytime
- Optional: Password-protected links

#### 2.3 Rich Previews (Open Graph)
- Trip cover photo as preview image
- Title: "{Trip Name} on Sonder"
- Description: "{X} places · {Date range} · by @{username}"
- Works in: iMessage, WhatsApp, Twitter, Slack, etc.

#### 2.4 Share UI
- Share button on trip detail view
- Options: Copy link, Share via system sheet, Generate QR code
- Toggle for "Allow collaborators" before sharing
- Show active share links with ability to revoke

### Supabase Schema

```sql
-- trip_shares table
CREATE TABLE trip_shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES auth.users(id),
    share_token TEXT UNIQUE NOT NULL, -- Short unique token for URL
    permission_level TEXT NOT NULL DEFAULT 'view', -- 'view' or 'collaborate'
    is_active BOOLEAN DEFAULT true,
    expires_at TIMESTAMPTZ, -- Optional expiration
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_trip_shares_token ON trip_shares(share_token);
CREATE INDEX idx_trip_shares_trip ON trip_shares(trip_id);
```

### Web Preview Page (Future)
- Simple landing page showing trip preview
- "Open in Sonder" button
- "Get Sonder" App Store link
- Can be a simple static page or Supabase Edge Function

---

## Phase 3: Quick Log Mode

**Priority: HIGH**
**Enables: Faster logging, reduces friction for casual users**

### Overview
One-tap rating from anywhere in the app, with option to add details later.

### Core Features

#### 3.1 Quick Log Gesture
- **Long-press** on any place pin (map, search result, friend's log)
- Popup with 3 rating buttons: Skip / Solid / Must-See
- Instant save with minimal data (place + rating + timestamp)
- Toast confirmation: "Logged! Add details?"

#### 3.2 Incomplete Logs Queue
- Logs without photos/notes shown in a "Complete your logs" section
- Gentle nudge in Profile tab: "3 logs need details"
- Batch editing mode for adding notes to multiple logs

#### 3.3 Quick Log from Notification (Future)
- "You're near {Place}. How was it?" notification
- Rate directly from notification (iOS 15+ interactive notifications)

### Implementation Notes
- Log model already supports optional photo/note
- Add `isComplete` computed property or flag
- UI component: `QuickLogPopover`

---

## Phase 4: Memories & Throwbacks

**Priority: MEDIUM**
**Placement: Home/Feed tab or Profile tab**

### Overview
Surface nostalgic content to increase engagement and emotional connection.

### Possible Placements

**Option A: Feed Tab Banner (Recommended)**
- Appears at top of feed on relevant days
- "This time last year..." card with photo + place
- Dismissible, appears once per memory

**Option B: Profile Tab Section**
- "Memories" section below stats
- Shows recent throwbacks in horizontal scroll
- Tap to see full log detail

### Core Features

#### 4.1 "On This Day" Memories
- Query logs from same date in previous years
- Show if user has 1+ year of history
- Prioritize logs with photos

#### 4.2 Trip Anniversaries
- "1 year since your Tokyo trip!"
- Link to trip detail view

#### 4.3 Milestone Celebrations
- "You've logged 50 places!"
- "Your 1-year Sonder anniversary"

### Implementation Notes
- Daily job or on-app-open check for matching dates
- Cache memories locally to avoid repeated queries
- Respect user preference to disable

---

## Future Phases (Lower Priority)

### Phase 5: Smart Recommendations
**Priority: LOW (requires data)**
- "Based on your must-sees, you might like..."
- Collaborative filtering using rating patterns
- Requires significant user data to be useful

### Phase 6: Collaborative Trip Planning
**Priority: LOW (complex feature)**
- Real-time trip editing with multiple users
- Voting/polling on places to visit
- Comments and discussion on trip items
- Requires: WebSocket or Supabase Realtime, conflict resolution

### Phase 7: Export Options
**Priority: LOW (nice-to-have)**
- Export trip as PDF itinerary
- Add trip to Apple Calendar
- Export to Google Maps list
- Share as Instagram story template

### Phase 8: Local Guides & Badges
**Priority: LOW (gamification)**
- Badge for 10+ logs in a city
- "Local Guide" indicator on profile
- Leaderboards by city/category

### Phase 9: Offline Mode
**Priority: LOW (complex infrastructure)**
- Download trip area for travel without data
- Sync when back online
- Requires significant caching architecture

---

## Implementation Priority Summary

| Phase | Feature | Priority | Complexity | Dependencies |
|-------|---------|----------|------------|--------------|
| 1 | ~~Friends Activity Map~~ | ~~HIGH~~ | ~~Medium~~ | **COMPLETE** |
| 2 | Shareable Trip Links | HIGH | Medium | None |
| 3 | Quick Log Mode | HIGH | Low | None |
| 4 | Memories | MEDIUM | Low | 1+ year of user data |
| 5 | Smart Recommendations | LOW | High | Large dataset |
| 6 | Collaborative Planning | LOW | High | Real-time infrastructure |
| 7 | Export Options | LOW | Medium | None |
| 8 | Badges | LOW | Low | None |
| 9 | Offline Mode | LOW | Very High | Caching architecture |

---

## Next Steps

1. **Pre-production hardening** — Apple Sign-In, Google Places SDK migration, performance fixes (see `load_testing_audit.md`, `reducing-supabase-calls.md`)
2. **Phase 2 (Shareable Links)** — viral growth enabler
3. **Phase 3 (Quick Log)** — quick win, low complexity
4. **Code quality** — see `docs/ISSUES.md` for tracked tech debt
