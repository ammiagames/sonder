# Sonder — Growth Strategy & Competitive Playbook

*Last updated: Feb 2026*

---

## Core Thesis

Sonder does not win by being a better place-saving app. Sonder wins by being the app that **turns trips into stories people are proud to share** — and letting the stories do the marketing.

The logging, ratings, social feed, and map are the engine. The beautiful output — trip journals, place cards, year-in-review — is the product. Every shared artifact is an ad that demonstrates value to the viewer and creates a new user.

---

## Strategic Positioning

| App | What it is | Core action | Output |
|-----|-----------|-------------|--------|
| Corner | Social place bookmark | Save a pin | A list of pins |
| Polarsteps | GPS travel tracker | Track a route | A timeline |
| Google Maps | Navigation + saves | Star a place | Nothing |
| **Sonder** | **Travel journal** | **Log + rate + capture tips** | **A beautiful trip story** |

**Sonder's moat:** Rich post-visit data (ratings + structured tips + photos + occasion context) that produces shareable artifacts no competitor can replicate from their shallow data models.

---

## The Growth Loop

```
Log places on a trip
        |
        v
Generate beautiful trip journal
        |
        v
Share on Instagram Stories / send to friends
        |
        v
200 people see it, 20 think "I want that"
        |
        v
Download Sonder before their next trip
        |
        v
Log places on a trip ...
```

This loop does not require an existing social graph. It is powered by content quality, not network effects. One user with one trip can start the flywheel.

---

## Phase 1: Make the Output Undeniable

**Goal:** The trip export is so visually stunning that anyone who sees it wants to create one.

**Timeline:** 2-4 weeks

**Priority work:**
- [ ] Polish all trip export formats to professional design quality
  - Trip Journal (scroll-through story: photo + place + rating + tip per stop)
  - Trip Postcard (single shareable image: hero photo + trip stats)
  - Trip Route Map (animated or static route with rated stops)
  - Trip Film Strip (horizontal photo strip with captions)
- [ ] Add subtle "Made with Sonder" watermark on all exports
- [ ] Ensure exports are optimized for Instagram Story dimensions (1080x1920)
- [ ] Add one-tap share to Instagram Stories, iMessage, and general share sheet
- [ ] Record a polished demo video: log 5 places → tap "share trip" → beautiful journal appears
- [ ] Create a landing page (sonder.app) showcasing example trip journals

**Success criteria:** Show 10 people a Sonder trip journal and 8+ say "that's beautiful" or "I want to make one."

**Why this is Phase 1:** Nothing else matters if the output isn't compelling. Features, social graphs, and growth tactics are irrelevant if the thing you produce isn't worth sharing. Nail this first.

---

## Phase 2: Retroactive Trip Logging

**Goal:** Let people document trips they've already taken — the highest-intent onramp.

**Timeline:** 2-3 weeks

**Priority work:**
- [ ] Camera roll import flow:
  - Select date range for a trip
  - Pull photos with location metadata from the camera roll
  - Auto-match photos to Google Places via lat/lng
  - Present matched places for quick rating (Must-See / Solid / Skip)
  - Optional: add a one-line tip per place
  - Generate trip journal from the imported data
- [ ] "Document your last trip in 5 minutes" onboarding path
- [ ] Prompt after sign-up: "Have a recent trip you want to remember?"

**Success criteria:** A new user can turn a past trip into a shareable journal in under 10 minutes.

**Why this is Phase 2:** The biggest barrier to a travel journal app is "I'll use it on my next trip." Most people don't have a trip coming up. Retroactive import solves the cold-start problem — every user has past trips they wish they'd documented. This is also an onramp that Corner doesn't offer because their product is built around real-time saving, not post-trip reflection.

---

## Phase 3: Seed With Real Content (10-20 Trip Journals)

**Goal:** 10-20 real, beautiful trip journals exist and are being shared by real people.

**Timeline:** 2-3 weeks (overlaps with Phase 2)

**Priority work:**
- [ ] Identify 10-20 people (friends, friends-of-friends, travel-oriented people)
- [ ] Help them log a past trip using the retroactive flow
- [ ] Ensure each journal is polished and shareable
- [ ] Ask each person to share their journal on at least one platform (Instagram Story, Twitter, group chat)
- [ ] Collect screenshots and reactions for marketing material
- [ ] Create "example journals" section on landing page

**Success criteria:** 10+ trip journals shared publicly, generating organic interest and initial downloads.

**Why this is Phase 3:** You don't need 10,000 users to prove the concept. You need 10 beautiful outputs in the wild. Each one is proof the product works and a magnet for new users who want to create their own.

---

## Phase 4: The Receiving Experience

**Goal:** When someone receives a Sonder trip guide, the experience is so good it converts them.

**Timeline:** 3-4 weeks

**Priority work:**
- [ ] Web viewer for shared trip guides (no app required)
  - Interactive map with rated pins
  - Scroll through places with ratings, tips, photos
  - "Open in Maps" for each place
  - Mobile-optimized, fast, beautiful
- [ ] "Save to my Want to Go" action (requires Sonder account)
- [ ] "Create your own trip journal" CTA (subtle, not aggressive)
- [ ] App Clip or Smart App Banner for frictionless download prompt
- [ ] Deep link: opening a shared guide in the app shows it natively

**Success criteria:** 20%+ of guide viewers tap "Create your own" or download the app.

**Why this is Phase 4:** The person receiving a trip guide is the highest-intent potential user. They're either planning a trip to the same destination (they want the recommendations) or they're impressed by the artifact (they want to make one). Make the receiving experience so seamless that conversion is natural.

---

## Phase 5: Share Sheet + Import (Competitive Parity)

**Goal:** Match Corner's capture-from-anywhere capability while adding what they don't have.

**Timeline:** 3-4 weeks

**Priority work:**
- [ ] iOS Share Extension for saving places from any app
  - URL parsing: Google Maps, Instagram locations, TikTok, Yelp, TripAdvisor
  - Text extraction fallback with Google Places search
  - Save to Want to Go in under 5 seconds
- [ ] Add Sonder-only enrichment on save:
  - Source attribution ("from Sarah", "Instagram", "NYT article")
  - Occasion tags ("date night", "groups", "solo")
  - Trip association ("add to Tokyo trip")
- [ ] Google Maps import: bulk-import starred/saved places as Want to Go items
- [ ] Corner import: if technically feasible, import Corner lists

**Success criteria:** Saving a place to Sonder from Instagram is faster and richer than saving to Corner.

**Why this is Phase 5 (not Phase 1):** The share sheet is important, but it's a feature Corner already has. Building it first means competing on their turf before you've established your own. Build the output first (Phases 1-4), then add the capture layer.

---

## Phase 6: Structured Tips — The Data Advantage

**Goal:** Every Sonder log captures actionable intelligence that no competitor has.

**Timeline:** 2 weeks

**Priority work:**
- [ ] Add optional structured tip fields to the logging flow:
  - "What to get" (free text, short — "the mushroom pasta, the natural wine")
  - "Pro tip" (free text — "sit at the bar", "go before 6pm", "reservations essential")
  - "Skip" (free text — "overpriced wine list", "don't sit outside")
- [ ] Surface tips in:
  - Place preview cards on the map
  - Shared place cards and trip guides
  - Revisit screen when returning to a logged place
  - Want to Go detail view
- [ ] Shareable single-place card with structured tips

**Success criteria:** 50%+ of logs include at least one structured tip.

**Why this is Phase 6:** Structured tips make every Sonder recommendation 10x more useful than a Corner pin. But they only matter once you have users logging places. Build the acquisition engine first (Phases 1-5), then deepen the data model.

---

## Phase 7: Year-in-Review (Wrapped)

**Goal:** An annual viral event that creates FOMO and drives downloads.

**Timeline:** 4-5 weeks (ship by November for end-of-year)

**Priority work:**
- [ ] Compute personal travel stats from the year's logs:
  - Total places, cities, countries
  - Most-visited place, neighborhood, city
  - Top-rated cuisine/category
  - Biggest surprise (expected Skip that was Must-See)
  - Travel timeline (months visualized)
  - Taste profile summary
- [ ] Generate 5-8 shareable slides (Instagram Story format)
- [ ] Beautiful design with Sonder branding
- [ ] Share to Instagram Stories, save to camera roll, share as web link
- [ ] Notification: "Your 2026 Year in Review is ready"

**Success criteria:** 60%+ of active users share at least one Wrapped slide.

**Why this is the long-term play:** Corner cannot build this because they don't capture ratings. Wrapped only works with opinionated data — "your top-rated place" requires ratings, "your most-logged cuisine" requires tags. This is the single biggest annual growth event and it's structurally exclusive to Sonder's data model.

---

## Metrics That Matter

| Metric | Why it matters |
|--------|---------------|
| Trip journals shared per week | Direct measure of the growth loop |
| Guide views → app downloads | Conversion rate of the receiving experience |
| Places logged per trip | Data richness — more logs = better output |
| % of logs with structured tips | Data quality — tips make recommendations 10x better |
| Retroactive trips created | Cold-start onramp effectiveness |
| Wrapped slides shared (annual) | Viral event reach |

**Vanity metrics to ignore:** DAU, time in app, daily opens. Sonder is a travel app — people use it intensely during trips and lightly between them. Optimize for trip-level engagement, not daily engagement.

---

## What We Deliberately Do NOT Build

| Feature | Why not |
|---------|---------|
| AI/algorithmic recommendations | Corner's territory. We compete on trusted friends, not algorithms. |
| Vibe search / natural language | Same — this is Corner's differentiator. Don't chase it. |
| Gamification / badges / streaks | Undermines the journal aesthetic. Sonder is personal, not performative. |
| Strangers' content in feed | Friends-only. Authenticity over discovery volume. |
| Daily push notifications | Travel apps should be present when needed, silent when not. |

---

## Competitive Advantages We Protect

1. **Rich post-visit data** — ratings + structured tips + photos + notes + visit history. This data model cannot be replicated by save-only apps.
2. **Beautiful output** — trip journals, place cards, and Wrapped that are worth sharing. The output quality is the marketing.
3. **Full trip lifecycle** — save → plan → log → journal → share. No competitor covers the entire loop.
4. **Trust-based social** — friends only, chronological, no algorithm. Authenticity as a feature.
5. **Retroactive logging** — document past trips from your camera roll. Unique onramp that solves cold-start.
