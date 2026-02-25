# Bottom Card Drag Jitter — Resolved

**Status**: ✅ Fixed Feb 2026
**File**: `sonder/sonder/Views/Map/UnifiedBottomCard.swift`
**Parent**: `sonder/sonder/Views/Map/ExploreMapView.swift`

---

## The Bug

`UnifiedBottomCard` (Explore tab) stuttered/jittered during slow, deliberate drags to expand or collapse. Fast flicks were fine — the spring animation took over quickly enough. Only sustained slow drags produced visible frame drops.

---

## What the Card Does

A custom SwiftUI overlay (not a native sheet) with drag-to-resize:

- **Compact**: ~120pt tall — place name, photo thumbnail, rating
- **Expanded**: 50–75% of screen height — photo gallery, timeline entries, buttons
- **Three content variants** depending on pin type: `.personal`, `.friends`, `.combined`
- **Drag gesture**: updates `@State dragTranslation` each frame → recomputes display height → positions the card

---

## Attempted Fixes (All Implemented, None Sufficient)

The following fixes were applied one by one. Each improved things marginally but the jitter remained.

### 1. Freeze `showExpandedContent` during drag

`showExpandedContent` originally flipped at 30% drag progress, mass-inserting the photo gallery, timeline, and other expanded views mid-drag. Fixed with a `@State frozenShowExpanded` captured at drag start:

```swift
private var showExpandedContent: Bool {
    if isDragging { return frozenShowExpanded }
    return isExpandedState
}
```

Content now only transitions on snap. **Still jittered.**

### 2. Deterministic `GalleryPhoto` IDs

`GalleryPhoto` originally used `let id = UUID()`, generating new identities every frame and causing `ForEach` to destroy and recreate all gallery cells 60×/s. Fixed by using `"user-\(log.id)"` / `"friend-\(item.id)"` as stable IDs. **Still jittered.**

### 3. `.compositingGroup()` before shadows

Two `.shadow()` modifiers without `.compositingGroup()` caused the GPU to shadow each sub-layer independently. Added `.compositingGroup()` between `.clipShape()` and the shadow modifiers. **Still jittered.**

### 4. Cached content arrays

Gallery photos and timeline entries were being rebuilt on every `body` evaluation. Moved to `@State` arrays (`userGalleryPhotos`, `friendGalleryPhotos`, `userTimelineEntries`, `friendTimelineEntries`) rebuilt only on `onAppear` and `onChange(of: pin.id)`. **Still jittered.**

### 5. Frozen heights + dual-frame approach

Added `frozenCompactHeight` and `frozenExpandedHeight` captured at drag start. Used a dual-frame system to keep the inner content stable while the outer frame clipped to `displayHeight`:

```swift
.frame(height: stableContentHeight, alignment: .top)   // inner: stable
.frame(height: isDragging ? displayHeight : stableContentHeight, alignment: .top)  // outer: clips
```

Intent: only the outer clip changes each frame. **Still jittered.**

---

## Root Cause (The Real Problem)

After all the above fixes were in place, every drag frame still called SwiftUI's layout engine and changed the card's **`CALayer` bounds** via the outer `.frame(height: displayHeight)` modifier.

**When `CALayer.bounds` changes, Core Animation cannot reuse the cached render.** It must fully re-render the composited layer — including recomputing both Gaussian shadow blurs (radius 12pt and 8pt). Gaussian blur is O(shadow_area) of GPU work. With bounds changing 60×/s during a sustained slow drag, this consistently exceeded the 16ms frame budget → dropped frames → jitter.

Fast flicks didn't exhibit this because the gesture ended before enough frames dropped to be perceptible. Slow drags held the GPU in this expensive per-frame re-render loop for the entire duration.

This is a fundamental incompatibility between **bounds-resizing** and **shadow rendering** in Core Animation. No amount of SwiftUI-level content caching can fix it, because the bottleneck is below SwiftUI — it's at the CALayer compositing level.

---

## The Fix: Transform-Based Positioning

**Replace bounds-resizing with a transform (offset).**

Instead of changing the card's frame height every drag frame, keep the frame at a fixed `expandedHeight` always. Control what's visible by offsetting the card's Y position. When only the transform changes, Core Animation moves the already-rendered layer without touching the render pipeline. Shadows are computed **once** when the card appears and cached until it disappears.

This is exactly how UIKit's native `UISheetPresentationController` achieves butter-smooth drag.

### What changed in `UnifiedBottomCard.swift`

**Removed:**
- `stableContentHeight` — no longer needed
- `dismissOffset` — subsumed into `cardYOffset`
- The dual `.frame()` modifiers

**Added:**

```swift
/// Y-offset that positions the card without changing its bounds.
/// Card frame is always expandedHeight tall. In compact state the card
/// sits mostly below the screen; in expanded state it's fully visible.
/// During drag only this offset changes — layer bounds stay fixed so
/// Core Animation never re-renders shadows or runs layout passes.
private var cardYOffset: CGFloat {
    let expandedH = isDragging ? frozenExpandedHeight : expandedHeight
    let compactH  = isDragging ? frozenCompactHeight  : (compactHeight > 0 ? compactHeight : 120)

    let baseOffset: CGFloat
    if isDragging {
        baseOffset = expandedH - displayHeight
    } else if isExpandedState {
        baseOffset = 0
    } else {
        baseOffset = expandedH - compactH
    }

    // Dismiss: when dragging down from compact, slide card further off-screen.
    let dismissExtra: CGFloat = (!isExpandedState && dragTranslation > 0) ? dragTranslation : 0
    return baseOffset + dismissExtra
}

private var dismissOpacity: Double {
    let d: CGFloat = (!isExpandedState && dragTranslation > 0) ? dragTranslation : 0
    return Double(d > 100 ? max(0, 1 - (d - 100) / 80) : 1)
}
```

**Changed frame modifiers in `body`:**

```swift
// Before:
.frame(height: stableContentHeight, alignment: .top)
.frame(height: isDragging ? displayHeight : stableContentHeight, alignment: .top)
.padding(.bottom, edgeInset)
.offset(y: dismissOffset)
.opacity(Double(dismissOffset > 100 ? max(0, 1 - (dismissOffset - 100) / 80) : 1))

// After:
.frame(height: expandedHeight, alignment: .top)   // ← fixed, never changes during drag
.offset(y: cardYOffset)                            // ← transform only, zero GPU cost
.opacity(dismissOpacity)
```

### Positioning logic

| State | `cardYOffset` | Visible area |
|-------|--------------|--------------|
| Compact (at rest) | `expandedH − compactH` | Top `compactH` px of card |
| Expanded (at rest) | `0` | Full card |
| Dragging up from compact | `expandedH − displayHeight` (decreasing) | Growing smoothly |
| Dragging down from expanded | `expandedH − displayHeight` (increasing) | Shrinking smoothly |
| Dismiss drag (compact, down) | `expandedH − compactH + dragTranslation` | Card slides off-screen |

---

## Why This Works

- **No layout recalculation per frame**: `expandedHeight` is fixed, so the VStack, ScrollView, and all content have stable size proposals every frame during drag.
- **No shadow re-render per frame**: `CALayer.bounds` never changes during drag. The composited layer (including both shadow blurs) is computed once on appear and reused every frame.
- **Only a transform updates**: `offset(y:)` maps to a `CALayer.transform` translation. This is handled entirely by the GPU compositing stage — it's a matrix multiply on an already-rendered texture. Essentially free.
- **Content still freezes correctly**: `frozenShowExpanded`, cached content arrays, and the GeometryReader guard (`if !isDragging`) all remain in place and still do their job.

---

---

## Follow-on Bug: Map Not Tappable Behind Compact Card

**Discovered**: Feb 2026
**Status**: ✅ Fixed

### The Bug

After the transform-based fix, the map was unresponsive to taps in a large area above the visible compact card — roughly half the screen.

### Root Cause

SwiftUI's `.offset()` moves the **visual rendering** but does **not** move the **layout frame**. Hit-testing in SwiftUI uses the layout frame, not the visual position. With the card's fixed `.frame(height: expandedHeight)` anchored to the screen bottom (via `alignment: .bottom` on the overlay), the layout frame occupied `expandedHeight` of the screen from the bottom — even in compact state where only the top `compactHeight` was visually visible. Two `contentShape(Rectangle())` calls claimed this entire layout frame, so touches in `screenHeight − expandedHeight` to `screenHeight − compactHeight` were consumed by the card even though nothing visual was there.

### The Fix

Restrict `contentShape` to the **bottom `max(compactHeight, 120)` pt** of the layout frame in compact/non-dragging state. Because the layout frame is anchored to the screen bottom, the bottom slice of the layout frame corresponds exactly to where the compact card is visually rendered:

```swift
// Outer card (was: .contentShape(Rectangle()))
.contentShape(
    Path(CGRect(
        x: 0,
        y: (isExpandedState || isDragging) ? 0 : expandedHeight - max(compactHeight, 120),
        width: 10000,
        height: (isExpandedState || isDragging) ? expandedHeight : max(compactHeight, 120)
    ))
)

// Compact drag overlay (was: Color.clear.contentShape(Rectangle()))
Color.clear
    .contentShape(
        Path(CGRect(
            x: 0,
            y: expandedHeight - max(compactHeight, 120),
            width: 10000,
            height: max(compactHeight, 120)
        ))
    )
    .gesture(cardDragGesture)
```

In expanded or dragging state, the full `Rectangle()` is restored (via `y: 0, height: expandedHeight`) so nothing changes for those interactions.

### Key Principle

> **SwiftUI `.offset()` does not move the hit-test area.** Only the visual rendering shifts. For any view that uses offset-based positioning, `contentShape` must be manually restricted to match the visual position, not the layout frame.

---

## Key Principle for Future Custom Sheets

> **Never drive drag animations by changing view bounds.** Shadow-bearing views that resize each frame will always jitter because Core Animation cannot cache shadow blurs across bounds changes.
>
> Use `offset(y:)` or `scaleEffect` instead. Keep frames fixed. Let transforms do the motion.
>
> And remember: **`.offset()` does not move the hit-test area** — restrict `contentShape` explicitly to the visible region.
