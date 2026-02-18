# Bottom Card: Architecture & Lessons Learned

This document covers the Explore map's bottom preview card (`UnifiedBottomCard`), the problems encountered during development, the failed approaches, and the final working solution. Reference this if the card's drag behavior, sizing, or presentation regresses.

---

## Files Involved

- `sonder/Views/Map/UnifiedBottomCard.swift` — the card component
- `sonder/Views/Map/ExploreMapView.swift` — the host view that presents the card

---

## Final Architecture: Custom Overlay with Live Drag Tracking

The card is presented as a **SwiftUI `.overlay(alignment: .bottom)`** on the map, NOT a `.sheet()`. It uses a custom `DragGesture` with carefully constrained state to provide live height interpolation during drag without glitchiness.

### Why Not `.sheet()`?

We initially used `.sheet(item:)` + `.presentationDetents()` + `.presentationBackground(.clear)`. This failed for two reasons:

1. **White container behind floating card**: `.presentationBackground(.clear)` only clears the `UIHostingController.view.backgroundColor`. The system's private UIKit views (`UIDropShadowView`, `_UISheetContainerView`) managed by `UISheetPresentationController` retain their own opaque white backgrounds. We tried a `ClearSheetBackground` UIViewRepresentable that traversed the view hierarchy to clear backgrounds — it did not work reliably because the private views are recreated by the sheet controller at unpredictable times.

2. **Sheet controller instability**: Multiple issues with `.sheet()` caused the card to randomly expand to full screen or get stuck:
   - `.sheet(item:)` reuses the view when the item changes without dismissing/re-presenting, so `@State selectedDetent` persists from the previous pin
   - `.animation()` on content VStacks conflicts with the sheet controller's own layout animation
   - `GeometryReader` → `@State` → layout change → `GeometryReader` fires again creates a feedback loop that destabilizes detent computation

### Presentation: Overlay Instead of Sheet

**ExploreMapView.swift** presents the card via overlay:

```swift
.overlay(alignment: .bottom) {
    if let pin = sheetPin {
        UnifiedBottomCard(
            pin: pin,
            onDismiss: { clearSelection() },
            onNavigateToLog: { ... },
            onExpandedChanged: { expanded in
                cardIsExpanded = expanded
                recenterForCardState(coordinate: pin.coordinate, expanded: expanded)
            }
        )
        .id(pin.id)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
.animation(.smooth(duration: 0.25), value: sheetPin?.id)
```

Key details:
- **`.id(pin.id)`** forces a fresh view per pin, resetting all `@State` (expanded, drag, compact height). This is safe here because there's no UIKit sheet controller to get out of sync.
- **`.transition()`** provides enter/exit animation when `sheetPin` changes from nil to a value or vice versa.
- **`.animation(.smooth, value: sheetPin?.id)`** animates the transition when switching between pins or dismissing.
- **`sheetPin` is set directly** in `onChange(of: mapSelection)` — no `pendingSheetPin` or two-phase presentation needed.
- **Removed state**: `sheetDetent`, `pendingSheetPin`, and `handleUnifiedSheetDismiss()` are all gone.

### State Design: Minimal `@State`, Derived Everything Else

The card has exactly **four** `@State` variables:

```swift
@State private var isExpandedState = false      // true when snapped to expanded
@State private var dragTranslation: CGFloat = 0 // live finger offset during drag
@State private var compactHeight: CGFloat = 0   // measured once from content
@State private var scrollCooldown = false        // prevents rapid scroll-triggered expand/collapse
```

Everything else is a **computed property** derived from these three values:

```swift
private var isExpanded: Bool { isExpandedState }
private var isDragging: Bool { dragTranslation != 0 }

// Height during drag — interpolates between compact and expanded
private var displayHeight: CGFloat {
    let baseCompact = compactHeight > 0 ? compactHeight : 120
    if isExpandedState {
        // Dragging down from expanded shrinks toward compact
        let h = expandedHeight - dragTranslation  // positive translation = drag down
        return max(baseCompact, min(expandedHeight, h))
    } else {
        // Dragging up from compact grows toward expanded
        let h = baseCompact - dragTranslation  // negative translation = drag up
        return max(baseCompact, min(expandedHeight, h))
    }
}

// Offset for dismiss gesture (drag down from compact)
private var dismissOffset: CGFloat {
    if !isExpandedState && dragTranslation > 0 { return dragTranslation }
    return 0
}

// 0 = compact, 1 = expanded — used to interpolate visual properties
private var dragProgress: CGFloat {
    let baseCompact = compactHeight > 0 ? compactHeight : 120
    let range = expandedHeight - baseCompact
    guard range > 0 else { return isExpandedState ? 1 : 0 }
    return (displayHeight - baseCompact) / range
}

// Edge inset interpolates: 10pt at compact, 0pt at expanded
private var edgeInset: CGFloat { 10 * (1 - dragProgress) }

// Expanded height = 50% of screen
private var expandedHeight: CGFloat { UIScreen.main.bounds.height * 0.5 }
```

### Compact Height Measurement: One-Shot PreferenceKey

The compact height is measured **once** using a `PreferenceKey`, NOT via a continuously-firing `GeometryReader`:

```swift
cardContent
    .background(
        GeometryReader { geo in
            Color.clear.preference(key: CompactHeightKey.self, value: geo.size.height + 17)
        }
    )
```

The `+17` accounts for the drag indicator capsule (5pt) + its padding (6pt top + 2pt bottom) + the content's top padding (4pt from spacing).

The preference is only consumed when NOT expanded and NOT dragging:

```swift
.onPreferenceChange(CompactHeightKey.self) { value in
    if value > 0 && !isExpandedState && !isDragging {
        compactHeight = value
    }
}
```

This prevents the GeometryReader feedback loop: expanded content is taller than compact content, so if we measured during expanded state, it would set `compactHeight` too large, causing white space when collapsed.

### Frame Height Logic

```swift
.frame(height: isDragging ? displayHeight : (isExpanded ? expandedHeight : (compactHeight > 0 ? compactHeight : 120)), alignment: .top)
```

Three states:
1. **Compact, not dragging**: `height: compactHeight` (or 120 fallback) — explicit height required because ScrollView is greedy in overlay
2. **Expanded, not dragging**: `height: expandedHeight` — fixed at 50% screen
3. **Dragging (either direction)**: `height: displayHeight` — interpolated between compact and expanded based on finger position

The `.alignment: .top` ensures content stays pinned to the top as the card grows/shrinks.

### ScrollView: Always Present, Conditionally Enabled

Content is always wrapped in a `ScrollView`, but scroll is **disabled** when compact or dragging:

```swift
ScrollView {
    cardContent
        .padding(...)
        .background(GeometryReader { ... }) // compact height measurement
}
.scrollBounceBehavior(.basedOnSize)
.scrollDisabled(!isExpanded || isDragging)
.onScrollGeometryChange(for: CGFloat.self) { geo in
    geo.contentOffset.y
} action: { _, offset in
    handleScrollOffset(offset)
}
```

**Why always present**: Two-finger trackpad scroll in iPhone Mirroring generates scroll events that only `ScrollView` can capture. `DragGesture` does not respond to scroll wheel / two-finger trackpad events. Without a ScrollView, two-finger scroll does nothing.

**Why disabled when compact**: When scroll is disabled, `ScrollView` does not intercept touch gestures, so our `DragGesture` on the outer container fires normally for touch-based expand/dismiss. This avoids the chicken-and-egg problem where ScrollView captures the gesture before `isDragging` becomes true.

**Why disabled when dragging**: Prevents ScrollView from fighting with our live drag resize. Once `isDragging` is true, all gesture handling is done by `DragGesture`.

**Scroll-based collapse** (for two-finger trackpad): When expanded, `.onScrollGeometryChange` detects top-overscroll (user scrolls past the top of content). If `contentOffset.y < -30`, we collapse with a spring animation. A `scrollCooldown` flag (500ms) prevents the stale offset from immediately re-triggering expand.

**Compact frame height**: Because ScrollView is greedy (expands to fill available space in overlay), the compact state uses an explicit height (`compactHeight > 0 ? compactHeight : 120`) instead of `nil`. The `compactHeight` is measured on first layout via `PreferenceKey`; `120` is a brief fallback before the real measurement arrives.

```swift
.frame(height: isDragging ? displayHeight : (isExpanded ? expandedHeight : (compactHeight > 0 ? compactHeight : 120)), alignment: .top)
```

### Drag Gesture: Live `onChanged` + Snap `onEnded`

```swift
private var cardDragGesture: some Gesture {
    DragGesture(minimumDistance: 10)
        .onChanged { value in
            dragTranslation = value.translation.height
        }
        .onEnded { value in
            let ty = value.translation.height
            let predicted = value.predictedEndTranslation.height

            if isExpandedState {
                if ty > 60 || predicted > 150 {
                    // Collapse
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isExpandedState = false
                        dragTranslation = 0
                    }
                } else {
                    // Snap back to expanded
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dragTranslation = 0
                    }
                }
            } else {
                if ty < -25 || predicted < -120 {
                    // Expand
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isExpandedState = true
                        dragTranslation = 0
                    }
                } else if ty > 50 || predicted > 120 {
                    // Dismiss
                    onDismiss()
                } else {
                    // Snap back to compact
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        dragTranslation = 0
                    }
                }
            }
        }
}
```

Key details:
- **`onChanged`** updates `dragTranslation` every frame — this drives `displayHeight`, which makes the card grow/shrink live with the finger.
- **`onEnded`** uses `withAnimation(.spring(...))` to animate the snap. Both `isExpandedState` and `dragTranslation` are set **inside the same `withAnimation` block** so they animate together.
- **No `.animation()` modifier** on the view — this is critical. An `.animation()` modifier would cause every per-frame `dragTranslation` update to be animated, creating compounding spring animations (glitchy). Only the `onEnded` transition is animated.
- **`predictedEndTranslation`** gives velocity-aware thresholds so flicks feel natural.

### Dismiss Gesture (Compact + Drag Down)

When compact and dragging down, the card doesn't shrink (it's already at minimum height). Instead, it offsets downward and fades:

```swift
.offset(y: dismissOffset)
.opacity(Double(dismissOffset > 100 ? max(0, 1 - (dismissOffset - 100) / 80) : 1))
```

If the drag exceeds 50pt (or predicted > 120pt), `onDismiss()` fires.

### Visual Property Interpolation via `dragProgress`

`dragProgress` (0 = compact, 1 = expanded) drives smooth interpolation of:

- **Edge inset**: `10 * (1 - dragProgress)` — 10pt (floating) at compact, 0pt (full-width) at expanded
- **Shadow**: `opacity(dragProgress < 0.5 ? 0.12 : 0)` — shadow visible in compact half, fades in expanded half
- **Content visibility**: `if showExpandedContent { ... }` gates expanded-only content — appears at 30% drag progress during drag-up, not just after snap
- **Compact thumbnail opacity**: `1 - dragProgress` — smoothly fades as card expands

### Expanded Content During Drag (`showExpandedContent`)

```swift
private var showExpandedContent: Bool { isExpandedState || dragProgress > 0.3 }
```

Content methods (`personalContent`, `friendsContent`, `combinedContent`) gate their detail sections on `showExpandedContent` instead of `isExpanded`. This means hero images, notes, ratings, etc. appear as the user drags up (at ~30% of the way to expanded), giving visual feedback that more content is loading in. Without this, the card would grow during drag but show only the compact header until release.

---

## Problems Encountered and How They Were Solved

### Problem 1: White Container Behind Floating Card

**Symptom**: Even with `.presentationBackground(.clear)`, a white rectangle was visible behind the card.

**Root cause**: `UISheetPresentationController` manages private UIKit views (`UIDropShadowView`, `_UISheetContainerView`) that have their own opaque backgrounds, separate from the hosting controller's background.

**Failed fix**: `ClearSheetBackground` UIViewRepresentable that traversed the view hierarchy in `didMoveToWindow()` and `layoutSubviews()` to set every ancestor view's background to `.clear`. This didn't work because the private views are managed by the sheet controller and can be recreated.

**Solution**: Replaced `.sheet()` with `.overlay(alignment: .bottom)`. Full control over the card's background — no UIKit containers involved.

### Problem 2: Card Filled Entire Screen in Overlay

**Symptom**: After switching to overlay, tapping a pin made a card that covered the entire screen.

**Root cause**: `ScrollView` inside the overlay expanded to fill all available space (the overlay gives its content the full screen height).

**Solution**: Used conditional content — `ScrollView` only when expanded, plain `VStack` when compact. Later removed `ScrollView` entirely (see Problem 6).

### Problem 3: Card Didn't Follow Finger During Drag

**Symptom**: Card only changed size when the finger was released, not during the drag.

**Root cause**: The initial implementation only used `onEnded` (snap-on-release), with no `onChanged` handler.

**Solution**: Added `onChanged` to update `@State dragTranslation` every frame, and computed `displayHeight` from it.

### Problem 4: `Group { if/else }` Broke Gesture Mid-Drag

**Symptom**: First drag only partially expanded the card. Subsequent drags worked.

**Root cause**: Using `Group { if isExpanded { ... } else { ... } }` to switch between fixed-height and content-driven sizing changed the SwiftUI view identity mid-drag, which reset the active `DragGesture`.

**Solution**: Always apply `.frame(height: ...)` — use `nil` for content-driven height when compact and not dragging, `displayHeight` when dragging, `expandedHeight` when expanded. No view identity changes.

### Problem 5: Extra White Space in Compact Card

**Symptom**: The compact card had visible white space above and below the content.

**Root cause**: Using a fixed `compactBaseHeight = 120` that was larger than the actual content height (~100pt). Also, the GeometryReader was measuring expanded content height and storing it as compact height.

**Solution**: Measure compact height via `PreferenceKey`, only update when `!isExpandedState && !isDragging`. Use `nil` height (content-driven) when compact and not dragging.

### Problem 6: Drag-Down From Expanded Didn't Live-Track

**Symptom**: Dragging down from expanded state — the card collapsed only on release, not during the drag.

**Root cause**: `ScrollView`'s internal gesture recognizer captured the drag gesture before our `DragGesture` could fire. Even with `.scrollDisabled(isDragging)`, the ScrollView captured the gesture on the first frame (before `isDragging` became true).

**Solution**: Removed `ScrollView` entirely. Content is in a plain `VStack` with `.clipShape()` for overflow. No gesture conflicts.

### Problem 7: Instant Width Shrink on Drag Start

**Symptom**: Starting a drag from expanded state caused the card to instantly snap narrower.

**Root cause**: `edgeInset` was computed as `isExpanded && !isDragging ? 0 : 10`. The moment `isDragging` became true, `edgeInset` jumped from 0 to 10, shrinking the card width by 20pt instantly.

**Solution**: Interpolate edge inset based on `dragProgress`: `10 * (1 - dragProgress)`. Width transitions smoothly as the card height changes.

### Problem 8: Drag Direction Sign Error

**Symptom**: Dragging down from expanded made the card try to grow taller instead of shrinking.

**Root cause**: `displayHeight` used `expandedHeight + dragTranslation` for the expanded state. Since dragging down produces a positive `dragTranslation`, this increased the height. Should have been `expandedHeight - dragTranslation`.

**Solution**: Fixed the sign: `expandedHeight - dragTranslation` (positive translation = drag down = shrink).

### Problem 9: ScrollView Expanded Compact Card to Full Screen

**Symptom**: After adding always-present ScrollView, tapping a pin showed a card covering the entire screen.

**Root cause**: ScrollView is a greedy view — it expands to fill all available space. In the overlay, that's the full screen. When the compact frame height was `nil` (content-driven), the VStack deferred to ScrollView, which took the full screen.

**Solution**: Always use an explicit compact height: `compactHeight > 0 ? compactHeight : 120`. The `compactHeight` is measured via PreferenceKey on first layout; `120` is a brief fallback.

### Problem 10: `.simultaneousGesture` + `.scrollBounceBehavior(.always)` Caused Glitchiness

**Symptom**: Drag interactions became glitchy again after adding ScrollView with `.simultaneousGesture` and `.scrollBounceBehavior(.always)`.

**Root cause**: `.simultaneousGesture` means both ScrollView's gesture and our DragGesture fire at the same time. When compact with `.scrollBounceBehavior(.always)`, the ScrollView rubber-bands while our DragGesture resizes the card — dual behavior on the same touch event causes visual jitter.

**Failed fix**: Using `.simultaneousGesture` with `isDragging` guard on scroll — timing issues meant both fired on the first frame.

**Solution**:
1. Reverted to `.gesture()` (not `.simultaneousGesture()`) — DragGesture only fires when ScrollView doesn't consume the gesture.
2. `.scrollDisabled(!isExpanded || isDragging)` — scroll disabled when compact (so DragGesture captures all touch drags) and during active drag.
3. `.scrollBounceBehavior(.basedOnSize)` always — no forced bounce.

This means: when compact, scroll is disabled, so DragGesture handles all touches for live resize. When expanded, scroll is enabled for content browsing, and DragGesture fires on the capsule handle (which is outside the ScrollView) for collapse.

### Problem 11: Card Disappeared on Collapse Instead of Returning to Compact

**Symptom**: Collapsing the expanded card via scroll overscroll made the card vanish entirely instead of animating to the compact state.

**Root cause**: `onScrollGeometryChange` fired with `offset < -20`, triggering collapse (`isExpandedState = false`). But the stale scroll offset was still negative, so on the next evaluation, `!isExpandedState && abs(offset) > 20` triggered immediate re-expand. This rapid collapse→expand→collapse cycle made the card appear to vanish.

**Solution**: Added a `scrollCooldown` flag that blocks `handleScrollOffset` for 500ms after any scroll-triggered state change:

```swift
@State private var scrollCooldown = false

private func handleScrollOffset(_ offset: CGFloat) {
    guard !isDragging, !scrollCooldown else { return }
    if isExpandedState && offset < -30 {
        scrollCooldown = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isExpandedState = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            scrollCooldown = false
        }
    }
}
```

Additionally, `.scrollDisabled(!isExpanded || isDragging)` means scroll is immediately disabled after collapse (`isExpanded = false`), cutting off further offset events.

---

## What NOT to Do

1. **Don't use `.sheet()` if you need a floating card with transparent background** — `UISheetPresentationController`'s private views cannot be reliably cleared.
2. **Don't use `.simultaneousGesture()` with ScrollView** — both gestures fire on the same touch, causing dual scroll+resize behavior (jitter). Use `.gesture()` so the DragGesture only fires when ScrollView doesn't consume the touch.
3. **Don't use `.scrollBounceBehavior(.always)` on a draggable card** — forced bounce when content fits causes ScrollView to compete with DragGesture for touch events. Use `.basedOnSize` and disable scroll when compact.
4. **Don't use `.animation()` modifier with per-frame state updates** — it causes every `onChanged` update to spawn a new spring animation, creating compounding jitter. Only animate in `onEnded` via explicit `withAnimation`.
5. **Don't use `GeometryReader` in a feedback loop** — measuring height → setting state → changing layout → measuring again creates infinite re-evaluation. Measure once with a `PreferenceKey` and guard the update.
6. **Don't use `Group { if/else }` during active gestures** — it changes SwiftUI view identity, which resets the gesture recognizer mid-drag.
7. **Don't use binary state for visual properties that should interpolate** — e.g., `edgeInset = isExpanded ? 0 : 10` causes instant jumps. Use `dragProgress` to interpolate.
8. **Don't set `compactHeight` from expanded content** — only measure when the card is actually in compact state, or you'll get white space.
9. **Don't use `nil` frame height with ScrollView in overlay** — ScrollView is greedy and will expand to fill the entire overlay. Always provide an explicit height.
10. **Don't handle scroll-based state changes without a cooldown** — `onScrollGeometryChange` can fire multiple times with stale offsets during animation, causing rapid expand/collapse cycles that make the card vanish.

---

## Quick Reference: State → Visual Mapping

| State | `isDragging` | `isExpanded` | Frame Height | Edge Inset | Scroll | Content |
|-------|-------------|-------------|-------------|-----------|--------|---------|
| Compact, idle | false | false | `compactHeight` (explicit) | 10pt | Disabled | Compact header only |
| Compact, dragging up | true | false | `displayHeight` (growing) | Interpolating → 0 | Disabled | Compact + expanded appearing at 30% |
| Expanded, idle | false | true | `expandedHeight` (50%) | 0pt | Enabled | Full detail, scrollable |
| Expanded, dragging down | true | true | `displayHeight` (shrinking) | Interpolating → 10 | Disabled | Full detail, clipped |
| Compact, dragging down | true | false | compact (no shrink) | 10pt | Disabled | Compact + offset + fade |

## Gesture Routing Summary

| Input | Compact State | Expanded State |
|-------|--------------|----------------|
| Touch drag (anywhere) | `DragGesture` → live resize (scroll disabled) | ScrollView scrolls content |
| Touch drag (capsule handle) | `DragGesture` → live resize | `DragGesture` → live collapse |
| Two-finger trackpad scroll | Not captured (scroll disabled) | `onScrollGeometryChange` → snap collapse on top-overscroll |
| Touch drag down from compact | `DragGesture` → dismiss offset + fade | N/A |
