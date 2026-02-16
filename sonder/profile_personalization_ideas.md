# Profile Personalization — Ideas & Design Direction

How to make the Sonder profile page feel like a living portrait of someone's taste, not just a stats dashboard. Inspired by Letterboxd's approach to solo logging, but going further by leveraging what makes place-logging fundamentally richer: geography, temporality, physicality, and sensory experience.

---

## What Letterboxd Gets Right (and Where It Stops)

Letterboxd works because it makes you feel *understood*. Your rating distribution, your favorite four films, your diary calendar — they quietly tell a story about who you are. But Letterboxd is limited to a flat list of films with a star rating. Sonder has access to **geography, time, photos, movement, categories, neighborhoods, and social context**. We can build something that actually *knows* you.

---

## 1. Taste Identity

### 1.1 Taste DNA (Radar Chart)

A spider/radar chart showing the user's preference breakdown across 6-8 dimensions derived from their tags + Google Place `types`:

```
         Food
          /\
    Nightlife  Culture
       |        |
    Nature   Shopping
          \/
        Coffee
```

Each axis is weighted by log count + rating (must-see places in a category count 3x). The shape of the chart becomes a visual fingerprint — two people with different shapes have genuinely different tastes.

**Why it's better than Letterboxd:** Letterboxd shows genre stats as a boring bar chart on a separate page. This is a single glanceable shape on the profile that *means something*. Your friends can see at a glance that you're a food-and-nature person, not a nightlife person.

**Data source:** `Place.types` (Google categories like `restaurant`, `cafe`, `museum`, `park`, `bar`, `night_club`) + `Log.tags` (user-provided). Map both into a fixed taxonomy of 6-8 dimensions.

---

### 1.2 Explorer Archetype

Auto-classify the user into an archetype based on their logging patterns. Shown as a label under their username.

| Archetype | Signal |
|---|---|
| **The Foodie** | >60% of logs are restaurants/cafes |
| **The Culture Vulture** | High ratio of museums, galleries, historic sites |
| **The Night Owl** | Concentrated in bars, nightlife venues |
| **The Wanderer** | High geographic spread, many cities, few revisits |
| **The Regular** | Lots of revisits to the same places |
| **The Photographer** | High photo-per-log ratio, mostly must-see ratings |
| **The Completionist** | Logs everything — high volume, wide category spread |
| **The Curator** | Detailed notes on every log, lots of tags, thoughtful ratings |

The archetype updates as patterns change. Could show "You became The Foodie in October 2025" as a subtle timeline note.

**Why it's better:** Letterboxd doesn't attempt identity. This gives users a *word* for their exploration style that they'll want to share.

---

### 1.3 Signature Tags

Not just "most used tags" (which is what we have now) — but the user's **most distinctive** tags. What makes *your* tagging different from everyone else?

Use a TF-IDF-style weighting: if everyone tags "coffee" but only you tag "natural wine bars", "natural wine bars" is your signature tag even if you've used it fewer times.

Display as oversized word-art or a bold label: *"Nobody tags 'hole-in-the-wall ramen' quite like you"*

**Data source:** Compare user's tag frequency distribution against the global average from Supabase.

---

### 1.4 Rating Philosophy

A one-liner that describes how they rate, shown near the rating distribution bar:

- "You're generous — 68% of your places are Must-See" (high must-see ratio)
- "You have high standards — only 12% of your places make the cut" (low must-see)
- "You're balanced — your ratings are evenly split" (roughly equal thirds)
- "You don't waste time on bad places — only 5% are Skip" (low skip ratio)

Optionally show how they compare to the community average.

---

## 2. Temporal Patterns

### 2.1 Logging Calendar (Heatmap)

A GitHub-style contribution grid showing logging activity over the past 6-12 months. Each square = one day. Color intensity = number of logs that day.

```
Mon  ░ ░ ▓ ░ ░ ░ █ ░ ░ ░ ░ ░ ▓
Wed  ░ ░ ░ ░ ▓ ░ ░ ░ █ ░ ░ ░ ░
Fri  ▓ ░ ░ █ ░ ░ ░ ▓ ░ ░ ▓ ░ ░
     Jan       Feb       Mar
```

Use warm terracotta tones for intensity (cream → light terracotta → deep terracotta).

**Why it's better than Letterboxd:** Letterboxd has a diary but it's a plain list. The heatmap is instantly visual and shows consistency/bursts at a glance. Users love filling in squares (the GitHub effect).

**Data source:** `Log.createdAt` grouped by calendar day.

---

### 2.2 Streak Counter

```
Current streak: 4 days
Longest streak: 12 days (Jul 2025)
```

Subtle, not gamified. Shown as a small stat in the hero section or as a flame icon next to the places count when active.

---

### 2.3 First & Latest Bookends

A visual pairing of the user's very first log and their most recent log:

```
┌─────────────────────────────────────────┐
│  Your journey                           │
│                                         │
│  📍 Blue Bottle Coffee     →  📍 Tsuta  │
│  San Francisco                 Tokyo    │
│  Feb 4, 2026                  Feb 15    │
│  ────────── 1 year, 11 days ──────────  │
└─────────────────────────────────────────┘
```

Simple but emotionally resonant. Shows how far they've come.

---

### 2.4 Day-of-Week Pattern

A subtle insight: "You explore most on **Saturdays**" or "You're a weekday explorer — 72% of your logs are Mon-Fri."

Shown as a small horizontal bar chart (7 bars, one per day) or just as a text insight.

---

## 3. Geographic Patterns

### 3.1 Exploration Radius

How far from "home" do they typically explore?

- Auto-detect home base (most-logged neighborhood/city)
- Show average distance of logged places from home
- Show the **farthest** place they've logged: "Your farthest log is 5,400 miles from home — Shinjuku, Tokyo"
- Track if their radius is expanding over time

Display as a subtle stat or as concentric rings on a mini-map.

---

### 3.2 Neighborhood Fingerprint

Instead of just "top cities" (which we already have), drill down to **neighborhoods** within their most-logged city.

```
Your San Francisco

██████████  Mission District (14)
██████░░░░  Hayes Valley (8)
████░░░░░░  SoMa (5)
███░░░░░░░  North Beach (4)
██░░░░░░░░  Richmond (3)
```

Tapping a neighborhood shows those logs on a map. This is deeply personal — it reveals the *texture* of how someone lives in a city, not just that they live there.

**Data source:** Reverse geocode `Place.latitude/longitude` to get neighborhood names (one-time computation, cache the result). Or use the `address` field to extract sub-city-level locality.

---

### 3.3 Geographic Reach

A single dramatic stat:

> "Your logs span **4,200 miles** across **3 continents**"

Computed from the bounding box of all logged place coordinates. Optionally visualize as a great-circle arc on a mini globe or flat map.

---

### 3.4 New Territory Tracking

Monthly insight: "You explored **3 new neighborhoods** and **1 new city** this month."

Compares this month's logs against all previous logs. Highlights genuine exploration vs. returning to familiar spots.

---

## 4. Curation & Collections

### 4.1 Pinned Favorites (Top 4)

Let users pin their 4 favorite places to the top of their profile — the Letterboxd "four favorites" concept.

```
┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
│      │ │      │ │      │ │      │
│ 📸   │ │ 📸   │ │ 📸   │ │ 📸   │
│      │ │      │ │      │ │      │
│ Tsuta │ │Blue  │ │Dolores│ │ Aman │
│      │ │Bottle│ │ Park │ │Tokyo │
└──────┘ └──────┘ └──────┘ └──────┘
```

Square photo cards with the place name underneath. This is the **most important** personalization feature because it gives users direct control over how they present themselves. It answers: "If someone had 30 seconds on my profile, what 4 places would I want them to see?"

**Implementation:** Add a `pinnedPlaceIDs: [String]` field to the `User` model (max 4). Edit from profile via long-press or dedicated edit mode.

---

### 4.2 Curated Lists

User-created themed collections:

- "Best Ramen in NYC"
- "Date Night Spots"
- "Where to Take Visitors"
- "Rainy Day Cafes"

Each list has a title, optional description, cover photo (auto-selected from first must-see place), and ordered place entries.

**Why it matters:** Lists are the highest form of taste expression. They show *judgment*, not just logging. They're also the most shareable content type — "here's my best-of list for Tokyo" is something people actually send to friends.

**Data model:** New `PlaceList` model with `title`, `description`, `placeIDs: [String]`, `createdBy`, `isPublic`.

---

### 4.3 Auto-Generated Collections

The app creates smart collections from patterns:

| Collection | Logic |
|---|---|
| "Your Must-Sees" | All places rated must-see, sorted by recency |
| "Repeat Favorites" | Places logged more than once |
| "Solo Adventures" | Logs not attached to any trip |
| "This Year's Finds" | All logs from current calendar year |
| "Hidden Gems" | Must-see places that few other users have logged |

These appear as subtle suggestions: "We made a list for you: **Your 2025 Must-Sees** (14 places)"

---

## 5. Stats & Insights Page

A dedicated stats page (tappable from the profile) that goes deep. Inspired by Letterboxd's stats page but richer.

### 5.1 Category Breakdown

Donut chart or horizontal stacked bar of place types:

```
Restaurants  ████████████████  42%
Cafes        ████████          21%
Parks        █████             13%
Museums      ████              10%
Bars         ███                8%
Other        ██                 6%
```

Derived from `Place.types` mapped to a readable taxonomy.

---

### 5.2 Rating Distribution (Enhanced)

Current: stacked bar with counts.

Enhanced version adds:
- **Average rating per category** — "You rate cafes higher than restaurants on average"
- **Rating trend** — "You've been rating higher this month" (are they becoming more generous or more critical over time?)
- **Harshest vs. kindest category** — "You're toughest on bars (40% skip) and kindest to parks (80% must-see)"

---

### 5.3 Year in Review

Annual shareable summary (generate in December or on-demand):

```
┌─────────────────────────────────────┐
│         Your 2025 in Sonder         │
│                                     │
│  📍 127 places logged               │
│  🏙️ 8 cities explored              │
│  🌍 3 countries visited             │
│  📸 342 photos taken                │
│  🔥 41 must-sees discovered         │
│                                     │
│  Most-logged city: San Francisco    │
│  Farthest trip: Tokyo (5,400 mi)    │
│  Longest streak: 12 days            │
│  Top tag: "outdoor seating"         │
│                                     │
│  Your type: The Foodie              │
│  [Taste DNA radar chart]            │
│                                     │
│  Your Top 4:                        │
│  [pinned favorites photos]          │
└─────────────────────────────────────┘
```

Rendered as a shareable image (like the existing `ShareProfileCardView` but much richer). This is the single most viral feature — Spotify Wrapped for places.

---

### 5.4 Monthly Recap Card

A lighter version that appears at the start of each month:

> "In January you logged **8 places** across **2 cities**. Your must-see was **Tsuta Ramen**. You explored **1 new neighborhood** (Shinjuku)."

Shown as a dismissable card on the profile or feed. Shareable.

---

## 6. Photography & Visual

### 6.1 Photo Mosaic

A tappable grid of the user's best photos — not just city-level (which we have) but a unified mosaic of their most photogenic logs (prioritize must-see rated places with photos).

Layout: 3-column masonry or the Instagram-style 1-big + 2-small pattern. Tapping a photo navigates to that log.

---

### 6.2 Trip Timeline

A horizontal scrollable timeline replacing or supplementing the current "Recent Activity" section:

```
2025                                          2026
──┬──────┬──────────┬────┬──────────────┬─────
  │Tokyo │          │NYC │              │SF
  │trip  │ 5 solo   │wknd│  8 solo      │trip
  │(12)  │ logs     │(4) │  logs        │(7)
```

Trips shown as blocks (with cover photos), solo logs as dots between them. Gives a visual sense of the user's exploration rhythm over time.

---

## 7. Social & Comparative

### 7.1 Taste Compatibility

When viewing someone else's profile, show a compatibility score:

> "You and @sarah have **73% taste overlap**"

Based on:
- Shared tags (weighted by frequency)
- Similar ratings on places you've both logged
- Overlapping categories in your Taste DNA

Shown subtly on `OtherUserProfileView`. This drives follows — "oh, we have similar taste, I should follow them."

---

### 7.2 Shared Places

> "You and @sarah have both been to **7 places**"

Tappable to see the list with side-by-side ratings:

```
Tsuta Ramen      You: 🔥  @sarah: 🔥
Blue Bottle      You: 👍  @sarah: 🔥
Dolores Park     You: 🔥  @sarah: 👍
```

Conversation starter. Creates engagement.

---

### 7.3 Unique Finds

Places you've logged that none of your followers have:

> "You've discovered **12 places** nobody in your circle has been to"

Tappable to see the list. Makes the user feel like a genuine explorer, not just someone following trends.

---

### 7.4 Impact / Inspired By You

> "**8 people** saved your places to their Want to Go list"

Quantifies the user's influence without being a vanity metric — it's about helping others discover good places, not about likes.

---

## 8. Growth & Milestones

### 8.1 Milestone Moments

Non-gamified celebrations of genuine moments:

| Milestone | Copy |
|---|---|
| 1st log | "Your journey begins" |
| 10th place | "Double digits" |
| 1st must-see | "You found something special" |
| 1st international log | "You went international" |
| 50 places | "Half a hundred" |
| 5 cities | "Multi-city explorer" |
| 1st trip created | "Trip architect" |
| 100 photos | "A hundred moments" |

Shown as a timeline on the stats page or as subtle cards on the profile. No badges, no points, no leaderboards — just quiet acknowledgment.

---

### 8.2 Exploration Score

A single composite number (0-100) that captures how *actively* someone explores:

**Factors:**
- **Breadth** — number of unique categories explored
- **Geographic spread** — how many neighborhoods/cities
- **Consistency** — logging frequency over time (not just bursts)
- **Depth** — notes, photos, tags per log (quality of logging)
- **Discovery** — ratio of new places vs. revisits

Not competitive. Just a personal benchmark. "Your exploration score is 72 — you've been exploring more this month."

---

## 9. Priority & Sequencing

### Phase 1 — High Impact, Low Effort (use existing data as-is)
1. **Pinned Favorites (Top 4)** — highest identity-expression value, simple data model change
2. **Logging Calendar Heatmap** — purely derived from `Log.createdAt`, visually striking
3. **Rating Philosophy one-liner** — simple computed string from rating distribution
4. **First & Latest Bookends** — two queries, high emotional resonance
5. **Enhanced Rating Distribution** — build on the existing section with per-category breakdown

### Phase 2 — Medium Effort, High Personalization
6. **Taste DNA Radar Chart** — requires mapping `Place.types` + `Log.tags` to a taxonomy
7. **Explorer Archetype** — derived from Taste DNA, adds identity
8. **Neighborhood Fingerprint** — requires reverse geocoding or better address parsing
9. **Year in Review / Monthly Recap** — shareable cards, high viral potential
10. **Streak Counter** — simple but motivating

### Phase 3 — Social Features (require cross-user queries)
11. **Taste Compatibility** — needs server-side computation
12. **Shared Places** — cross-user query on Supabase
13. **Unique Finds** — requires comparing against followers' logs
14. **Impact / Inspired By You** — need to track Want to Go attribution

### Phase 4 — Deep Features
15. **Curated Lists** — new data model, CRUD UI, sharing
16. **Auto-Generated Collections** — server-side computation, push notifications
17. **Trip Timeline** — complex visual component
18. **Exploration Score** — composite calculation, needs tuning
19. **Photo Mosaic** — curation logic for "best" photos

---

## 10. Design Principles

1. **Show, don't tell.** A radar chart says more than "You like food." A heatmap says more than "You logged 47 places."
2. **Personal, not performative.** No leaderboards, no "top X% of users." Every insight should make the user feel understood, not ranked.
3. **Shareable by default.** Every section should be renderable as a standalone card image. The profile IS the marketing.
4. **Progressive disclosure.** The profile shows highlights; tapping anything goes deeper. Don't overwhelm on first glance.
5. **Evolving identity.** The profile should feel different at 5 logs vs. 50 vs. 500. Show what's meaningful at each stage, hide what's not.
6. **Warm, not clinical.** Use natural language ("You love hole-in-the-wall ramen spots") over data labels ("Tag: ramen, Count: 14"). The profile should read like a friend describing you, not a database query.
