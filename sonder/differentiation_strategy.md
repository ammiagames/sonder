# Sonder — Differentiation Strategy

## Positioning

**Beli** = "Rank your restaurants"
**Google Maps** = "Navigate and save pins"
**Polarsteps** = "Document your travels"
**Sonder** = "Remember every place you've loved — and make it useful"

Sonder is not a restaurant ranker, a navigation tool, or a trip scrapbook. It's your **personal place memory** — a living record of everywhere you've been and everywhere you want to go, organized by your opinions, your context, and your life. It gets more valuable every week and becomes indispensable for daily decisions and trip planning alike.

---

## The 5 Moments That Define the Product

Every place app lives or dies on five recurring moments in a user's life. Winning all five makes Sonder irreplaceable.

---

### Moment 1: "I heard about a place — save it"

**When it happens**: A friend texts you a restaurant name. You see a coffee shop on Instagram. You read an article about hidden bars in Tokyo. You walk past a place that looks interesting. This happens 3-10 times per week for most people.

**How it's broken today**:
- **Google Maps**: Search → Star. The star goes into a list of 300 undifferentiated pins with zero context. You don't remember why you saved it, who told you about it, or when. Within a month, it's buried. Google Maps saved places is where recommendations go to die.
- **Beli**: Only works for restaurants. If someone recommends a park, a coffee shop, a museum, or a bar — Beli can't help. And there's no way to capture *why* or *who*.
- **What people actually do**: Screenshot the Instagram post. Text themselves the name. Add it to a Notes app list. Save the Instagram post. All of these are fragmented, unsearchable, and forgotten within weeks.

**What Sonder needs — Share Sheet Extension**:
A system-level share sheet that intercepts the save moment from ANY app. The flow:

1. User sees a place recommendation (Instagram, Google Maps, Safari, iMessage, TikTok — anywhere)
2. Taps Share → Sonder
3. Sonder auto-detects the place name/location from the shared content (URL parsing, text matching, or manual search fallback)
4. One screen: the place is shown with a "Save to Want to Go" button
5. Optional enrichment (one tap each, all skippable):
   - **Source**: Who/where did you hear about this? (`Sarah`, `Instagram`, `NYT`, `walked by`) — shown as chips from recent sources + free text
   - **Occasion**: What's it good for? (`date night`, `solo`, `groups`, `work from`, `special occasion`) — tap to add
   - **Trip**: Planning a specific trip? Assign it now.
6. Done. Saved in under 5 seconds without opening the full app.

**Why this wins**: It's faster than starring in Google Maps AND it captures context that no competitor preserves. Every save is a seed — for daily recommendations, for trip planning, for sharing with friends. The share sheet makes Sonder the universal inbox for place discovery, regardless of where the discovery happens.

**Technical notes**:
- iOS Share Extension with `NSExtensionActivationSupportsWebURLWithMaxCount` and text handling
- URL parsing for Google Maps links (`/maps/place/`), Instagram post locations, Yelp/TripAdvisor URLs
- Fallback: search field pre-populated with extracted text, backed by Google Places autocomplete
- Source tags stored as a `recommendedBy` field on WantToGo model
- Recent sources cached locally for quick chip display

---

### Moment 2: "Where should I go right now?"

**When it happens**: It's Saturday night. You need a dinner spot. Or it's 2pm and you want a coffee shop to work from. Or friends are in town and you need a bar. This happens 2-5 times per week.

**How it's broken today**:
- **Google Maps**: Shows every restaurant in the city. You scroll through strangers' reviews trying to remember which ones you've actually been to and liked. Your own stars are just pins — no ratings, no notes, no context. You can't ask "which of MY places is good for a date?"
- **Beli**: Shows your ranked restaurant list. But your #14 restaurant — is it good for a date or a work lunch? Is it nearby? Is it even open? The ranking tells you nothing about *when* or *why* to go.
- **What people actually do**: Scroll through Google Maps reviews, ask friends in a group chat, default to the same 3 places they always go.

**What Sonder needs — Smart Filtering on Map**:
The explore map becomes your personal concierge when filtered properly:

1. **Occasion filter**: Tap chips to filter by `date night`, `work from`, `solo`, `groups`, `late night`, `quick bite`, `special occasion`, `outdoor`
2. **Rating filter**: Must See only, or Must See + Solid
3. **Proximity**: "Near me" radius slider or "in this neighborhood"
4. **Place type**: Food, coffee, drinks, activities, outdoors (broader than Beli's restaurant-only)
5. **Status**: "Been there" vs "Want to Go" toggle — sometimes you want your proven spots, sometimes you want to try something new

Results show on the map with your notes visible in the preview card. The note format should encourage **actionable tips** (see Moment 4). When you find the right place, one tap to open in Apple Maps / Google Maps for navigation.

**Why this wins**: No other app can answer "show me my favorite date night spots within walking distance." Google Maps doesn't have your opinions. Beli doesn't have occasion context. This is a query that only works when you own both the rating data AND the contextual data — which requires the occasion tags from Moment 1 and the logging flow to support them.

**The key insight**: This feature gets more valuable with every log. At 10 logs, it's marginally useful. At 50 logs, it's indispensable. At 100+ logs, you can't imagine making a "where should we go?" decision without it. This is the retention flywheel.

---

### Moment 3: "Someone asked me for recommendations"

**When it happens**: A friend is visiting your city. A coworker asks "know any good Italian places?" Someone's planning a trip to a city you've been to. This happens 1-3 times per month, but it's high-stakes — you want to seem knowledgeable and helpful.

**How it's broken today**:
- **Google Maps**: You can create a "shared list" but it's ugly, lacks your opinions, and the recipient has to open Google Maps. Most people just text names one by one.
- **Beli**: You can share your restaurant ranking. But it's just restaurants, just a ranked list, and the recipient needs context — why is #7 good? What should they order?
- **What people actually do**: Type out 5-10 place names in a text thread with brief comments. The recipient either screenshots it or loses it in the conversation. Zero discoverability after that.

**What Sonder needs — Shareable Place Cards & City Guides**:

**Single place card**: When you want to recommend one spot, generate a beautiful card image containing:
- Place name and your photo
- Your rating (Must See / Solid)
- Your tip/note
- Occasion tags (so they know it's a "date night" spot)
- "Open in Maps" deep link
- Shareable as an image (iMessage, Instagram Story, WhatsApp) or a web link

**City guide**: When someone asks "what should I do in [city]?", generate a shareable web link:
- Interactive map of your picks in that city
- Organized by category (eat, drink, coffee, see, do)
- Your ratings and notes visible
- Each place has an "Open in Maps" link
- Filterable by the recipient (they can filter by occasion, rating, category)
- Beautiful, branded design — something people are proud to share
- No Sonder account required to view
- Subtle "Made with Sonder" branding + download CTA at the bottom

**Trip guide**: After completing a trip, the trip journal auto-generates a shareable guide in the same format. Your route, your stops, your ratings, your tips — all shareable as a link.

**Why this wins**: This is the feature that makes people *want* to tell others about Sonder. The output is so much better than a text thread or a Google Maps list that it reflects well on the sharer. And every shared guide is a passive advertisement — the recipient sees a product that's clearly better than what they're using, with a frictionless path to download.

**Viral mechanics**: Each shared guide has a "Create your own guide with Sonder" CTA. The recipient just received proof that the app is useful (they're literally holding the proof). Conversion from guide-viewer to app-downloader should be high because the value is self-evident.

---

### Moment 4: "I'm going back to a place I've been"

**When it happens**: You return to a restaurant you visited months ago. You're in a neighborhood and remember you went somewhere there but can't recall the name. A friend suggests a place and you think "haven't I been there?"

**How it's broken today**:
- **Google Maps**: Has zero memory of your visits (unless you opt into Timeline, which most people find creepy and never check). No opinions, no notes, no history.
- **Beli**: Stores your ranking number. No notes, no tips, no visit history. You rated it #23 once and that's frozen forever.
- **What people actually do**: Try to remember. Scroll through photos on their camera roll looking for food pics. Often give up and re-evaluate the place from scratch.

**What Sonder needs — Revisit Awareness & Actionable Tips**:

**On revisit** (when logging a place you've already been):
- Show previous visit(s): date, rating, note
- Prompt: "Has your opinion changed?" — easy re-rate
- Running count: "Visit #4"

**Actionable tip format** — during logging, encourage structured notes:
- **Best item**: "What's the must-order?" (free text, short)
- **Pro tip**: "Anything someone should know?" (e.g., "reservations essential", "sit at the bar", "go before 6pm")
- **Skip**: "Anything to avoid?" (e.g., "overpriced wine list", "don't sit outside")

These structured tips are stored as searchable, shareable data — not buried in a paragraph. They surface in:
- Your own preview card when you tap the place on your map
- The bottom card on the explore map
- Shared place cards and city guides
- Proximity notifications (optional): "You're near Tartine. Your tip: get the morning bun."

**Place relationship over time**:
- "You've been to Blue Bottle 8 times since March 2025"
- "Your most visited neighborhood: Williamsburg (23 places)"
- "Places you loved but haven't visited in 6+ months" — gentle resurface

**Why this wins**: Your past self becomes useful to your present self. No other app maintains a living, evolving record of your relationship with specific places. Beli freezes your opinion at a single ranking number. Google Maps doesn't even try. Sonder makes your history actionable.

---

### Moment 5: "I'm planning a trip"

**When it happens**: You decide to visit a new city (or revisit one). You have 2-6 weeks to plan. You want to figure out where to eat, what to see, where to stay, where to get coffee.

**How it's broken today**:
- **Google Maps**: You star random places from blog posts and Google searches. They pile up as undifferentiated pins on the map. No organization by day, no notes on why you saved them, no way to tell what's near what. When you arrive, you open the map and see 40 stars with no context.
- **Beli**: No trip concept. Zero planning functionality.
- **Polarsteps**: Focused on documenting *during/after* travel, not planning. No "want to go" integration.
- **What people actually do**: Google Sheets. Notion docs. Screenshotted Instagram posts. A Notes app list that gets increasingly chaotic. Multiple browser tabs. All disconnected from any map.

**What Sonder needs — Trip Planning from Want to Go**:

The insight: if you've been saving Want to Go places with context over weeks or months, trip planning is mostly done before you start. The feature just needs to surface and organize what you've already collected.

**Planning flow**:
1. **Create trip** → pick destination city/region
2. **Auto-populate**: Sonder shows all your Want to Go places in that area — saved over time from friends, articles, Instagram, etc. Each one shows the source ("from Sarah", "NYT article") and any occasion tags.
3. **Curate**: Swipe through to keep/remove. Add new places via search.
4. **Organize by day**: Drag places into day buckets. Map view shows each day's stops with routing so you can optimize geography. Or skip this step entirely — some people prefer to wing it.
5. **Collaborate**: Invite travel companions to the trip. They can add their own Want to Go places from their Sonder account. See each other's contributions.
6. **During the trip**: Want to Go places show as "planned" pins on your map. When you visit one, log it with a rating — it transitions from "planned" to "visited." New discoveries get logged and added to the trip in real time.
7. **After the trip**: The trip becomes a shareable guide (Moment 3). Your Want to Go sources get a satisfying "visited" checkmark. Places you didn't get to remain on your Want to Go list for next time.

**Why this wins**: Nobody else connects daily place saving → trip planning → trip logging → shareable output. Google Maps has saves but no planning. Polarsteps has logging but no planning. Beli has neither. Sonder closes the entire loop. And crucially, the planning is *effortless* because you've been saving places all along — you're not starting from scratch the night before departure.

---

## First Principles Differentiation

Beyond the five moments, these are deeper structural advantages that compound over time.

---

### 1. Universal Place Types — Not Just Food

Beli is restaurants. Google Maps saves are generic pins. Sonder logs *everything*: the park where you read on Sundays, the rooftop bar with the sunset view, the museum that was a skip, the bookshop with the hidden cafe, the neighborhood you wandered through, the hotel that surprised you.

This matters because:
- Real recommendations aren't just food. "What should I do in Tokyo?" means restaurants AND temples AND neighborhoods AND coffee shops AND parks.
- Occasion tags work across categories: "outdoor" applies to parks, rooftop bars, and cafe terraces equally.
- Your place identity is broader than your food taste. Sonder captures who you are as an *experiencer*, not just an eater.

---

### 2. Context Over Rankings

Beli's core mechanic is forced ranking — is this restaurant #14 or #15? This creates engagement through comparison but loses context. You know your #1 restaurant but you don't know which of your top 10 is right for *tonight*.

Sonder's core mechanic is **contextual memory**: not just "how good" but "good for what, when, and why." The three-tier rating (Must See / Solid / Skip) is intentionally simple because the value isn't in granular ranking — it's in the metadata: occasion, tips, notes, photos, visit history.

This is a fundamentally different data model:
- Beli: `place → ranking_number`
- Sonder: `place → rating + occasion + tips + notes + photos + source + visit_history + trip`

The richer data model enables every feature above — smart filtering, shareable guides with context, revisit tips, trip planning with sources. Rankings can't do any of this.

---

### 3. Your Data Works For You (Not Just For Display)

Google Maps saves are write-only. You save, you forget, you never read them. Beli rankings are for comparing with friends. Neither makes your data *actionable*.

Sonder's entire feature set is about making your logged data useful back to you:
- **Smart filtering** turns your logs into a personal concierge
- **Revisit tips** turn your notes into a future-self assistant
- **Trip planning** turns your Want to Go list into an itinerary
- **Shareable guides** turn your opinions into social currency
- **Proximity awareness** turns your logs into context-aware reminders

The principle: every piece of data you put into Sonder should come back to help you at least once. If it doesn't, we shouldn't be asking for it.

---

### 4. The Capture-Anywhere Advantage (Share Sheet)

Beli and Google Maps both require you to be *in their app* to save a place. But place discovery happens everywhere — Instagram, text messages, articles, conversations, walking down the street.

The share sheet extension makes Sonder the **universal capture layer** for place intent. Regardless of where you discover a place, it flows into one system. This is structurally superior to any in-app-only solution because it meets users where they already are.

Over time, this creates a gravity effect: the more places you've saved in Sonder, the more valuable it becomes as your single source of truth, and the less you need to check other apps for "wait, did I save that somewhere?"

---

### 5. Beautiful Output as Viral Mechanic

Google Maps shared lists are ugly and functional. Beli shares are a ranked list. Neither produces something you'd be *proud* to share.

Sonder's shareable guides should be beautiful enough that:
- People share them on Instagram Stories
- Recipients screenshot and save them
- They look better than a Notion doc or a Notes app list
- They function better than a Google Maps list (interactive map, your notes, one-tap navigation)

The output quality IS the marketing. Every shared guide demonstrates the product's value to a potential new user, with a frictionless path from "wow this is useful" to "I should make my own."

---

### 6. Passive Accumulation — The Anti-Effort App

Beli requires active effort: rate and rank every restaurant. Polarsteps requires editing your travel journal. Google Maps saved places require remembering to star things in the Maps app specifically.

Sonder should be the lowest-friction option:
- **Log in 5 seconds**: tap place → rate → done. Note, tags, photos all optional.
- **Save in 3 seconds**: share sheet from any app → one tap save.
- **Trip planning in 2 minutes**: your saved places auto-populate the itinerary.
- **Sharing in 1 tap**: generate guide → send link.

The principle: the app should feel like it's doing 80% of the work. You provide opinions; Sonder organizes, remembers, and surfaces them. The less effort required, the more data accumulates, and the more valuable the app becomes. This is the opposite of Beli's forced-ranking approach, which asks you to think hard about whether a place is #23 or #24.

---

### 7. Works Alone, Better Together

The social cold-start problem kills most social apps. Sonder must be fully valuable with zero friends on the platform.

**Solo value** (no friends needed):
- Personal place memory and smart filtering
- Want to Go list with sources
- Shareable guides (recipients don't need accounts)
- Trip planning and logging
- Revisit awareness and tips

**Social value** (when friends join):
- See friends' logs on the explore map
- Friends' ratings visible on places you're considering
- Collaborative trip planning
- Feed of friends' recent discoveries
- Taste comparison ("you and Sarah agree on 73% of places")

The social layer amplifies the solo experience but never gates it. This is the opposite of Beli, where the social comparison IS the product.

---

## Implementation Priority

| Phase | Feature | Impact | Effort |
|-------|---------|--------|--------|
| **1** | Share sheet extension | Wins capture moment. Creates daily habit. Foundation for everything else. | Medium |
| **2** | Occasion tags (on logs + Want to Go) | Enables smart filtering. Quick win — just chips in existing flows. | Low |
| **3** | Smart map filtering (occasion + rating + proximity) | Daily utility. The "where should I go?" answer. | Medium |
| **4** | Shareable place cards | Single-place sharing. Quick viral mechanic. | Medium |
| **5** | Shareable city guides (web link) | Multi-place sharing. Full viral loop. | High |
| **6** | Trip planning from Want to Go | Connects daily saves to travel. Full product loop. | High |
| **7** | Revisit awareness + structured tips | Deepens engagement over time. | Medium |
| **8** | Recommendation source tracking | Enriches Want to Go context. Satisfying loop closure. | Low |
| **9** | Proximity-based tip surfacing | Passive utility. "Your past self helping your present self." | Medium |
