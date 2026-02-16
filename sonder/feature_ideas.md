# Sonder — Feature Ideas

A comprehensive list of ideas to make Sonder a generational product. Organized by the emotional need they serve, not by implementation difficulty.

---

## I. Make Logging Feel Effortless and Addictive

The logging moment is the atomic unit of Sonder. If it's not faster and richer than any alternative, nothing else matters.

---

### 1. Siri / Voice Logging

Walking out of a restaurant with your hands full. Say: "Hey Siri, Sonder log this as Must See — get the mushroom pasta."

Sonder auto-detects the place from your current location, creates a log with the rating and note from your voice transcript. The entire interaction takes 3 seconds and you never touch your phone.

- Uses App Intents framework for native Siri integration
- Location-based place detection (nearest place within ~50m)
- Voice-to-text for the note field
- Confirmation via haptic tap on Apple Watch

---

### 2. Apple Watch Quick Rate

After you leave a place (detected via significant location change), your watch shows a subtle notification: "Were you at Tartine?" Three buttons: Must See / Solid / Skip. One tap. Done.

No phone required. No app open required. The lowest-friction logging possible on any platform.

- Uses CoreLocation significant location monitoring (battery-efficient)
- WatchKit notification with inline action buttons
- Optional: after tapping a rating, a second screen offers quick note input via dictation
- Syncs to phone via Watch Connectivity

---

### 3. Share Sheet Extension — Universal Capture

Save a place to Want to Go from ANY app — Instagram, Google Maps, Safari, iMessage, TikTok, email. Tap Share → Sonder → auto-detect place → save.

The share sheet is where the daily habit forms. If capturing to Sonder is faster and richer than starring in Google Maps, you win the save moment permanently.

- iOS Share Extension with URL parsing (Google Maps links, Instagram locations, Yelp URLs)
- Text extraction fallback → pre-populated search
- Optional source tag ("from Sarah", "Instagram", "article") and occasion tag
- No full app launch required

---

### 4. Smart Location Detection

When you open the logging flow, Sonder already knows where you are. Instead of searching, you see: "Are you at Blue Bottle Coffee?" with a one-tap confirm. If you're at a new place, the top search results are sorted by proximity.

Reduces the most tedious part of logging (searching for the place) to a single tap for repeat visits and familiar areas.

---

### 5. Logging Streaks (Gentle, Not Annoying)

"You've logged at least one new place every week for 8 weeks." A quiet streak counter in your profile — not Duolingo-aggressive push notifications, just a visible indicator of your consistency. Breaking the streak has no punishment. Maintaining it gives a small sense of pride.

The goal isn't to guilt people into logging. It's to make consistent loggers feel good about their habit.

---

## II. Make Your Data Genuinely Useful Every Day

Logged data that you never use is wasted effort. Every log should come back to help you at least once.

---

### 6. Smart Filtering — "What's Right for Right Now?"

The killer daily query: "Show me my Must See date night spots within walking distance."

Filter your map by:
- **Occasion**: date night, work from, solo, groups, late night, quick bite, special occasion, outdoor
- **Rating**: Must See only, Must See + Solid, or everything
- **Distance**: near me, this neighborhood, this city
- **Type**: food, coffee, drinks, activities, outdoors, shopping
- **Status**: places I've been vs. places I want to try
- **Recency**: visited recently vs. haven't been in months

This query is impossible in Google Maps (no opinions), impossible in Beli (no occasion context), and impossible anywhere else. It only works when you own both the rating AND the contextual metadata. Every log makes this feature more powerful.

---

### 7. "What Should I Order?" — Structured Tips

For restaurants and cafes, a dedicated "menu picks" field during logging:
- **Get**: "mushroom pasta, the natural wine, ask about the daily special"
- **Skip**: "overpriced appetizers, the house cocktails"
- **Pro tip**: "sit at the bar for better service", "go before 6pm", "reservations essential on weekends"

These aren't buried in a paragraph. They're structured, scannable data that surfaces in:
- Your place preview card on the map
- Shared place cards and city guides
- Proximity alerts ("You're near Tartine. Your tip: get the morning bun")
- The revisit screen when you return to a place

This is the most actionable form of food recommendation possible, and no app captures it in a structured way.

---

### 8. Proximity Briefing — "You're Near a Place You Loved"

Optional, low-frequency notification when you're near a logged Must See place: "You're near Diner. Your tip: get the burger, sit in the back room. Last visit: 4 months ago."

Not a push notification for every nearby place — that would be noise. Triggered only for Must See places you haven't visited in 3+ months, and max once per day. Your past self helping your present self.

Uses iOS geofencing (battery-efficient, OS-managed). Could also power a Live Activity when actively exploring a neighborhood.

---

### 9. Want to Go — Intelligent Nudges

Your Want to Go list is alive, not static:
- "You saved Ramen Lab 6 months ago (from Sarah). You're 8 minutes away right now."
- "You have 4 untried Want to Go places in this neighborhood."
- "This place has been on your list the longest — 11 months. Time to try it?"

Transforms the Want to Go list from a graveyard into an active discovery engine. Shows in a dedicated "Try Something New" section or as contextual suggestions on the map.

---

### 10. Discovery Roulette — "Just Pick for Me"

Can't decide where to eat? Shake your phone (or tap a button). Sonder picks a random place from:
- Your Want to Go list nearby (default)
- Your Must Sees you haven't been to in a while
- A friend's Must See that you haven't tried

Fun, low-pressure decision helper that removes the "where should we go?" paralysis. Includes a "spin again" option. The randomness makes it feel playful, not algorithmic.

---

### 11. Collaborative Want to Go Lists

Shared Want to Go collections between couples, friend groups, or roommates:
- "Date Night Ideas" — both partners add places, shuffle when you can't decide
- "Weekend Brunch Spots" — the friend group's running list
- "Tokyo Trip" — everyone adds their finds before the trip

Real-time sync. Each person's additions are attributed. When someone from the group visits a place, it gets a "tried it" checkmark with their rating. The list evolves from "things to try" to "things we've tried and rated."

---

## III. Make Sharing Irresistible

Every share is both a gift to the recipient and a passive advertisement for Sonder. The output has to be so good that people prefer sharing from Sonder over typing names in a text.

---

### 12. Place Cards — Single Recommendation Sharing

When you want to recommend one place, generate a beautiful card:
- Your photo (or the place's Google Photos image)
- Place name, neighborhood, category
- Your rating (Must See / Solid)
- Your structured tip ("Get: the tasting menu. Skip: the wine pairing.")
- Occasion tags ("great for: date night, special occasion")
- "Open in Maps" button
- Subtle Sonder branding

Shareable as:
- An image (iMessage, WhatsApp, Instagram Story)
- A web link (richer, with interactive map)
- A contact card (AirDrop)

This is what people actually need when someone asks "know any good Italian places?" One tap → beautiful card → send.

---

### 13. City Guides — Multi-Place Sharing

When someone asks "what should I do in your city?" or "what were your favorites in Tokyo?":

Generate a shareable web link containing:
- Interactive map with all your picks pinned
- Organized by category (eat, drink, coffee, see, do, stay)
- Your ratings, tips, and photos for each place
- Filterable by the recipient (occasion, category, neighborhood)
- Each place has "Open in Maps" for instant navigation
- Mobile-optimized, beautiful design
- No Sonder account needed to view

The guide updates if you add more places — it's a living document, not a static export. Share the same link with multiple friends; it always reflects your latest opinions.

---

### 14. Trip Guides — Post-Trip Sharing

After a trip, your chronological log auto-generates a shareable trip guide:
- Your route on a map
- Day-by-day stops with ratings, tips, photos
- Highlight reel of Must Sees
- "Places I skipped" (useful negative information)
- Total stats: places visited, days, cities

This replaces the "trip blog post" that 90% of people intend to write but never do. Sonder writes it for you from data you already logged. Share with friends planning the same destination.

---

### 15. Curated Collections / Place Playlists

User-created themed collections, like Spotify playlists for places:
- "My Perfect Saturday in Brooklyn" — coffee shop → bookstore → lunch → park → dinner → bar
- "Best Coffee in NYC" — your personal ranking
- "Rainy Day Spots" — indoor places with good vibes
- "Impress a Visitor" — your go-to must-sees for out-of-towners

Ordered, mapped, shareable. Each collection is a mini-guide. Other users can save a collection and use it as a ready-made itinerary. This is social without requiring a social graph — the content itself is the connection.

---

## IV. Make Trips Feel Magical

Trips are the tentpole emotional experience. They should feel special, well-supported, and produce beautiful artifacts.

---

### 16. Trip Planning from Want to Go

The feature that connects daily saving to travel:

1. Create a trip → pick destination
2. Sonder auto-shows your Want to Go places in that city, each with the source ("from Sarah", "NYT article") and occasion tags
3. Swipe to keep/remove, search to add more
4. Optionally organize by day — drag places into day slots, map shows routing
5. Invite collaborators — they see and contribute their own Want to Go places
6. Export the plan to Apple Calendar (optional)

The key insight: if you've been saving places for months via the share sheet, your trip is half-planned before you start. This makes the share sheet habit feel like it's paying off.

---

### 17. Trip Countdown & Anticipation

When a trip is created with dates:
- Countdown widget on home screen ("12 days to Tokyo")
- As departure approaches, surface: your Want to Go places for that city, friends' logs there, seasonal tips, weather context
- A "pre-trip briefing" the day before: map of your planned stops, packing reminders based on destination, currency info

Builds excitement and keeps the app top-of-mind in the lead-up.

---

### 18. Live Trip Mode

During an active trip, the app transforms:
- Map centers on trip destination with your planned + visited stops
- Want to Go places glow as "planned" — tap to navigate, then log after visiting
- New discoveries get auto-added to the trip
- Daily summary card at end of each day: "Today you visited 4 places. Best: [Must See place]. You walked 6.2km."
- Trip progress: "Day 5 of 10. 12 places logged. 6 Want to Go places remaining."

The trip becomes a live, evolving experience — not just retrospective documentation.

---

### 19. Wanderlust Mode — Guided Exploration

You're in a new neighborhood or city with free time. Activate Wanderlust Mode:

Sonder generates a walking route connecting:
- Your Want to Go places nearby (priority)
- Your friends' Must Sees you haven't tried
- Highly-rated community places that match your taste profile

The route is optimized for walkability (A → B → C, not zigzagging). Each stop shows the source, why it's recommended, and estimated walking time to the next stop. You can skip stops, reorder, or add spontaneous discoveries.

This is a self-guided walking tour built from your own data and your network's opinions. No other app can generate this because no other app has your Want to Go list + your friends' contextual ratings.

---

### 20. Interactive Trip Story

After a trip, auto-generate a scroll-through visual story:
- Each card is one stop: full-bleed photo, place name, your rating, your tip, a mini-map showing where this stop is in the overall route
- Swipe through chronologically
- Shareable as a web link (like an Instagram Story but permanent and richer)
- Beautiful enough to be a travel blog replacement

Most people want to document their trips but don't have the energy to write blog posts or organize photo albums. Sonder does it automatically from data they already captured. The story is the reward for logging.

---

## V. Make the App Feel Personal and Identity-Forming

The features that make people say "this is MY app" and feel a sense of ownership over their place identity.

---

### 21. Annual Wrapped — Year in Review

Spotify Wrapped but for places. End of year (or on-demand):

- "In 2026, you logged 94 places across 6 cities"
- "Your most-visited neighborhood: Williamsburg (18 places)"
- "Your top-rated cuisine: Japanese (8 Must Sees)"
- "Your biggest surprise: [a place you expected to Skip but rated Must See]"
- "Your most revisited place: Blue Bottle Coffee (11 visits)"
- "You tried 23 places from your Want to Go list"
- "Cities explored: New York, Tokyo, Paris, Portland, Barcelona, Austin"
- "Your recommendation accuracy: 78% of places you recommended to friends were rated Must See by them"

Shareable as cards/slides to Instagram Stories. This is the single biggest annual engagement and viral event. People WILL share this because it forms identity.

---

### 22. Taste Fingerprint — Your Place Identity

After 30+ logs, Sonder generates a visual taste profile:

Not just stats, but pattern recognition:
- "You gravitate toward neighborhood gems over trendy destinations"
- "Your sweet spot: casual lunch places with outdoor seating"
- "You're adventurous with coffee (12 different shops) but loyal with dinner (3 regular spots)"
- "You rate higher when traveling vs. at home"
- "Your taste is most similar to: [friend's name] (82% match)"

Displayed as a beautiful visual card — shareable, identity-forming. Updates as you log more. This is the Letterboxd effect: people want to see themselves reflected in their data.

---

### 23. "On This Day" Memories

A daily or weekly nostalgia nudge:
- "2 years ago today, you were at Tsukiji Market in Tokyo. You rated it Must See and wrote: 'the tuna auction at 5am was worth every minute of lost sleep.'"
- Shows your original photo, rating, and note
- Option to share as a memory card
- Option to revisit (if local) or add to a "return trip" Want to Go list

This works with zero friends on the app. It's purely personal and emotionally resonant. Creates a reason to open the app even on days you don't log anything.

---

### 24. City Expertise / Neighborhood Passport

Visualize your knowledge of places:

- Heat map of where you've logged places vs. unexplored areas
- "You've logged 23 places in Williamsburg. 0 in Bushwick." — gentle nudge to explore
- After reaching thresholds: "You're a Williamsburg local — 25 places logged"
- City-level stats: "You know NYC (87 places) better than anyone in your network"

Not gamified badges — just a quiet visual representation of your evolving relationship with the places you live and visit. Creates a completionist pull without being annoying about it.

---

### 25. Personal Map Aesthetic

Your Sonder map has a visual identity:
- Map style options: warm parchment, clean minimal, dark mode, vintage, satellite
- Pin styles: classic circles, polaroid thumbnails, minimalist dots
- Your shareable guides and place cards inherit your chosen aesthetic
- People recognize the visual style: "that's a Sonder guide"

This is small but meaningful — it makes the app feel like YOURS, not a generic utility. Customization drives ownership.

---

### 26. Milestone Celebrations

Quiet, delightful moments:
- "You just logged your 100th place." — special animation, stats summary
- "First log in a new country!" — flag emoji, country added to your map
- "You've now been to every continent." — (for dedicated travelers)
- "You've logged places in 10 different neighborhoods in your city."

Not achievement-spam. Rare, meaningful milestones that acknowledge your journey. Each one is shareable if you want, ignorable if you don't.

---

## VI. Social That Works Without Critical Mass

Features that create social value without requiring all your friends to be on the app.

---

### 27. Taste Match — Compare With Anyone

When someone shares their guide with you (or you view their profile), Sonder computes:
- "You and Sarah agree on 78% of overlapping places"
- "You both rated X as Must See"
- "You disagree on Y — you said Must See, she said Skip"

Works even without following each other — just from shared guides. This creates conversation and curiosity without requiring a full social graph. The comparison is specific and interesting, not just a percentage.

---

### 28. Recommendation Requests

Structured way to ask for recommendations:
- "I need a dinner spot for 4 in SoHo on Friday. Date night vibe."
- Share the request with specific friends (via iMessage/WhatsApp — they don't need the app)
- Friends can respond by picking from their Sonder logs or typing a suggestion
- Responses are collected in one place, not scattered across a group chat

This is how recommendations actually happen — someone asks, multiple people respond. Sonder just structures the chaos. The requester gets organized picks; the responders get to show off their knowledge.

---

### 29. Place Reactions — Lightweight Social

When you visit a place a friend has logged, option to send a lightweight reaction:
- "Went to your rec! 🔥" (one tap)
- "You were right about the mushroom pasta"
- "Tried it — not for me, but thanks!"

Not a full social feed. Just a thin social layer that closes the recommendation loop. The friend gets a notification that their recommendation led to action. This is satisfying for both parties and encourages more sharing.

---

### 30. Anonymous Community Layer

For users without friends on the app, an optional community layer:
- "87% of Sonder users rated this Must See"
- "People who loved [place you love] also loved [place you haven't tried]"
- Community-sourced tips that supplement your own notes

Opt-in, not default. Uses aggregate anonymized data. Helps with cold start (new users see community ratings before they have their own) and discovery (taste-based recommendations from the broader Sonder community).

---

## VII. Platform & Distribution

Features that extend Sonder beyond the main app.

---

### 31. Widget Ecosystem

- **Lock screen widget**: "3 Want to Go places nearby" or trip countdown
- **Home screen small widget**: your most recent log with photo and rating
- **Home screen medium widget**: mini-map showing nearby Must Sees and Want to Go places
- **StandBy mode widget**: your city map with Must Sees
- **Apple Watch complication**: nearest Must See or Want to Go place
- **Interactive widget (iOS 17+)**: quick rate buttons — "Were you at [place]?" with Must See / Solid / Skip

Widgets keep Sonder visually present without requiring a full app open. The interactive rating widget is particularly powerful — log a place without ever opening the app.

---

### 32. iMessage App

Send a place card directly in iMessage:
- Search your logs or Want to Go → tap → send as a rich iMessage card
- Recipient sees: place name, your rating, your tip, "Open in Maps" button
- Recipient can tap "Save to Sonder" if they have the app

This is the most natural sharing context. Someone asks "where should we eat?" You respond with a rich card, not just a name. Works even if the recipient doesn't have Sonder.

---

### 33. App Clip for Shared Guides

When someone receives a Sonder guide link, they can view it in an App Clip — no download required. Full interactive map, all your picks, filtering, navigation links. The App Clip includes a "Get the full app" CTA that's visible but not aggressive.

This removes 100% of the friction from the recipient's side. They get full value from your guide without installing anything. The quality of the experience sells the app.

---

### 34. Siri Shortcuts & Automation

Pre-built shortcuts:
- "Log this place" — detects location, opens quick-rate flow
- "Where should I eat?" — opens filtered map with Must Sees nearby
- "Share my [city] guide" — generates and copies the link
- "What's on my Want to Go list nearby?" — shows closest unvisited saves

Also: Shortcuts automation triggers. "When I arrive at [work], show me nearby lunch spots I haven't tried." "When I leave [home] on Saturday, suggest a Want to Go place."

---

### 35. Export & Print

Own your data completely:
- Export all logs as CSV/JSON (for data nerds)
- Export a trip as a PDF booklet — beautiful layout, your photos, your route map, your ratings and tips. Coffee-table-book quality.
- Export a city guide as a printable one-pager (for travelers who want a paper backup)
- Export your full map as a high-res image (for framing — "everywhere I've been")

The PDF trip journal is particularly powerful. People pay $40+ for Chatbooks/Artifact Uprising photo books. A Sonder trip journal that's print-ready is a premium feature people would pay for.

---

## VIII. Intelligence That Feels Magical, Not Creepy

Smart features that use your data to help you, without feeling algorithmic or surveillance-like.

---

### 36. Taste-Based Discovery

After 30+ logs, Sonder understands your preferences enough to suggest new places:
- "Based on your Must See coffee shops, you might like [new place nearby]"
- "You and Sarah have similar taste. She loved [place you haven't tried]."
- "People who rated [your favorites] as Must See also loved [suggestion]"

This is NOT an algorithmic feed. It's a dedicated "Discover" section that you check when you want inspiration. Transparent about why each suggestion is made. Never pushy.

---

### 37. Seasonal Awareness

Your logs have timestamps. Sonder knows what you enjoyed in summer vs. winter:
- "Last summer you loved these outdoor spots: [list]"
- "Your winter favorites: [cozy indoor places]"
- "Spring is here — 3 places on your Want to Go list have outdoor seating"

Surfaces the right places at the right time of year. Simple temporal matching, not complex ML.

---

### 38. Visit Pattern Insights

After enough data, surface personal patterns:
- "You log more places on weekends (68%) than weekdays"
- "Your average rating is higher when traveling (87% Must See) vs. at home (42% Must See)"
- "You've tried 14 ramen spots this year. Your top 3: [names]"
- "Your most-logged category: coffee (31 places)"
- "Neighborhoods you rate highest: [list]"

These insights are interesting, shareable, and make the data accumulation feel worthwhile.

---

### 39. Predictive Trip Suggestions

Based on your logging patterns and Want to Go saves:
- "You've saved 12 places in Barcelona. Time to plan that trip?"
- "You visited 3 Italian restaurants this month — how about a trip to Rome?"
- "Friends who liked your Tokyo favorites also loved Osaka and Kyoto"

Gentle, infrequent suggestions that feel helpful, not pushy. Only shown in a dedicated "Trip Ideas" section, never as push notifications.

---

## Quick Reference: Priority vs. Impact Matrix

### Must Build (High Impact, Foundation)
- Share sheet extension (#3)
- Occasion tags / smart filtering (#6)
- Shareable place cards (#12)
- Trip planning from Want to Go (#16)
- Structured tips / "What Should I Order" (#7)

### Should Build (High Impact, Differentiation)
- City guides (#13)
- Annual Wrapped (#21)
- Siri / voice logging (#1)
- Apple Watch quick rate (#2)
- Discovery Roulette (#10)
- Collaborative Want to Go lists (#11)

### Could Build (Medium Impact, Delight)
- Taste Fingerprint (#22)
- "On This Day" memories (#23)
- Neighborhood Passport (#24)
- Place Playlists (#15)
- Wanderlust Mode (#19)
- Interactive Trip Story (#20)
- Widgets (#31)
- iMessage App (#32)

### Future Vision (Ambitious, Long-term)
- Taste-based discovery (#36)
- Community layer (#30)
- Export & print (#35)
- App Clip for guides (#33)
- Predictive trip suggestions (#39)
