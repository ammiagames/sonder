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
- **Social Layer (Phase 4 - In Progress)**:
  - Follow/unfollow users
  - Feed showing friends' logs
  - User search
  - Want to Go list (bookmark places from friends' logs)
  - Other user profiles

#### Key Models (SwiftData)
| Model | Purpose |
|-------|---------|
| `User` | User profile (id, username, email, avatarURL, bio, isPublic) |
| `Place` | Cached place data (id, name, address, lat/lng, types, photoReference) |
| `Log` | A user's review (id, userID, placeID, rating, photoURL, note, tags, tripID, syncStatus) |
| `Trip` | Trip container (id, name, description, dates, collaboratorIDs, createdBy) |
| `Follow` | Follow relationship (followerID, followingID) |
| `WantToGo` | Saved/bookmarked place (userID, placeID, sourceLogID) |
| `RecentSearch` | Search history cache |

#### Key Services (`@Observable`, injected via Environment)
| Service | Purpose |
|---------|---------|
| `AuthenticationService` | Sign in/out, current user state |
| `GooglePlacesService` | Place search, autocomplete, details, photos |
| `LocationService` | CoreLocation wrapper, current location |
| `PlacesCacheService` | SwiftData cache for places + recent searches |
| `PhotoService` | Image compression, Supabase Storage upload queue |
| `SyncEngine` | Offline-first sync, pending count, network monitoring |
| `FeedService` | Load friends' feed, pagination, Supabase Realtime |
| `SocialService` | Follow/unfollow, user search, follower counts |
| `WantToGoService` | Save/unsave places to Want to Go list |
| `TripService` | Trip CRUD, collaborator management |

#### Project Structure
```
sonder/
├── sonder/
│   ├── Models/          # SwiftData models
│   ├── Services/        # @Observable services
│   ├── Views/
│   │   ├── Auth/        # Sign in/up views
│   │   ├── Components/  # Reusable UI components
│   │   ├── Feed/        # Social feed views
│   │   ├── Logging/     # Place search, preview, add details
│   │   ├── LogDetail/   # View/edit existing log
│   │   ├── Main/        # MainTabView, tab navigation
│   │   ├── Map/         # Map views
│   │   ├── Profile/     # User profile, settings
│   │   ├── Social/      # User search, follow lists
│   │   ├── Trips/       # Trip list, detail, creation
│   │   └── WantToGo/    # Saved places list
│   ├── Theme/           # SonderColors, SonderTypography, SonderSpacing
│   ├── Config/          # Supabase config, Google Places config
│   └── sonderApp.swift  # App entry, service injection
├── sonderTests/         # Unit tests (Swift Testing framework)
└── FEATURE_ROADMAP.md   # This file
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
# From project root, or use Xcode: Product > Test (Cmd+U)
xcodebuild test -scheme sonder -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
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

## Phase 1: Friends Activity Map (Explore)

**Priority: HIGH**
**Replaces: Current Map tab (profile map stays as personal view)**

### Overview
Transform the Map tab into a social discovery experience showing where friends have been, with smart clustering to avoid visual clutter.

### Core Features

#### 1.1 Friends Activity Map
- Show pins for places friends have logged
- **Clustered pins** when multiple friends reviewed the same place
  - Badge shows count: "3"
  - Tap to expand mini-feed of friends' reviews
  - Display aggregated rating with friend avatars
- **Clean UI approach for crowding:**
  - Zoom-based clustering (zoomed out = clusters, zoomed in = individual pins)
  - Maximum 3 avatar thumbnails on cluster, "+2 more" indicator
  - Bottom sheet for details instead of map overlays

#### 1.2 Saved Places Layer
- Toggle to show/hide Want to Go pins (different color/icon)
- Visual distinction: Friends' logs = filled pins, Your saves = bookmark outline
- Tap saved place to see who recommended it

#### 1.3 "Your Friends Loved" Section
- Horizontal carousel or section highlighting places with 2+ must-see ratings
- Shows on map with special "fire" indicator
- Quick filter to show only these places

#### 1.4 Filter System
- **Rating**: Must-See only, Solid+, All
- **Category**: Food, Coffee, Nightlife, Outdoors, Shopping, Attractions
- **Recency**: Last month, 6 months, All time
- **Source**: All friends, Close friends (if implemented later)

### Supabase Considerations
- Efficient query for friends' logs with place joins
- Consider materialized view for "friends_places" if performance is an issue
- Index on (user_id, created_at) for recency filtering

### UI Changes
- Map tab icon changes to compass/explore icon
- Current personal map moves to Profile tab (already exists there)
- Add filter chip bar at top of map
- Bottom sheet for place details (replaces full-screen navigation)

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
| 1 | Friends Activity Map | HIGH | Medium | Social layer complete |
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

1. Complete Social Layer (follows, feed, want-to-go) - in progress
2. Begin Phase 1 (Friends Activity Map) - highest user value
3. Phase 2 (Shareable Links) - can be developed in parallel
4. Phase 3 (Quick Log) - quick win, low complexity
