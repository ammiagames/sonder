# Sonder Feature Roadmap

This document outlines upcoming features prioritized by user value and development complexity.

---

## Phase 5: Friends Activity Map (Explore)

**Priority: HIGH**
**Replaces: Current Map tab (profile map stays as personal view)**

### Overview
Transform the Map tab into a social discovery experience showing where friends have been, with smart clustering to avoid visual clutter.

### Core Features

#### 5.1 Friends Activity Map
- Show pins for places friends have logged
- **Clustered pins** when multiple friends reviewed the same place
  - Badge shows count: "3"
  - Tap to expand mini-feed of friends' reviews
  - Display aggregated rating with friend avatars
- **Clean UI approach for crowding:**
  - Zoom-based clustering (zoomed out = clusters, zoomed in = individual pins)
  - Maximum 3 avatar thumbnails on cluster, "+2 more" indicator
  - Bottom sheet for details instead of map overlays

#### 5.2 Saved Places Layer
- Toggle to show/hide Want to Go pins (different color/icon)
- Visual distinction: Friends' logs = filled pins, Your saves = bookmark outline
- Tap saved place to see who recommended it

#### 5.3 "Your Friends Loved" Section
- Horizontal carousel or section highlighting places with 2+ must-see ratings
- Shows on map with special "fire" indicator
- Quick filter to show only these places

#### 5.4 Filter System
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

## Phase 6: Shareable Trip Links

**Priority: HIGH**
**Enables: Viral growth, easier collaboration**

### Overview
Generate shareable links for trips that work across platforms with rich previews and flexible permissions.

### Core Features

#### 6.1 Deep Links
- Format: `sonder.app/trip/{trip_id}` or `sonder://trip/{trip_id}`
- **App installed**: Opens directly to trip view
- **App not installed**: Web preview page with App Store link
- Universal Links (Apple) / App Links (future Android)

#### 6.2 Permission Levels
- **View-only**: See trip details, places, collaborators (default for shared links)
- **Collaborator invite**: Can add/edit places, requires authentication
- Link creator can revoke access anytime
- Optional: Password-protected links

#### 6.3 Rich Previews (Open Graph)
- Trip cover photo as preview image
- Title: "{Trip Name} on Sonder"
- Description: "{X} places · {Date range} · by @{username}"
- Works in: iMessage, WhatsApp, Twitter, Slack, etc.

#### 6.4 Share UI
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

## Phase 7: Quick Log Mode

**Priority: HIGH**
**Enables: Faster logging, reduces friction for casual users**

### Overview
One-tap rating from anywhere in the app, with option to add details later.

### Core Features

#### 7.1 Quick Log Gesture
- **Long-press** on any place pin (map, search result, friend's log)
- Popup with 3 rating buttons: Skip / Solid / Must-See
- Instant save with minimal data (place + rating + timestamp)
- Toast confirmation: "Logged! Add details?"

#### 7.2 Incomplete Logs Queue
- Logs without photos/notes shown in a "Complete your logs" section
- Gentle nudge in Profile tab: "3 logs need details"
- Batch editing mode for adding notes to multiple logs

#### 7.3 Quick Log from Notification (Future)
- "You're near {Place}. How was it?" notification
- Rate directly from notification (iOS 15+ interactive notifications)

### Implementation Notes
- Log model already supports optional photo/note
- Add `isComplete` computed property or flag
- UI component: `QuickLogPopover`

---

## Phase 8: Memories & Throwbacks

**Priority: MEDIUM**
**Placement: Home/Feed tab or Profile tab**

### Overview
Surface nostalgic content to increase engagement and emotional connection.

### Possible Placements

**Option A: Feed Tab Banner**
- Appears at top of feed on relevant days
- "This time last year..." card with photo + place
- Dismissible, appears once per memory

**Option B: Profile Tab Section**
- "Memories" section below stats
- Shows recent throwbacks in horizontal scroll
- Tap to see full log detail

**Option C: Dedicated Memories Tab (Not recommended yet)**
- Too early, not enough content for most users

### Core Features

#### 8.1 "On This Day" Memories
- Query logs from same date in previous years
- Show if user has 1+ year of history
- Prioritize logs with photos

#### 8.2 Trip Anniversaries
- "1 year since your Tokyo trip!"
- Link to trip detail view

#### 8.3 Milestone Celebrations
- "You've logged 50 places!"
- "Your 1-year Sonder anniversary"

### Implementation Notes
- Daily job or on-app-open check for matching dates
- Cache memories locally to avoid repeated queries
- Respect user preference to disable

---

## Future Phases (Lower Priority)

### Phase 9: Smart Recommendations
**Priority: LOW (requires data)**
- "Based on your must-sees, you might like..."
- Collaborative filtering using rating patterns
- Requires significant user data to be useful

### Phase 10: Collaborative Trip Planning
**Priority: LOW (complex feature)**
- Real-time trip editing with multiple users
- Voting/polling on places to visit
- Comments and discussion on trip items
- Requires: WebSocket or Supabase Realtime, conflict resolution

### Phase 11: Export Options
**Priority: LOW (nice-to-have)**
- Export trip as PDF itinerary
- Add trip to Apple Calendar
- Export to Google Maps list
- Share as Instagram story template

### Phase 12: Local Guides & Badges
**Priority: LOW (gamification)**
- Badge for 10+ logs in a city
- "Local Guide" indicator on profile
- Leaderboards by city/category

### Phase 13: Offline Mode
**Priority: LOW (complex infrastructure)**
- Download trip area for travel without data
- Sync when back online
- Requires significant caching architecture

---

## Implementation Priority Summary

| Phase | Feature | Priority | Complexity | Dependencies |
|-------|---------|----------|------------|--------------|
| 5 | Friends Activity Map | HIGH | Medium | Phase 4 (Social) |
| 6 | Shareable Trip Links | HIGH | Medium | None |
| 7 | Quick Log Mode | HIGH | Low | None |
| 8 | Memories | MEDIUM | Low | 1+ year of user data |
| 9 | Smart Recommendations | LOW | High | Large dataset |
| 10 | Collaborative Planning | LOW | High | Real-time infrastructure |
| 11 | Export Options | LOW | Medium | None |
| 12 | Badges | LOW | Low | None |
| 13 | Offline Mode | LOW | Very High | Caching architecture |

---

## Next Steps

1. Complete Phase 4 (Social Layer) - in progress
2. Begin Phase 5 (Friends Activity Map) - highest user value
3. Phase 6 (Shareable Links) - can be developed in parallel
4. Phase 7 (Quick Log) - quick win, low complexity
