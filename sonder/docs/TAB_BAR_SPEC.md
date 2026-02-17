# Tab Bar (SonderTabBar) Specification

## File
`sonder/Views/Main/MainTabView.swift`

## Architecture

The tab bar uses `safeAreaInset(edge: .bottom)` on the main ZStack so scroll views automatically inset their content. The icons are visually pushed into the device safe area using `.offset(y:)`.

### Why offset instead of overlay?
- `safeAreaInset` constrains its content **above** the device safe area (~34pt on Face ID iPhones). Icons can never enter the safe area zone through padding alone.
- `.overlay(alignment: .bottom)` anchors at the safe area boundary too — `.ignoresSafeArea` on the child extends it downward but doesn't move the anchor point, so icons stay in the same position.
- `.offset(y:)` on the icon HStack is a **visual-only** shift. It moves the rendered icons into the safe area without changing the layout frame. The background (which has `.ignoresSafeArea(edges: .bottom)`) already fills to the screen edge, so the icons render over the existing material.

## Layout

```
┌─────────────────────────────┐
│  Content (ScrollView etc.)  │
│  ↕ inset by safeAreaInset   │
├─────────────────────────────┤ ← tab bar frame top
│  top padding: 4pt (xxs)     │
│  ┌─────────────────────────┐│
│  │ Icons (HStack)     46pt ││ ← visually offset 16pt down
│  │  icon frame: 30pt       ││
│  │  spacing: 4pt (xxs)     ││
│  │  label: ~12pt            ││
│  └─────────────────────────┘│
│  bottom padding: 4pt (xxs)  │
├─────────────────────────────┤ ← safe area boundary (~34pt from bottom)
│  Background material only   │ ← .ignoresSafeArea(edges: .bottom)
│  (cream + ultraThinMaterial)│
├─────────────────────────────┤
│  Home indicator (~5pt)      │
└─────────────────────────────┘ ← screen bottom
```

## Key Values

| Property | Value | Notes |
|----------|-------|-------|
| Top padding | `SonderSpacing.xxs` (4pt) | Above icons |
| Bottom padding | `SonderSpacing.xxs` (4pt) | Below icons (within frame) |
| Icon offset | `offset(y: 16)` | Pushes icons 16pt into safe area |
| Log button offset | `offset(y: -16)` | Floats above bar (net 0pt from original frame) |
| Gradient fade | 24pt tall, `offset(y: -24)` | Dissolves content into bar |
| Background | `.ignoresSafeArea(edges: .bottom)` | Extends material to screen edge |

## Tabs

| Index | Icon | Label |
|-------|------|-------|
| 0 | `bubble.left.and.bubble.right` | Feed |
| 1 | `safari` | Explore |
| — | `plus` (circle) | Log (fullScreenCover) |
| 2 | `book.closed` | Journal |
| 3 | `person` | Profile |

## Selection Animation
- `matchedGeometryEffect` capsule pill slides between tabs
- Spring animation: `response: 0.3, dampingFraction: 0.8`
- Selected icons use `.fill` variant + terracotta color
- Unselected icons use `SonderColors.inkLight`

## Common Pitfalls

1. **Do NOT add `.padding(.bottom, X)` to individual tab content views** — `safeAreaInset` already handles content inset. Extra bottom padding creates dead space.
2. **Do NOT use overlay approach** — `.overlay(alignment: .bottom)` anchors at the safe area, not the screen edge. `ignoresSafeArea` on the child doesn't change the anchor.
3. **The offset is visual only** — it doesn't change the layout frame. The `safeAreaInset` height is based on the un-offset frame, which is correct for content inset.
4. **Lazy tab loading** — `loadedTabs: Set<Int>` ensures tabs are only mounted on first visit. Once mounted, they stay alive (opacity-toggled). This means `.task` only runs once per tab lifetime.
