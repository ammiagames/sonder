# Wandr
## Product Specification v3.0 — MVP Edition

*Log anything. Remember everywhere. Trips optional.*

---

## Vision

Wandr is the fastest way to log, rate, and share any place you experience. A beach. A speakeasy. A viewpoint. A taco truck. A neighborhood. The magic is in the flexibility—log anything, organize however you want.

---

## Strategic Positioning

Wandr fills the gap between two flawed paradigms:

| | Polarsteps | Beli | **Wandr** |
|---|---|---|---|
| Scope | Trip-centric (required) | Food-only | **Place-centric (anything)** |
| Input | GPS tracking (unreliable) | Manual logging | **Manual-first, GPS optional** |
| Retroactive | Painful | Easy | **Trivial** |
| Rating | Star ratings | Comparative ranking (tedious) | **Simple 3-tier rating** |
| Social | Solo journaling | Social, friends-first | **Social, friends-first** |

**Core differentiator:** Category-agnostic logging with optional trip organization. Simple rating that doesn't get exhausting at scale.

---

## Core Insight

Beli's comparative ranking is clever but becomes tedious after 50+ places. Users want **fast, simple logging that stays fast**—not a system that gets harder to use the more you use it.

Our 3-tier rating (Skip / Solid / Must-See) is instant at any scale. No comparisons. No fatigue.

---

## Key Features (MVP)

### 1. Universal Log

Log any place, any type. Completable in under 10 seconds.

**Required Fields:**
- **Location:** Search (Google Places API) or select from nearby suggestions
- **Rating:** 👎 Skip | 👍 Solid | 🔥 Must-See

**Rating Philosophy:**

| Rating | Meaning |
|---|---|
| 👎 Skip | Wouldn't recommend. Not worth the trip. |
| 👍 Solid | Good experience. Would go again if convenient. |
| 🔥 Must-See | Exceptional. Go out of your way for this. |

**Optional Fields (Progressive Disclosure):**
- Photo (single image)
- Note (freeform, 280 char max)
- Tags (freeform or suggested): #food, #bar, #hike, #viewpoint, #museum, etc.
- Trip association (optional)

### 2. Personal Map & List

- **Map view:** All logged places as color-coded pins
- **List view:** Chronological or filtered by rating/tag/trip
- **Search:** Find any logged place by name, tag, or location
- **Stats:** Countries, cities, total places logged

### 3. Trips (Optional)

Trips are organizational containers, not requirements.

- Create trip: Name, date range, cover photo (all optional except name)
- Associate logs to trips at any time (including retroactively)
- Collaborative trips: Invite friends to co-log a shared trip
- Trip view: Map + chronological list of trip logs

### 4. Social Feed

- Chronological stream of friends' logs (not algorithmic)
- Format: [Friend] rated [Place] in [City] + optional photo/note
- One-tap save to "Want to Go"
- Friends-only (no strangers, no algorithm)

### 5. Want to Go

- Saved places you haven't visited yet
- Grouped by city/region
- Shows who recommended it
- Smart prompt when near a saved place

### 6. Profile

- Map as hero (your places visualized)
- Stats: Places, countries, cities, top tags
- Public or friends-only (default: friends-only)
- Asymmetric follow model

---

## Screen Architecture

> **Design decision:** Full screens for all functionality. No bottom sheets. Sheets feel temporary—we want each action to feel intentional and complete.

### Navigation Structure

Tab bar with 4 primary destinations:

| Tab | Purpose |
|---|---|
| Feed | Friends' recent logs. Primary discovery surface. |
| Map | Your personal map. All logged places. Filter/search. |
| Trips | Trip list. Create, view, collaborate. |
| Profile | Your stats, settings, followers/following. |

**Floating Action Button (FAB):** "+" button for logging, visible on Feed and Map tabs.

### Log Flow (Full Screens)

| Screen | Description |
|---|---|
| 1. Search Place | Full screen. Search bar at top. Nearby suggestions below (if GPS available). Recent searches. Tap place to proceed. |
| 2. Rate Place | Full screen. Place name/address confirmed. Three large rating buttons (Skip/Solid/Must-See). Tap to select and proceed. |
| 3. Add Details | Full screen. Photo picker, note field, tag input, trip selector. All optional. "Save" button at bottom. |
| 4. Confirmation | Brief success state with haptic. Auto-returns to previous screen after 1s, or tap to dismiss immediately. |

---

## Technical Architecture

### Platform & Stack

| Component | Choice |
|---|---|
| Platform | Native iOS (SwiftUI). iOS 16.0 minimum. |
| Backend | Supabase (PostgreSQL + Auth + Storage + Realtime) |
| Authentication | Sign in with Apple (required) + Google Sign-In |
| Places API | Google Places API (search, details, photos) |
| Maps | Apple MapKit (display) |
| Photo Storage | Supabase Storage (S3-compatible) |

### Offline & Sync Strategy

> **Key insight:** Place search requires network (Google Places API), but log creation can be queued offline once a place is selected.

**Places Cache:**
- Cache searched places locally (SwiftData)
- Recently searched places available offline for re-logging
- "Want to Go" places cached for offline reference

**Log Queue:**
- Logs saved locally first, always
- Background sync when network available
- Pending logs marked with sync indicator
- Conflict resolution: Last write wins (user's device is source of truth)

**Photo Upload:**
- Photos compressed client-side (max 1200px, 80% JPEG)
- Upload queued with log, retries automatically
- Local thumbnail shown until upload completes

### Supabase Scaling

Supabase can handle Wandr's growth through at least the first 100K MAU:

| Plan | Cost | Capacity |
|---|---|---|
| Free | $0/mo | 50K MAU, 500MB DB. Good for development/beta. |
| Pro | $25/mo + usage | 100K MAU, 8GB DB. Typical bill: $35-75/mo. |
| Team | $599/mo | SOC 2, SSO, longer backups. When compliance matters. |

Re-evaluate architecture when approaching 100K MAU or if costs exceed $500/mo.

---

## MVP Development Roadmap

**Total estimated timeline: 16-20 weeks for one senior iOS developer.**

### Phase 1: Foundation (4-5 weeks)

**Goal:** Project scaffolding, authentication, and core data layer.

| Task | Estimate | Dependencies |
|---|---|---|
| Xcode project setup, SwiftUI architecture | 2-3 days | None |
| Supabase project setup, schema design | 2-3 days | None |
| Sign in with Apple integration | 3-4 days | Supabase |
| Google Sign-In integration | 2-3 days | Supabase |
| SwiftData models (User, Place, Log, Trip) | 3-4 days | Schema design |
| Sync engine foundation (queue, retry logic) | 4-5 days | SwiftData |
| Tab bar navigation shell | 1-2 days | Project setup |

*Deliverable: User can sign in with Apple or Google. Data syncs between local and Supabase.*

### Phase 2: Core Logging (3-4 weeks)

**Goal:** Complete log creation flow with places search.

| Task | Estimate | Dependencies |
|---|---|---|
| Google Places API integration | 3-4 days | None |
| Places cache layer (offline access) | 2-3 days | Places API, SwiftData |
| Search Place screen | 3-4 days | Places API |
| Rate Place screen (3-tier rating) | 2-3 days | Search screen |
| Add Details screen (photo, note, tags) | 3-4 days | Rate screen |
| Photo picker + compression | 2-3 days | Supabase Storage |
| Log sync with offline queue | 3-4 days | Sync engine |

*Deliverable: User can search for a place, rate it, add optional details, and save. Works offline.*

### Phase 3: Personal Experience (3-4 weeks)

**Goal:** Map, list, search, filtering, and profile.

| Task | Estimate | Dependencies |
|---|---|---|
| Map screen with MapKit | 4-5 days | Log data |
| Custom pin clustering and styling | 2-3 days | Map screen |
| List view with filters | 3-4 days | Log data |
| Search across all logs | 2-3 days | List view |
| Log detail view + edit/delete | 2-3 days | List view |
| Profile screen with stats | 3-4 days | Log data |
| Settings (privacy, account) | 2-3 days | Profile screen |

*Deliverable: User can view all their logs on a map, filter/search, see stats, manage settings.*

### Phase 4: Social Layer (3-4 weeks)

**Goal:** Follow system, feed, and Want to Go.

| Task | Estimate | Dependencies |
|---|---|---|
| Follow/unfollow system | 2-3 days | User model |
| User search + discovery | 2-3 days | Follow system |
| Feed screen (friends' logs) | 4-5 days | Follow system |
| Feed pagination + realtime updates | 2-3 days | Feed screen |
| Want to Go list + save action | 3-4 days | Feed screen |
| Push notifications (new follower, friend logged) | 3-4 days | Supabase Edge Functions |
| View other users' profiles | 2-3 days | Profile screen |

*Deliverable: User can follow friends, see their logs in feed, save places to Want to Go.*

### Phase 5: Trips (2-3 weeks)

**Goal:** Optional trip organization and collaboration.

| Task | Estimate | Dependencies |
|---|---|---|
| Trip CRUD (create, edit, delete) | 3-4 days | Trip model |
| Trips list screen | 2-3 days | Trip CRUD |
| Trip detail view (map + logs) | 3-4 days | Trips list |
| Associate logs to trips | 2-3 days | Trip detail |
| Collaborative trips (invite friends) | 3-4 days | Follow system |

*Deliverable: Users can create trips, associate logs, invite collaborators.*

### Phase 6: Polish & Launch (2-3 weeks)

**Goal:** Bug fixes, performance, App Store submission.

| Task | Estimate | Dependencies |
|---|---|---|
| Bug fixing + edge cases | 4-5 days | All phases |
| Performance optimization | 2-3 days | All phases |
| Haptics + micro-interactions | 2-3 days | All screens |
| Onboarding flow | 2-3 days | Auth |
| App Store assets + submission | 2-3 days | All phases |
| TestFlight beta testing | 5-7 days | Submission |

*Deliverable: Polished app submitted to App Store, beta tested with real users.*

---

## Data Model

```
User
  id, username, avatar_url, bio (280 char), is_public, created_at

Follow
  follower_id, following_id, created_at

Place
  id (Google place_id), name, address, lat, lng, types[], photo_reference

Log
  id, user_id, place_id, rating (skip/solid/must_see), photo_url?, note?,
  tags[], trip_id?, sync_status, created_at, updated_at

Trip
  id, name, cover_photo_url?, start_date?, end_date?, collaborator_ids[],
  created_by, created_at

WantToGo
  id, user_id, place_id, source_log_id, created_at
```

---

## Open Questions

### 1. Tag Taxonomy
Suggested tags with freeform custom? Or fully freeform? **Lean:** Suggested set + custom to balance consistency with flexibility.

### 2. Retroactive Logging UX
How to help users log past places? Options: Photo library integration, dedicated import flow, or organic (just search and log). **Lean:** Dedicated flow for onboarding, then organic.

### 3. Public Profiles
Should strangers see your map? **Lean:** Default friends-only, optional public toggle for "travel influencer" use case.

### 4. Monetization
Deferred until PMF. Options: Premium features, printed travel books, or stay free. **Constraint:** No ads in feed.

---

## V2 Features (Post-MVP)

- **"Ask a Friend"** — Ping friends for tips about places they've been
- **Collections** — User-curated lists ("Best rooftops," "Hidden gems")
- **Year in Review** — Wrapped-style summary of your travels
- **Taste Compatibility** — Score showing how similar you are to a friend
- **Android** — After iOS PMF confirmed
- **Travel Book Export** — Physical book of trips (monetization opportunity)

---

*— End of Specification —*
