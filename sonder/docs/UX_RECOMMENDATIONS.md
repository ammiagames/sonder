# Sonder UX Recommendations

A comprehensive analysis of features to add, modify, and remove to create the best social travel journal experience.

---

## Table of Contents

1. [Core Philosophy](#core-philosophy)
2. [Features to Add](#features-to-add)
3. [Features to Modify](#features-to-modify)
4. [Features to Remove/Simplify](#features-to-removesimplify)
5. [Prioritized Roadmap](#prioritized-roadmap)
6. [Success Metrics](#success-metrics)

---

## Core Philosophy

### The Two Modes of Travel Journaling

Users engage with a travel journal in fundamentally different mental states:

| Mode | When | Mindset | Need |
|------|------|---------|------|
| **In-Moment** | At the location, traveling | Busy, distracted, time-pressured | Speed above all else |
| **Reflective** | After the trip, at home | Nostalgic, thoughtful, unhurried | Rich expression, detail |

**Design principle:** Optimize for in-moment capture (reduce friction to near-zero), but provide depth for reflective enhancement later.

### The Two Relationship Types

| Relationship | Purpose | Emotional Core |
|--------------|---------|----------------|
| **With Self** | Personal memory, growth, nostalgia | "Remember when..." |
| **With Friends** | Discovery, recommendations, connection | "You should try..." |

**Design principle:** Private journaling and social sharing should coexist without conflict. Users should never hesitate to log something because they're unsure who will see it.

---

## Features to Add

### 1. Quick Log Mode

**Problem:** Current logging flow requires multiple steps (search place, add photo, rate, add note, add tags, assign trip). When you're at an amazing ramen shop and your food is getting cold, this is too much friction.

**Solution:** A "Quick Log" option that captures the minimum viable entry:

```
Quick Log Flow:
1. Tap "+" button
2. Take/select photo
3. Auto-detect location OR confirm suggested place
4. Done (rating, note, tags, trip added later)
```

**Implementation Details:**
- Photo is the only required element (strongest memory trigger)
- Location auto-detected via GPS, matched to nearby places
- Entry marked as "Draft" with subtle indicator
- Draft entries appear in Journal with "Add details" prompt
- Push notification 2 hours later: "Add details to your log at Blue Bottle Coffee?"

**User Story:**
> "As a traveler eating at a restaurant, I want to log this place in under 10 seconds so I can enjoy my meal and add details later."

---

### 2. Private/Public Per Log

**Problem:** Some memories are deeply personal (a difficult travel day, a romantic spot, a place that disappointed). Users may avoid logging these if everything is public to followers.

**Solution:** Per-log visibility toggle with sensible defaults.

**Implementation Details:**
- Default visibility: User's global setting (Public/Private/Followers Only)
- Override per log with simple toggle
- Visual indicator on log cards (subtle lock icon for private)
- Private logs excluded from Feed, included in personal Journal/Map
- Trip-level visibility that cascades to logs (can still override individual)

**Privacy Levels:**
| Level | Visible To |
|-------|------------|
| Private | Only you |
| Followers | People who follow you |
| Public | Anyone (discoverable via search) |

**User Story:**
> "As a user, I want to log a place where I had a bad experience without sharing it publicly, so I remember to avoid it but don't broadcast negativity."

---

### 3. Memories/Throwbacks

**Problem:** The value of a journal compounds over time, but users rarely revisit old entries organically. The app should surface meaningful memories.

**Solution:** "On This Day" feature that resurfaces past logs.

**Implementation Details:**
- Daily check for logs from 1, 2, 3+ years ago on this date
- Push notification: "1 year ago in Barcelona..."
- Dedicated "Memories" section accessible from Profile
- Option to reshare to Feed: "Throwback: 1 year ago..."
- Weekly digest email (optional): "Your week in memories"

**Memory Triggers:**
- Same date, previous years
- Same location revisited
- Trip anniversaries (start date of past trips)
- Milestone logs (your 100th log, first log in a new country)

**User Story:**
> "As a long-time user, I want to be reminded of where I was a year ago so I can relive those memories and feel the value of my journaling habit."

---

### 4. Collections (Themed Lists)

**Problem:** Trips are time-bound containers, but taste-based groupings are often more useful for recommendations. "Best Coffee Shops" is more shareable than "Portland Trip 2024."

**Solution:** User-created collections that can span trips and time.

**Implementation Details:**
- Create collection with name, description, optional cover photo
- Add logs to collections (a log can be in multiple collections)
- Collections can be private or public
- Shareable link: sonder.app/@username/collections/best-ramen
- Browse others' public collections
- "Featured Collections" for discovery

**Default Starter Collections:**
- Favorites (auto-populated with "Must See" ratings)
- Want to Go (existing feature, reframed as collection)

**Collection Ideas to Suggest:**
- Best Coffee
- Date Night Spots
- Hidden Gems
- Worth the Splurge
- Kid-Friendly
- Outdoor Dining

**User Story:**
> "As a user with 2 years of logs, I want to create a 'Best Tacos' collection so I can share my expertise with friends visiting my city."

---

### 5. Travel Stats Dashboard

**Problem:** Users build valuable data over time but have no way to see the big picture. Stats create pride, motivation to log more, and interesting profile content.

**Solution:** Rich travel statistics on Profile.

**Stat Categories:**

**Geography:**
- Countries visited (with flag icons)
- Cities visited
- Most-logged city
- World map with pins (zoomable)

**Activity:**
- Total logs
- Logs this year
- Current streak (consecutive days/weeks with logs)
- Longest streak

**Taste Profile:**
- Rating distribution (pie chart: Skip/Solid/Must See)
- Most-used tags
- Top categories (if implemented)
- Favorite cuisine (based on tags/places)

**Social:**
- Followers / Following
- Most-saved log (by others)
- Logs in others' Want to Go lists

**Implementation Details:**
- Stats section on Profile (expandable)
- Shareable "Year in Review" card (end of year)
- Milestone celebrations (10th country, 100th log)

**User Story:**
> "As a user, I want to see how many countries I've logged places in so I feel accomplished and motivated to keep journaling."

---

### 6. Search Within Friend's Logs

**Problem:** The most common social use case is "What did [friend] like in [city]?" Currently requires scrolling through their entire profile.

**Solution:** Searchable friend profiles with location filtering.

**Implementation Details:**
- Search bar on OtherUserProfileView
- Filter by: City, Country, Rating, Tags
- "What did @sarah log in Tokyo?" natural language support (stretch)
- Results show map + list view toggle

**User Story:**
> "As a user planning a trip to Tokyo, I want to see what my friend Sarah logged there so I can add places to my Want to Go list."

---

### 7. Map Filters & Layers

**Problem:** As users accumulate logs, the map becomes cluttered. Need ability to filter and focus.

**Solution:** Filter controls on map view.

**Filter Options:**
- By Rating (Skip / Solid / Must See)
- By Trip
- By Date Range (This year, Last 6 months, All time)
- By Tags/Categories
- By Visibility (show private logs toggle)

**Layer Options:**
- Heatmap mode (density of logs)
- Cluster mode (grouped pins at zoom levels)
- Want to Go overlay (show saved places from friends)

**Implementation Details:**
- Filter sheet accessible from map toolbar
- Active filters shown as chips below map
- Remember last filter state

**User Story:**
> "As a user revisiting a city, I want to filter my map to show only Must See places so I can prioritize what to revisit."

---

### 8. Free-Form Journal Entries

**Problem:** Not every travel memory is a place. Delayed flights, chance encounters, personal reflections—these don't fit the place-log model but are part of the travel story.

**Solution:** Optional text-only journal entries within trips.

**Implementation Details:**
- New entry type: "Note" (vs. "Place Log")
- Can include photo, but no location required
- Appears in Trip timeline alongside place logs
- Chronologically integrated into Journal view
- Private by default (more personal nature)

**Entry Types:**
| Type | Required | Optional |
|------|----------|----------|
| Place Log | Photo OR Place | Rating, Note, Tags, Trip |
| Journal Note | Text | Photo, Trip |

**User Story:**
> "As a user, I want to write about the amazing people I met on a train without needing to attach it to a specific place."

---

### 9. Smart Tag Suggestions

**Problem:** Free-form tags lead to inconsistency ("coffee" vs "Coffee" vs "cafe" vs "café"). This degrades filtering and discovery.

**Solution:** Suggested tags based on place type + user history, with custom option.

**Implementation Details:**
- Detect place type from Google Places data (restaurant, museum, park, etc.)
- Suggest relevant tags: Restaurant → "dinner", "lunch", "date night", "casual", "fine dining"
- Show user's most-used tags as quick-add chips
- Allow custom tags (normalized: lowercase, trimmed)
- Merge similar tags: "cafe" and "café" → "cafe"

**Tag Categories:**
- Meal type: breakfast, brunch, lunch, dinner, snack
- Vibe: casual, fancy, romantic, family-friendly, solo-friendly
- Features: outdoor seating, view, live music, pet-friendly
- Cuisine: japanese, italian, mexican, etc.

**User Story:**
> "As a user logging a restaurant, I want relevant tag suggestions so I don't have to type and my tags stay consistent for filtering."

---

### 10. iOS Widget

**Problem:** Logging requires opening the app. A widget reduces friction and keeps the app top-of-mind.

**Solution:** Home screen widgets with multiple sizes.

**Widget Options:**

**Small (2x2):**
- Quick Log button
- Or: Last log with photo thumbnail

**Medium (4x2):**
- Travel stats (countries, cities, total logs)
- Or: "On This Day" memory

**Large (4x4):**
- Recent logs grid (last 4)
- Or: Mini map with recent pins

**Implementation Details:**
- Widget taps deep-link to relevant screen
- Quick Log widget opens camera immediately
- Refresh widget data on log creation

**User Story:**
> "As a user, I want a home screen widget to quickly log a place without navigating through the app."

---

### 11. Export & Backup

**Problem:** Users invest significant effort into their travel journal. They need assurance their data is safe and portable.

**Solution:** Export options for backup and sharing.

**Export Formats:**

**PDF Travel Journal:**
- Beautiful formatted document
- Photos, notes, maps
- Organized by trip or date range
- Printable (gift for self or others)

**Data Export:**
- JSON/CSV with all log data
- Photos as zip file
- For backup or migration

**Implementation Details:**
- Export section in Settings
- Choose date range or specific trips
- PDF customization (cover page, include maps, include private logs)
- Email or save to Files

**User Story:**
> "As a user, I want to export my Japan trip as a PDF so I can print it as a keepsake."

---

### 12. Recommendations Engine

**Problem:** Users follow friends for discovery but may miss relevant recommendations buried in the feed.

**Solution:** "For You" recommendations based on taste profile.

**Recommendation Sources:**
- Places logged by people you follow
- Popular with users who have similar taste
- Near your current location
- In cities you're visiting (detected via calendar or manual input)

**Implementation Details:**
- Separate "Discover" tab or section within Feed
- Personalized based on your rating patterns and tags
- "Because you liked [similar place]..." explanations
- Easy add to Want to Go

**User Story:**
> "As a user visiting a new city, I want to see places my friends have logged there, ranked by relevance to my taste."

---

## Features to Modify

### 1. Logging Flow Optimization

**Current:** Linear flow with multiple required decisions.

**Proposed:** Modular flow with progressive disclosure.

```
Current Flow:
Search Place → Select → Add Photo → Rate → Add Note → Add Tags → Assign Trip → Save

Proposed Flow:
[Quick Path]
Add Photo → Auto-detect Place → Save as Draft

[Full Path]
Add Photo → Confirm Place → Save
           ↳ Rating (optional, skippable)
           ↳ Note (optional, skippable)
           ↳ Tags (suggested, skippable)
           ↳ Trip (auto-assigned or skippable)
```

**Key Changes:**
- Photo triggers the flow (visual-first)
- Place auto-detected, confirm with one tap
- Everything except photo/place is optional
- Smart defaults reduce decisions
- "Add more details" available in Journal

---

### 2. Feed Context Enhancement

**Current:** Individual logs in chronological order.

**Proposed:** Contextual grouping with narrative.

**Grouped Feed Items:**
```
┌─────────────────────────────────────┐
│ @sarah added 5 places to Japan 2024 │
│ ┌─────┐ ┌─────┐ ┌─────┐            │
│ │ 📷  │ │ 📷  │ │ 📷  │  +2 more   │
│ └─────┘ └─────┘ └─────┘            │
│ View Trip →                        │
└─────────────────────────────────────┘
```

**Benefits:**
- Reduces feed clutter
- Provides narrative context
- Encourages trip exploration
- Still allows individual log view

---

### 3. Profile Enhancement

**Current:** Basic stats (logs, followers, following).

**Proposed:** Rich, visual profile with travel identity.

**Profile Sections:**
1. **Header:** Avatar, username, bio, follow button
2. **Stats Bar:** Logs | Countries | Cities | Followers
3. **World Map:** Mini map with all pins (tappable to expand)
4. **Taste Profile:** Rating distribution, top tags
5. **Collections:** Public collections grid
6. **Recent Logs:** Last 6 logs grid

**Visual Identity:**
- Badge system (10 countries, 100 logs, etc.)
- "Member since" date
- Current streak indicator

---

### 4. Want to Go Enhancement

**Current:** Flat list of saved places.

**Proposed:** Organized, actionable list.

**Organization Options:**
- By source user ("From @sarah", "From @mike")
- By location (grouped by city/country)
- By date saved (recent first)

**Trip Planning Mode:**
- "I'm going to Tokyo" → Show all Tokyo saves
- Add saves directly to a trip plan
- Mark as "Visited" (creates log prompt)

**Implementation:**
- Filter/sort controls at top
- Swipe actions: Remove, Add to Trip, View Source Log
- Map view of Want to Go places

---

### 5. Rating System Consideration

**Current:** Three tiers (Skip / Solid / Must See).

**Analysis:**

| Keep 3-Tier | Expand |
|-------------|--------|
| Simple, fast | More nuance |
| Clear meaning | Harder to decide |
| Visual (3 emojis) | Need more iconography |

**Recommendation:** Keep 3-tier primary rating, add optional sub-ratings.

**Optional Sub-Ratings:**
- Food/Experience: ★★★★★
- Vibe/Atmosphere: ★★★★★
- Value: ★★★★★

**When Shown:**
- Not during initial logging (friction)
- In "Add Details" flow
- Stored for personal reference, may inform recommendations

---

## Features to Remove/Simplify

### 1. Reduce Required Fields

**Change:** Only photo truly required. Everything else optional.

**Rationale:** Every required field is friction. A photo with auto-detected location has enough information to be useful.

---

### 2. Auto-Assign Trips

**Change:** If user is within date range of an active trip and location matches trip's general area, auto-assign without asking.

**Rationale:** "Add to Japan Trip?" is an unnecessary question if I'm in Japan during my Japan trip dates.

**Implementation:**
- Check active trips by date
- Check location proximity to trip's logged places
- Auto-assign with subtle confirmation: "Added to Japan 2024"
- Easy to change if wrong

---

### 3. Consolidate Navigation

**Audit Areas:**
- Can you reach Log Detail from multiple paths? Ensure consistency.
- Is Settings duplicated anywhere?
- Are there orphan screens?

**Principle:** One clear path to each destination. Reduce cognitive load.

---

### 4. Simplify Onboarding

**Current:** Unknown (needs audit).

**Recommendation:**
- Minimal required info (email/Apple sign-in, username)
- No required follows or profile setup
- First log = first tutorial
- Progressive disclosure of features

---

## Prioritized Roadmap

### Phase 1: Core Experience (Reduce Friction)
**Goal:** Make logging effortless.

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| P0 | Quick Log Mode | Medium | High |
| P0 | Auto-assign Trips | Low | Medium |
| P1 | Smart Tag Suggestions | Medium | Medium |
| P1 | Reduce Required Fields | Low | High |

**Success Metric:** Time to log decreases by 50%.

---

### Phase 2: Personal Value (Make It Yours)
**Goal:** Increase emotional attachment.

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| P0 | Private/Public Per Log | Medium | High |
| P0 | Travel Stats Dashboard | Medium | High |
| P1 | Memories/Throwbacks | Medium | High |
| P1 | Free-Form Journal Entries | Medium | Medium |

**Success Metric:** 30-day retention increases by 20%.

---

### Phase 3: Social Depth (Connect & Discover)
**Goal:** Make following friends valuable.

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| P0 | Search Within Friend's Logs | Medium | High |
| P0 | Want to Go Enhancement | Medium | Medium |
| P1 | Collections | High | High |
| P1 | Feed Context Grouping | Medium | Medium |

**Success Metric:** Want to Go saves increase by 50%.

---

### Phase 4: Delight (Make It Special)
**Goal:** Create moments of joy.

| Priority | Feature | Effort | Impact |
|----------|---------|--------|--------|
| P1 | Profile World Map | Medium | Medium |
| P1 | iOS Widget | Medium | Medium |
| P2 | Export as PDF | High | Medium |
| P2 | Recommendations Engine | High | Medium |

**Success Metric:** NPS increases by 10 points.

---

## Success Metrics

### Core Engagement
| Metric | Current | Target |
|--------|---------|--------|
| Time to complete log | ? | < 15 seconds (quick mode) |
| Logs per active user per week | ? | 3+ |
| 30-day retention | ? | 40%+ |

### Social Health
| Metric | Current | Target |
|--------|---------|--------|
| Follow-back rate | ? | 50%+ |
| Want to Go saves per user | ? | 10+ |
| Feed scroll depth | ? | 80%+ view 5+ items |

### Long-term Value
| Metric | Current | Target |
|--------|---------|--------|
| 1-year retention | ? | 25%+ |
| Logs per user (lifetime) | ? | 50+ |
| Collections created per user | ? | 2+ |

---

## Appendix: Competitive Analysis

| Feature | Sonder | Instagram | TripAdvisor | Google Maps |
|---------|--------|-----------|-------------|-------------|
| Place logging | ✓ Primary | ✓ Tags only | ✓ Reviews | ✓ Save/Rate |
| Personal journal | ✓ Yes | ✗ No | ✗ No | ✗ No |
| Social feed | ✓ Yes | ✓ Yes | ✗ Limited | ✗ No |
| Trip organization | ✓ Yes | ✗ No | ✓ Yes | ✓ Lists |
| Private logs | Planned | ✓ Close Friends | ✗ No | ✓ Private lists |
| Recommendations | Planned | ✓ Algorithm | ✓ Algorithm | ✓ Algorithm |
| Travel stats | Planned | ✗ No | ✓ Points/Badges | ✗ No |
| Memories | Planned | ✓ Yes | ✗ No | ✓ Timeline |

**Sonder's Unique Position:** Personal travel journal that's social when you want it to be. Not a review platform, not a social media feed—a place for your travel memories that you can choose to share.

---

*Document created: February 2026*
*Last updated: February 2026*
