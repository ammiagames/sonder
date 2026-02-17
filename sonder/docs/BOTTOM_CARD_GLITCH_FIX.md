# Bottom Card Glitch Fix

## Problem 1: Drag Glitchiness
Custom `DragGesture` + `@State` height tracking for bottom cards causes visible glitchiness (jittering, frame drops) during drag interactions because:

1. **Per-frame state updates**: `DragGesture.onChanged` fires every frame, updating `@State var cardHeight`, which triggers a full SwiftUI view re-evaluation each frame
2. **Layout feedback loops**: Using `GeometryReader` to measure content height while also using that measurement to set the card height creates circular dependencies
3. **Computed property chains**: Properties derived from `cardHeight` (like `progress`, opacity values, etc.) all recalculate per-frame, compounding the cost

## Problem 2: Sheet Goes Full Screen Randomly
The sheet sometimes expands to full screen (beyond defined detents) and becomes stuck. Three causes:

1. **Stale `@State` when switching pins**: `.sheet(item:)` reuses the view when the item changes (doesn't dismiss/re-present). `@State selectedDetent` persists from the previous pin's expanded state.
2. **`.animation()` on content VStacks**: Animated layout changes (views inserting/removing via `if isExpanded`) conflict with the sheet controller's own layout/animation, destabilizing detent computation.
3. **`GeometryReader` feedback loop**: Using `GeometryReader` → `@State dragProgress` → layout changes → `GeometryReader` fires again creates a feedback loop that re-applies `.presentationDetents()` every frame, destabilizing the sheet controller.

## Solution: Native Sheet + Detent-Based State

Replace custom drag with SwiftUI's native `.sheet()` + `.presentationDetents()`, which uses UIKit's `UISheetPresentationController` (60/120fps compositor thread).

### Key Architecture

```swift
struct BottomCard: View {
    @State private var selectedDetent: PresentationDetent = .height(120)

    private static let compactDetent: PresentationDetent = .height(120)
    private static let expandedDetent: PresentationDetent = .fraction(0.65)

    private var isExpanded: Bool {
        selectedDetent != Self.compactDetent
    }

    var body: some View {
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(!isExpanded)
        .presentationDetents([Self.compactDetent, Self.expandedDetent], selection: $selectedDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: Self.compactDetent))
        .presentationDragIndicator(.visible)
    }
}
```

### Critical: Pin-Aware Detent Binding

**Do NOT use `.id(pin.id)` or `.onChange(of: pin.id)`** — neither works because:
- `.id()` recreates the SwiftUI view but NOT the UIKit sheet controller
- `.onChange()` fires AFTER the body evaluation, so the sheet controller already committed to the stale detent

Instead, track *which pin* is expanded and derive the detent synchronously:

```swift
@State private var expandedPinID: String?

private var isExpanded: Bool { expandedPinID == pin.id }

private var detentBinding: Binding<PresentationDetent> {
    Binding(
        get: { isExpanded ? Self.expandedDetent : Self.compactDetent },
        set: { newDetent in
            expandedPinID = (newDetent == Self.expandedDetent) ? pin.id : nil
        }
    )
}
```

When the pin changes from A→B, `expandedPinID` is still "A", so `isExpanded` = `"A" == "B"` = `false`. The getter returns compact. No timing race.

### Content Gating with `if isExpanded`

```swift
// Compact: only show header
compactHeader(...)

// Expanded: show all details
if isExpanded {
    heroImage(...)
    noteText(...)
    ratingRow(...)
    // etc.
}
```

## What NOT to Do

1. **Don't use custom `DragGesture`** for bottom cards
2. **Don't use `GeometryReader` to track sheet position** — creates feedback loops with `@State`
3. **Don't use `.animation()` on content VStacks inside sheets** — layout animations conflict with the sheet controller's own animation, causing the sheet to jump to full screen
4. **Don't use `.presentationContentInteraction(.resizes)`** with ScrollView — causes the sheet to get stuck when content is shorter than the sheet
5. **Don't use `@State selectedDetent` directly** when the sheet item can change — use a pin-aware binding that derives the detent from whether *this specific pin* is expanded
6. **Don't rely on `.id(item.id)` or `.onChange(of:)` to reset detent** — both have timing issues with the sheet controller

## Modifiers Reference

- `.presentationDetents([...], selection: $selectedDetent)` — defines available heights
- `.presentationBackgroundInteraction(.enabled(upThrough: compactDetent))` — allows map interaction behind compact card
- `.scrollDisabled(!isExpanded)` — prevents ScrollView from stealing drag at compact state
- `.scrollBounceBehavior(.basedOnSize)` — only bounces if content overflows
- `.presentationDragIndicator(.visible)` — shows the grab handle
- `.id(pin.id)` — forces fresh view per item (resets @State)
