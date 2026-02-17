# Trip Capsule — Design Vision & Specification

*The trip capsule is Sonder's core differentiator. When you open a past trip, it should feel like opening a keepsake box — personal, warm, and unmistakably yours. Not a database. Not a social feed. A memory.*

---

## Design Philosophy

Three principles, drawn from the best of physical journals, editorial magazines, and digital storytelling:

1. **Reduction, not addition.** Show fewer things with more space around each one. Whitespace signals that the content matters. (Cereal Magazine, Muji, Kinfolk)
2. **Your photos, your words, your story.** No Google descriptions. No strangers' comments. No platform noise. When you tap into a trip, every pixel is yours. (Day One, the anti-Corner)
3. **Pacing creates emotion.** A trip capsule is not a list — it's a story with an arc. Opening, rising action, climax, resolution. Control the scroll tempo. (Steller, Spotify Wrapped, Apple Memories)

---

## The Emotional Arc

Structure every trip capsule as a five-act story:

```
ACT 1: THE COVER
    Full-bleed hero photo, trip title in light serif, dates as a stamp
    Feeling: anticipation, "I remember this"

ACT 2: THE OVERVIEW
    Route map with animated polyline, trip stats (places, days, cities)
    Feeling: scale, "we really did all that"

ACT 3: THE DAYS
    Day-by-day chapters, each with an establishing photo + place entries
    Feeling: immersion, re-living the trip chronologically

ACT 4: THE MOMENTS
    Interspersed single-photo pauses with generous whitespace
    A quote from your note. A detail shot. Breathing room.
    Feeling: reflection, "that's the one I remember most"

ACT 5: THE CLOSING
    Final wide shot, trip stats summary, "Until next time"
    Feeling: bittersweet completeness, pride
```

---

## Act 1: The Cover

When you tap a trip card, the cover should fill the screen like opening a book.

### Layout
- **Full-bleed hero photo** — edge-to-edge, no safe area insets. The user's own cover photo (or best Must-See photo from the trip).
- **Gradient scrim** — from bottom, 0% to 60% black. Ensures text legibility without obscuring the photo.
- **Trip title** — large, light-weight serif. `Font.system(size: 36, weight: .light, design: .serif)`. White. Centered in the lower third.
- **Date stamp** — monospaced, letter-spaced, uppercase. `Font.system(size: 11, weight: .medium, design: .monospaced)` with `tracking(3.0)`. White at 70% opacity. Like a passport stamp.
- **Location subtitle** — "Tokyo, Japan" in the same monospaced style, slightly larger, above the title.

### The Opening Animation
Use iOS 18's `NavigationTransition` with `.zoom(sourceID:in:)` to create a hero transition — the trip card thumbnail expands seamlessly into the full-screen cover. This creates the "opening a capsule" feeling.

```swift
// On the trip card (source)
.matchedTransitionSource(id: trip.id, in: namespace)

// On the trip detail view (destination)
.navigationTransition(.zoom(sourceID: trip.id, in: namespace))
```

For pre-iOS 18, fall back to `.matchedGeometryEffect`.

### Subtle Motion
Apply a very slow Ken Burns effect on the cover photo — 3% scale increase over 8 seconds, easing in and out. This makes the static photo feel alive without being distracting.

```swift
@State private var isAnimating = false

AsyncImage(url: coverURL)
    .scaleEffect(isAnimating ? 1.03 : 1.0)
    .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: isAnimating)
    .onAppear { isAnimating = true }
```

---

## Act 2: The Overview

Scroll down from the cover to reveal the trip at a glance.

### Route Map
- **Full-width map** with a custom muted style (desaturated, warm-toned — not default Apple Maps brightness).
- **Animated route polyline** that draws itself stop-by-stop when the map scrolls into view. Use `MapPolyline` with a trim animation.
- **Stop markers** as small numbered circles along the route, colored by rating (terracotta = Must-See, sage = Solid, warm gray = Skip).
- Map height: ~250pt. Not too tall — this is a glance, not a full map view.

### Trip Stats Row
Below the map, a centered row of stats in the Spotify Wrapped style — bold numbers with small labels:

```
     14              5              3
   places          days          cities
```

- Numbers: `Font.system(size: 42, weight: .bold, design: .serif)` in `SonderColors.inkDark`
- Labels: `Font.system(size: 11, weight: .medium)` with `tracking(2.0)`, uppercase, in `SonderColors.inkLight`
- Generous spacing between each stat group (`SonderSpacing.xxl`)

### Optional: Trip Highlight
If there's a standout stat, show it as a warm pill below the stats row:
- "Your top-rated: Ichiran Ramen" in terracotta text on terracotta/10% background
- Or "8 of 14 places were food" — a taste insight

---

## Act 3: The Days

This is the heart of the capsule. Each day is a "chapter."

### Day Header
Each day begins with a section divider:

```
                DAY THREE
              The Coast
```

- Overline: `Font.system(size: 11, weight: .medium, design: .default)`, `tracking(4.0)`, `SonderColors.inkLight`
- Section title: `Font.system(size: 28, weight: .light, design: .serif)`, `SonderColors.inkDark`
- Generous vertical padding: 56pt above, 32pt below
- If dates are available: show the actual date as the overline instead ("NOVEMBER 14, 2025")

### Place Entry (The Core Unit)

Each logged place within a day follows this structure:

```
┌────────────────────────────────────────┐
│                                        │
│         [FULL-WIDTH PHOTO]             │
│         (3:2 aspect ratio)             │
│         (edge-to-edge, no radius)      │
│                                        │
├────────────────────────────────────────┤
│                                        │
│  Ichiran Ramen              🔥 Must See│
│  Shibuya, Tokyo                        │
│                                        │
│  "The tonkotsu broth was the best      │
│   I've ever had. Get the extra-firm    │
│   noodles and add the egg."            │
│                                        │
│  #ramen  #japanese  #mustvisit         │
│                                        │
└────────────────────────────────────────┘
```

**Specific design details:**

- **Photo**: Full content width, 3:2 aspect ratio, `.fill` content mode, clipped. NO rounded corners — this is the editorial/coffee-table-book approach. Photos are more immersive without border radius.
- **Place name**: `SonderTypography.title` (serif, semibold). Left-aligned.
- **Rating**: Inline with the place name, right-aligned. Rating pill as it exists now, but smaller — just the emoji + color dot, not a full labeled pill. Less UI, more content.
- **Address**: Simplified — just neighborhood + city, not full address. `SonderTypography.caption`, `SonderColors.inkMuted`.
- **Note**: This is the star. `Font.system(size: 16, weight: .regular, design: .default)` with generous `lineSpacing(7)`. `SonderColors.inkDark`. Indented slightly more than the title (40pt horizontal padding vs 24pt for the title). This creates the editorial narrow-column effect — your words framed with more whitespace.
- **Tags**: Small terracotta capsules as they exist now, but with 16pt top padding to breathe.
- **Section gap**: 48-56pt between place entries. Let each one be its own moment.

### Photo Layout Variations

Not every entry should look identical. Vary the photo layout based on available content:

- **Single photo**: Full-width, 3:2 ratio (the default)
- **No photo**: Skip the photo entirely. Show a thin terracotta horizontal rule (1pt, 40pt wide, centered) above the place name instead. The absence of a photo is its own aesthetic choice — like a blank page in a journal.
- **If we add multi-photo support later**: Use a hero + two details pattern:
  ```
  ┌──────────────────────────┐
  │      Hero (full width)   │
  ├────────────┬─────────────┤
  │  Detail 1  │  Detail 2   │
  └────────────┴─────────────┘
  ```
  With 3pt gutters between photos. No rounded corners.

### Transport Interstitials (Inspired by Polarsteps)

Between places that are in different neighborhoods/cities, show a subtle interstitial:

```
        · · · · · · · · ·
         Shibuya → Shinjuku
        · · · · · · · · ·
```

- Dotted line: small circles in `SonderColors.warmGrayDark`, 2pt diameter, 8pt spacing
- Text: `SonderTypography.caption`, `SonderColors.inkLight`
- This creates the travel rhythm — stop, move, stop, move — that makes trips feel like journeys

---

## Act 4: The Moments (Breathers)

Interspersed between day sections (every 4-6 place entries), insert a "moment" — a full-screen pause that breaks the rhythm and creates emotional punctuation.

### Moment Types

**Type A: The Full-Bleed Memory**
A single photo fills the entire screen width and most of the height (~80% of viewport). No text overlay. Just the image. Massive whitespace below (64pt) before the next section.

This is the coffee-table-book spread. One image, given the respect of an entire page.

**Type B: The Pull Quote**
A single sentence from one of your notes, displayed large and centered:

```



        "The tuna auction at
         5am was worth every
         minute of lost sleep."

              — Tsukiji Market



```

- Quote: `Font.system(size: 24, weight: .light, design: .serif)`, `SonderColors.inkDark`, centered
- Attribution: `SonderTypography.caption`, `SonderColors.inkMuted`
- Background: `SonderColors.cream` (same as page, no card treatment)
- Vertical padding: 80pt above and below
- This is the Cereal Magazine / Kinfolk moment — a single idea given an entire screen

**Type C: The Detail Shot**
A small photo (200x200pt) centered on the page with massive margins on all sides. Below it, a one-line caption in a handwritten-style font.

```



              ┌──────────┐
              │          │
              │  [photo] │
              │          │
              └──────────┘
            morning market


```

- Photo: Centered, with subtle white border (8pt padding + white background + soft shadow), like a Polaroid
- Caption: If available, use `Font.custom("Caveat", size: 16)` or fallback to `.system(size: 15, design: .rounded)` for a handwritten feel
- Optional: 2-3 degree rotation for the Polaroid-scrapbook effect
- This creates the intimate, personal, scrapbook moment

### Selection Logic
Auto-select moments based on the data:
- Pull quotes: pick the longest/most descriptive note from any Must-See log
- Full-bleed memories: pick the highest-quality photo (user photo preferred over Google Places photo)
- Detail shots: good for food close-ups, architectural details, or any square-ish photo

---

## Act 5: The Closing

The final section, after all days are shown.

### Layout

```
        ┌──────────────────────┐
        │                      │
        │   [Final wide shot]  │
        │   (full-bleed, 16:9) │
        │                      │
        └──────────────────────┘

               NOVEMBER 2025
               Tokyo, Japan

                    14
              places explored

             🔥 8 must-sees
             👍 5 solid finds
             👎 1 skip

          ─────────────────

            "Until next time."

              ── sonder ──
```

- Final photo: Full-bleed, cinematic 16:9 ratio. Ideally the last photo logged on the trip, or the cover photo again.
- Stats: Same large-number + small-label pattern from Act 2, but in a vertical stack
- Rating breakdown: Each rating with its emoji and count
- Closing text: `Font.system(size: 18, weight: .light, design: .serif)`, italic, `SonderColors.inkMuted`
- Sonder wordmark: Very subtle, `SonderColors.inkLight`, small. Not a logo — just the word in the app's serif style.
- Bottom padding: 80pt+. Let it breathe.

---

## Typography System (Trip Capsule Specific)

Extended from `SonderTheme.swift` — these are used only inside the trip capsule view:

| Role | Font | Color |
|------|------|-------|
| Cover title | `.system(size: 36, weight: .light, design: .serif)` | White |
| Cover date stamp | `.system(size: 11, weight: .medium, design: .monospaced)`, tracking 3.0 | White at 70% |
| Day overline | `.system(size: 11, weight: .medium)`, tracking 4.0, uppercase | `inkLight` |
| Day section title | `.system(size: 28, weight: .light, design: .serif)` | `inkDark` |
| Place name | `SonderTypography.title` (serif, semibold) | `inkDark` |
| Place address | `SonderTypography.caption` | `inkMuted` |
| Note text | `.system(size: 16)`, lineSpacing 7 | `inkDark` |
| Pull quote | `.system(size: 24, weight: .light, design: .serif)` | `inkDark` |
| Stat number | `.system(size: 42, weight: .bold, design: .serif)` | `inkDark` |
| Stat label | `.system(size: 11, weight: .medium)`, tracking 2.0, uppercase | `inkLight` |
| Handwritten caption | `Font.custom("Caveat", size: 16)` or `.system(size: 15, design: .rounded)` | `inkMuted` |

---

## Color Palette (Trip Capsule)

The trip capsule uses a deliberately restrained palette. Your photos provide all the color.

| Token | Value | Usage |
|-------|-------|-------|
| Background | `SonderColors.cream` | Page background |
| Card surface | None — no card backgrounds inside the capsule | |
| Text primary | `SonderColors.inkDark` | Place names, notes |
| Text secondary | `SonderColors.inkMuted` | Addresses, attributions |
| Text tertiary | `SonderColors.inkLight` | Date stamps, overlines, stat labels |
| Accent | `SonderColors.terracotta` | Rating pills, tags, route line on map |
| Divider | `SonderColors.warmGrayDark` at 30% | Thin rules, dotted travel lines |

**Key rule: No `warmGray` card backgrounds inside the capsule.** The capsule lives on cream directly. Cards and sections create a "dashboard" feel; the capsule should feel like a printed page.

---

## Spacing Constants (Trip Capsule)

| Constant | Value | Usage |
|----------|-------|-------|
| `sectionGap` | 56pt | Between major sections (days, moments) |
| `entryGap` | 48pt | Between place entries within a day |
| `contentPadding` | 24pt | Horizontal page margins |
| `narrowColumn` | 40pt | Extra inset for note text (editorial feel) |
| `captionOffset` | 12pt | Gap between photo bottom and text |
| `breathingRoom` | 80pt | Above/below moments, closing section |
| `photoGutter` | 3pt | Between photos in a multi-photo layout |
| `coverScrim` | 0% → 60% black | Gradient on cover photo |

---

## Micro-Interactions & Animation

### Scroll-Driven Effects
- **Day headers**: Fade in + slide up slightly (12pt) as they scroll into viewport. Use `.scrollTransition` modifier.
- **Photos**: Subtle parallax — photo moves at 0.9x scroll speed, creating a slight depth effect.
- **Stats numbers**: Count up from 0 to final value when they scroll into view (like Spotify Wrapped). Use `PhaseAnimator` or a simple `withAnimation` triggered by `onAppear`.
- **Route map polyline**: Animate drawing when the map section appears.

### Haptics
- **Day change**: Light haptic tick (`UIImpactFeedbackGenerator(.light)`) when scrolling past a day header.
- **Opening the capsule**: Medium haptic (`UIImpactFeedbackGenerator(.medium)`) when the cover transition completes.
- **Reaching the end**: Success haptic (`UINotificationFeedbackGenerator().notificationOccurred(.success)`) when you scroll to the closing section.

### Page Transitions (Story Mode)
If the user enters the existing swipe-through `TripStoryPageView`, enhance it:
- Cross-dissolve between pages (not the default TabView slide)
- Photo: subtle scale from 1.02 → 1.0 on appear (settling effect)
- Text: fade in with 0.3s delay after photo settles

---

## What Exists Today vs. What Needs to Change

### Current `TripDetailView`
- Standard card-based layout with `warmGray` section backgrounds
- Photos in rounded-corner cards
- All data crammed into one scrollable list
- Feels like a settings page, not a memory

### Current `TripStoryPageView`
- Good foundation — full-screen swipe with progress bar
- But each page is a uniform layout (photo + text stack)
- No breathing room, no moments, no arc
- Photos are in a fixed 400pt frame, not full-bleed

### Current Exports (Postcard, Journal, Route Map, Film Strip)
- Static image renders via `ImageRenderer`
- Good concepts but basic execution
- The in-app trip experience should be AS beautiful as the exports

### What Changes

| Element | Current | New |
|---------|---------|-----|
| Background | `warmGray` cards on cream | Content directly on cream, no cards |
| Photos | Rounded corners, fixed height | Full-bleed, varying aspect ratios |
| Typography | `SonderTypography.largeTitle` everywhere | Varied: light serif titles, monospaced dates, editorial body |
| Spacing | `SonderSpacing.md` between everything | 48-80pt section gaps, generous breathing room |
| Structure | Flat list of log cards | Five-act narrative arc |
| Animation | None | Scroll-driven fades, parallax, haptics |
| Entry point | Push navigation | Hero zoom transition from trip card |

---

## Implementation Priority

1. **Act 1 (Cover) + Act 3 (Days) + Act 5 (Closing)** — the core scroll experience. This alone transforms the trip detail from a list into a story.
2. **Hero zoom transition** — the "opening" feeling that sets the emotional tone before any content appears.
3. **Act 4 (Moments)** — pull quotes and full-bleed pauses. High emotional impact, relatively low implementation effort.
4. **Act 2 (Overview map + stats)** — the animated route map and stat counters.
5. **Scroll animations + haptics** — polish layer that makes everything feel alive.

---

## Reference Inspiration Summary

| Inspiration | What We Take |
|-------------|-------------|
| **Cereal Magazine** | Aggressive whitespace, light serif titles, narrow text columns |
| **Day One** | Date + location metadata as memory triggers, serif body text |
| **Polarsteps** | Animated route map, transport interstitials between stops |
| **Steller** | Full-bleed photos, mixed page types, controlled pacing |
| **Spotify Wrapped** | Bold stat numbers, data-as-identity, count-up animations |
| **Apple Memories** | Ken Burns on stills, full immersion (no UI chrome), music sync |
| **Artifact Uprising** | Hero + detail photo layouts, warm off-white, matte/printed feel |
| **Traveler's Company** | Reduction to essentials, monospaced stamps, intentional emptiness |
| **Coffee table books** | Cinematic wide photos, photo sequencing as storytelling |
