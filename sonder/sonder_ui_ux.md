# Sonder UI/UX Design Spec

## Core Vibe: "Warm Journal"

Sonder should feel like a **personal travel diary** that you share with close friends. It's cozy, nostalgic, and intimate—not performative or algorithmic. Every interaction should feel like flipping through a well-loved notebook or receiving a handwritten postcard from a friend.

---

## Design Principles

### 1. Personal, Not Performative
- This isn't Instagram. Users share to help friends, not to curate a public image.
- Avoid vanity metrics (no like counts, no follower leaderboards).
- Celebrate the places, not the poster.

### 2. Warm Over Cold
- Soft, inviting colors over stark whites and blacks.
- Rounded corners, gentle shadows, organic shapes.
- Photography should feel candid, not perfectly composed.

### 3. Tactile & Textured
- Subtle paper-like textures where appropriate.
- UI elements that feel like they have weight and depth.
- Consider: stamps, stickers, handwritten annotations as visual metaphors.

### 4. Memory & Nostalgia
- Logs are memories, not just data points.
- Time should feel present—"3 weeks ago" matters.
- Trips are stories with beginnings, middles, and ends.

### 5. Trust & Intimacy
- Friend recommendations feel like whispered secrets.
- "From @username" attribution builds trust.
- Small details show care (e.g., "Sarah saved this to her list").

---

## Color Palette

### Direction
Warm, earthy tones with moments of vibrant accent. Think: golden hour light, aged paper, terracotta, olive groves.

### Considerations
- **Primary background**: Warm off-white or cream (not pure white)
- **Secondary backgrounds**: Soft warm grays, light tans
- **Text**: Deep warm charcoal (not pure black)
- **Accents**: Earthy but vibrant—terracotta, ochre, sage, dusty rose
- **Rating colors**: Should feel natural, not traffic-light harsh
  - Skip: Muted, neutral (stone gray?)
  - Solid: Calm, reliable (sage green? warm blue?)
  - Must See: Warm, exciting (terracotta? golden amber?)

### Dark Mode
- Not inverted—should feel like evening/candlelight
- Deep warm browns/charcoals instead of pure blacks
- Accents remain warm

---

## Typography

### Direction
Readable, warm, with personality. Mix of utility and character.

### Considerations
- **Headers**: Could have subtle personality—rounded sans-serif or friendly serif
- **Body**: Clean and readable, but with warmth (avoid cold geometric fonts)
- **Accents**: Potential for handwritten-style font in specific places (trip titles? tags?)
- **Numbers/Data**: Clear but not sterile

### Hierarchy
- Place names should feel prominent and inviting
- Notes should feel personal, like journal entries
- Metadata (dates, addresses) should recede gracefully

---

## Imagery & Photography

### User Photos
- Should feel candid and authentic
- Consider: subtle warm filter or vignette to unify different photo qualities
- Rounded corners reinforce the journal/scrapbook feel

### Place Photos (from Google)
- These are often sterile—consider treatments to warm them up
- Overlay gradients, rounded corners, or subtle frames

### Empty States
- Illustrations over icons where possible
- Warm, inviting, encouraging (not sad/empty)
- Could have hand-drawn quality

---

## Iconography

### Direction
Friendly, slightly rounded, organic. Not too minimal, not too detailed.

### Considerations
- SF Symbols are a good base but may need customization
- Icons could have subtle warmth (rounded corners, softer strokes)
- Consider custom icons for core actions (log, save, rate)

### Rating Icons
Current: Emoji (👎 👍 🔥)
- Emojis are friendly but could explore custom illustrations
- Should be instantly recognizable
- Consider: stamps, badges, or hand-drawn marks

---

## Motion & Animation

### Direction
Gentle, natural, unhurried. Like pages turning or photos being placed.

### Considerations
- **Transitions**: Soft fades, gentle slides (not bouncy/elastic)
- **Feedback**: Subtle and satisfying (not aggressive haptics)
- **Loading**: Warm shimmers or gentle pulses
- **Celebrations**: Confetti feels wrong—maybe a gentle glow or stamp effect?

### Micro-interactions
- Saving a place: Could feel like pinning to a board or stamping
- Rating: Satisfying but not over-the-top
- Pull-to-refresh: Natural, paper-like

---

## Component Patterns

### Cards
- Soft shadows, rounded corners
- Generous padding (breathing room)
- Could have subtle paper texture or torn-edge effect

### Buttons
- Rounded, inviting
- Primary actions: warm accent colors
- Consider: pill shapes, subtle gradients

### Lists
- Generous spacing
- Dividers should be subtle or absent
- Each item should feel like a distinct memory

### Maps
- Warm map style if possible (Mapbox custom style?)
- Pins should feel like pushpins or stamps, not generic markers
- Could have hand-drawn quality

### Navigation
- Bottom tab bar: friendly icons, warm tints
- Transitions between tabs: smooth, natural

---

## Voice & Tone

### Copy Style
- Conversational, warm, encouraging
- First person where appropriate ("Your logs", "Places you've saved")
- Avoid corporate/sterile language

### Examples
- Not: "No results found" → "We couldn't find anything"
- Better: "No places yet" → "Your journal is waiting for its first entry"
- Not: "Error" → "Something went wrong"
- Better: "Oops, that didn't work. Try again?"

### Empty States
- Should feel like an invitation, not a failure
- "Your friends haven't shared any places yet" → "When friends log places, they'll show up here"

---

## Specific Screens (Notes)

### Feed
- Should feel like flipping through friends' postcards
- Each card is a mini-story
- Photos should be prominent but not overwhelming

### Map
- Your pins tell a story of where you've been
- Clusters could feel like collections/albums
- Selected pin could expand like opening a journal entry

### Library (Logs/Trips)
- Logs list: chronological journal entries
- Trips: distinct chapters or albums
- Visual hierarchy: trips feel "bigger" than individual logs

### Profile
- Personal stats should feel like "year in review" moments
- Map hero: a visual representation of your journey
- Not a resume—a reflection

### Log Detail
- The full story of a memory
- Photo is hero, but note/context is important
- Editing should feel like annotating, not form-filling

---

## Open Questions

- [ ] Custom illustrations vs. photography for empty states?
- [ ] How much texture is too much? (Subtle vs. skeuomorphic)
- [ ] Hand-drawn elements: where do they fit without feeling gimmicky?
- [ ] Should rating visuals evolve? (Emoji → stamps → custom?)
- [ ] Map style: how custom can we go?
- [ ] Sound design: any role? (Subtle stamp sound on save?)
- [ ] Seasonal/contextual theming? (Winter warmth, summer brightness)

---

## Inspiration References

To explore:
- Travel journals and scrapbooks
- Polaroid/Instax aesthetic
- Kinfolk magazine layouts
- Airbnb experience pages
- Letterboxd (for the personal logging feel)
- Pinterest boards (curated collections)
- Analog: Field Notes, Moleskine, postcard designs

---

## Implementation Notes

### Phase 1: Foundation
- Color palette update (warm off-white, warm grays)
- Typography audit (warmer fonts)
- Border radius consistency (more rounded)
- Shadow softening

### Phase 2: Components
- Card redesign with warmth
- Button style update
- Empty state illustrations
- Rating visual exploration

### Phase 3: Personality
- Micro-interactions
- Custom icons
- Map styling
- Transitions and animations

### Phase 4: Polish
- Sound design (optional)
- Seasonal touches (optional)
- Hand-drawn accents (where appropriate)

---

*This is a living document. The goal is warmth and intimacy—every decision should ask: "Does this feel like a personal journal shared with friends?"*
