# Sonder — Load Testing & Scalability Audit

Comprehensive analysis of performance bottlenecks that will surface under heavy load (many users, logs, followers, map pins, photos).

---

## 1. SwiftData Queries — Full Table Scans

### 1.1 Unfiltered `@Query` fetches entire tables into memory

**Files:** `ExploreMapView.swift:32-33`, `TripDetailView.swift:19-20`, `JournalContainerView.swift:16-18`, `MainTabView.swift:156-158`

```swift
@Query(sort: \Log.createdAt, order: .reverse) private var allLogs: [Log]
@Query private var places: [Place]
```

Every `@Query` with no predicate loads the **entire** `logs` and `places` tables from SwiftData into memory. With 10,000 logs, every view re-render materializes 10,000 objects. The data is then filtered in Swift computed properties on the main thread:

```swift
// ExploreMapView.swift:509-512
private var personalLogs: [Log] {
    guard let userID = authService.currentUser?.id else { return [] }
    return allLogs.filter { $0.userID == userID }
}
```

This O(n) scan runs on **every SwiftUI render pass** — triggered by map camera moves, filter toggles, pin taps, etc.

**Fix:** Use `#Predicate` in `@Query` or `FetchDescriptor` to push filtering to SQLite. Only fetch the data each view actually needs.

---

### 1.2 `placesByID` dictionary rebuilt on every render (3 views)

**Files:** `JournalContainerView.swift:32-34`, `MasonryTripsGrid.swift:41-43`, `TripDetailView.swift:70-72`

```swift
private var placesByID: [String: Place] {
    Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
}
```

This is a **computed property**, not memoized. SwiftUI evaluates it on every render. With 1,000 places, each render allocates a new 1,000-entry dictionary. Three separate views do this independently.

**Fix:** Cache in `@State` and only rebuild when `places.count` changes, or share via a service.

---

### 1.3 No indexes on any `@Model` fields

`Log` has `userID`, `placeID`, `syncStatus`, and `tripID` as commonly-queried fields. None are indexed. Every predicate-based query on these fields does a **full table scan in SQLite**.

**Fix:** Add `@Attribute(.index)` (or equivalent) to frequently filtered/joined fields: `Log.userID`, `Log.placeID`, `Log.syncStatus`, `Log.tripID`, `Place.id`.

---

### 1.4 `searchCachedPlaces` fetches ALL places on every keystroke

**File:** `PlacesCacheService.swift:211-221`

```swift
func searchCachedPlaces(query: String) -> [Place] {
    let descriptor = FetchDescriptor<Place>()
    guard let places = try? modelContext.fetch(descriptor) else { return [] }
    return places.filter { place in
        place.name.lowercased().contains(lowercaseQuery) || ...
    }
}
```

Called from `SearchPlaceView` on every character typed, with no debounce on this code path. Loads all places, then does two `lowercased()` + `contains()` per place.

**Fix:** Use a SwiftData predicate with `localizedStandardContains`, or at minimum debounce the caller and add a `LIMIT`.

---

### 1.5 `recentPlaceIds` issues a SwiftData fetch on every render pass

**File:** `SearchPlaceView.swift:325-327`

```swift
private var recentPlaceIds: Set<String> {
    Set(cacheService.getRecentSearches().prefix(5).map { $0.placeId })
}
```

This computed property calls `getRecentSearches()` which runs a `FetchDescriptor<RecentSearch>` query. It's accessed in `body`, so it runs on **every render**. It's also called a second time at line 333 for the recents section.

**Fix:** Move to `@State` and refresh on appear / after search selection.

---

## 2. Map — Pins, Filtering, and Rendering

### 2.1 No pin clustering — all annotations rendered simultaneously

**File:** `ExploreMapView.swift:344-367`

```swift
ForEach(annotatedPins, id: \.identity) { item in
    unifiedPinAnnotation(item: item)
}
```

SwiftUI's `Map` with `ForEach` does **not** cluster annotations. With 500 friends' logs plus all personal logs, this can produce 200-500+ `UnifiedMapPinView` instances simultaneously, each with async image loading. At city-level zoom in a popular area, this will destroy frame rate.

**Fix:** Bridge to `MKMapView` with `MKAnnotationView.clusteringIdentifier`, or implement viewport-based filtering to only render visible pins.

---

### 2.2 `computeUnifiedPins` re-runs on every log/place count change

**File:** `ExploreMapView.swift:536-553`

Triggered by `.onChange(of: allLogs.count)` and `.onChange(of: places.count)`. Every new log synced from Supabase triggers a **full pin recomputation** — building dictionaries, merging sets, iterating all places.

**Fix:** Debounce recomputation, or use incremental updates (add/remove single pin) instead of full rebuild.

---

### 2.3 No viewport bounding — loads 500 logs from around the world

**File:** `ExploreMapService.swift:52-59`

```swift
let response: [FeedLogResponse] = try await supabase
    .from("logs")
    .select(selectQuery)
    .in("user_id", values: followingIDs)
    .limit(500)
    .execute()
    .value
```

No lat/lng bounding box filter. A user following many active travelers loads 500 logs globally regardless of the current map viewport. No mechanism to load more when panning.

**Fix:** Add a PostGIS/bounding-box filter based on the visible map region. Load pins on-demand as the user pans.

---

### 2.4 `allFriends` computed property iterates all logs on every render

**File:** `ExploreMapService.swift:106-117`

```swift
var allFriends: [FeedItem.FeedUser] {
    var seen = Set<String>()
    for place in placesMap.values {
        for item in place.logs { ... }
    }
    return result.sorted { ... }
}
```

Computed property (not cached) accessed from `ExploreMapView` body. With 500 log items across 200+ places, this iterates and sorts on **every render frame**, including every camera move.

**Fix:** Cache the result and only recompute when `placesMap` changes.

---

### 2.5 Category filter does nested string operations on all places

**File:** `ExploreMapService.swift:93-99`

```swift
let allKeywords = filter.categories.flatMap(\.keywords)
results = results.filter { place in
    let name = place.name.lowercased()
    let tags = place.logs.flatMap(\.log.tags).joined(separator: " ").lowercased()
    return allKeywords.contains { name.contains($0) || tags.contains($0) }
}
```

For each place: lowercase name, flatten all log tags, join, lowercase, then scan through all keywords. With 500 places this is expensive on every filter toggle.

**Fix:** Pre-compute lowercased searchable text when places are loaded, not on every filter.

---

### 2.6 `findPinByProximity` is a linear scan

**File:** `ExploreMapService.swift:246-261`

O(n) `filter` + `min` through all pins on every pin drop. No spatial indexing.

**Fix:** Use a spatial index (quadtree) or at minimum a bounding-box pre-filter.

---

## 3. Feed — Pagination, Redundant Queries, Unbounded Fetches

### 3.1 `getFollowingIDs` called on every feed load, every page, every subscription

**File:** `FeedService.swift:325-338`

Called at:
- `loadFeed` (line 49)
- `loadMoreFeed` (line 116) — **every** pagination page
- `subscribeToRealtimeUpdates` (line 347)
- `ExploreMapService.loadFriendsPlaces` has its own duplicate (lines 265-278)

The follows list is **never cached** between calls. Opening the app triggers 2+ separate `SELECT * FROM follows` queries.

**Fix:** Cache `followingIDs` in memory with a TTL. Invalidate on follow/unfollow.

---

### 3.2 `fetchTripFeedItems` trip-logs query has no LIMIT

**File:** `FeedService.swift:211-218`

```swift
let tripLogs: [TripLogWithTripID] = try await supabase
    .from("logs")
    .select(...)
    .in("trip_id", values: tripIDs)
    .order("created_at", ascending: false)
    .execute()
    .value
```

No `.limit()`. 50 trips with 20 logs each = 1,000 rows in one query. Power users following many travelers could trigger much more.

**Fix:** Add a reasonable `LIMIT` or fetch trip logs on-demand per trip.

---

### 3.3 `fetchUserLogs` has no LIMIT — loads entire history for profile view

**File:** `FeedService.swift:431-449`

A user with 2,000 logs gets all 2,000 returned in one query for `OtherUserProfileView`. No pagination.

**Fix:** Paginate with cursor-based pagination (e.g., `created_at < lastItem.createdAt`).

---

### 3.4 Feed initial load requires 5+ sequential network round trips

**File:** `FeedService.swift:40-107`

Sequence: (1) `getFollowingIDs` → (2) `fetchFeedLogs` → (3) fetch trips → (4) fetch trip logs → (5) fetch trip activities → (6) `fetchTripCreatedEntries`. All sequential — no parallelism between independent queries.

**Fix:** Use `async let` / `TaskGroup` for independent queries. Consider a server-side aggregation endpoint.

---

## 4. SyncEngine — Full Sync Every 30 Seconds

### 4.1 `pullRemoteLogs` fetches ALL user logs — no delta sync

**File:** `SyncEngine.swift:558-565`

```swift
let remoteLogs: [RemoteLog] = try await supabase
    .from("logs")
    .select()
    .eq("user_id", value: userID)
    .execute()
    .value
```

No `updated_at > lastSyncDate` filter. Every 30 seconds, **every log the user has ever created** is fetched, decoded, and merged. With 1,000 logs this allocates thousands of objects on the main actor every 30 seconds.

**Fix:** Add `.gt("updated_at", value: lastSyncDate)` to only pull changes since last sync.

---

### 4.2 `pullRemoteTrips` — same full-table pull pattern

**File:** `SyncEngine.swift:472-501`

Two separate Supabase queries (owned + collaborator) with no delta filtering. Full pull every 30 seconds.

---

### 4.3 `mergeRemoteLogs` fetches ALL local logs on the main actor

**File:** `SyncEngine.swift:601-616`

```swift
let localLogs = try modelContext.fetch(FetchDescriptor<Log>())
var localLogsByID: [String: Log] = [:]
```

Fetches and builds a dictionary of **all** local logs on `@MainActor`. With 10,000 logs this blocks the main thread for significant time every sync cycle.

**Fix:** Move merge logic to a background `ModelActor`. Use incremental merge (only process changed records).

---

### 4.4 Sync fires every 30s regardless of app state or data changes

**File:** `SyncEngine.swift:309-326`

No check for foreground/background state, no check for whether data has changed. A user who leaves the app open is running full Supabase pulls every 30 seconds indefinitely.

**Fix:** Pause in background. Use Supabase Realtime for push-based updates. Only pull on app foreground / after local writes.

---

### 4.5 `syncPlace` called once per pending log — no deduplication

**File:** `SyncEngine.swift:384-386`

```swift
private func uploadLog(_ log: Log) async throws {
    try await syncPlace(placeID: log.placeID)
```

10 logs at the same place = 10 separate `syncPlace` upsert API calls.

**Fix:** Collect unique place IDs first, sync each place once, then sync logs.

---

### 4.6 `syncPendingLogs` and `syncPendingTrips` fetch ALL records then filter in Swift

**File:** `SyncEngine.swift:356-359, 451-453`

```swift
let descriptor = FetchDescriptor<Log>()
let allLogs = try modelContext.fetch(descriptor)
let pendingLogs = allLogs.filter { $0.syncStatus == .pending || $0.syncStatus == .failed }
```

Full table load to find a handful of pending items. Should use a predicate.

---

## 5. Social Features — N+1 and Unbounded Queries

### 5.1 `OtherUserProfileView.loadData` — 5 sequential network calls

**File:** `OtherUserProfileView.swift:296-323`

```
1. getUser(id:)           — serial
2. isFollowingAsync(...)  — serial
3. getFollowerCount(...)  — serial (could parallel with 4)
4. getFollowingCount(...) — serial (could parallel with 3)
5. fetchUserLogs(...)     — serial, unbounded
```

**Fix:** Parallelize independent calls with `async let`. Combine count queries into a single RPC.

---

### 5.2 Follower/following lists have no LIMIT

**File:** `SocialService.swift:127-167`

```swift
let response: [FollowWithUser] = try await supabase
    .from("follows")
    .select("following_id, users!follows_following_id_fkey(*)")
    .eq("follower_id", value: userID)
    .execute()
    .value
```

A user with 10,000 followers fetches all 10,000 user records in one query. No pagination in `FollowListView`.

**Fix:** Paginate with cursor or offset.

---

### 5.3 `isFollowingAsync` makes a network call on negative cache miss

**File:** `SocialService.swift:95-122`

A negative local cache result always triggers a Supabase query. Viewing 10 unfollowed profiles = 10 network calls that could be avoided by caching the full following list.

---

### 5.4 `refreshCounts` — two serial COUNT queries

**File:** `SocialService.swift:203-207`

```swift
followerCount = await getFollowerCount(for: userID)
followingCount = await getFollowingCount(for: userID)
```

Two independent queries run sequentially. Fires after every follow/unfollow.

**Fix:** `async let` for parallelism, or a single Supabase RPC returning both counts.

---

## 6. Photo Handling — Memory and Performance

### 6.1 Image compression runs on `@MainActor` synchronously

**File:** `PhotoService.swift:166-172`

```swift
for image in images {
    guard let data = compressImage(image) else { continue }
    entries.append(...)
}
```

`compressImage` uses `UIGraphicsImageRenderer` — CPU-intensive. A 12MP photo takes 50-150ms. With 5 photos, the main thread is **blocked for up to 750ms**.

**Fix:** Move compression to a background task with `Task.detached` or an actor.

---

### 6.2 Batch photo uploads are sequential

**File:** `PhotoService.swift:184-199`

```swift
for entry in entries {
    let url = await uploadCompressedData(entry.data, for: userId)
}
```

5 photos at 300ms each = 1.5s sequential. Could be ~300ms with concurrent uploads.

**Fix:** Use `TaskGroup` for concurrent uploads.

---

### 6.3 Image cache 30MB limit is never enforced

**File:** `DownsampledAsyncImage.swift:136-140`

```swift
static let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.totalCostLimit = 30 * 1024 * 1024
    return cache
}()
```

But `setObject` calls at lines 109 and 681 **don't pass a `cost` parameter**:

```swift
ImageDownsampler.cache.setObject(downsampled, forKey: cacheKey)
```

Without cost, `NSCache` treats every object as zero-cost. The 30MB cap is never triggered. Cache grows unbounded.

**Fix:** Pass `data.count` (or estimated byte size) as the `cost` parameter in `setObject(_:forKey:cost:)`.

---

### 6.4 `UIScreen.main.scale` accessed from background thread

**File:** `ExploreMapView.swift:668-670`

```swift
// Inside Task.detached(priority: .utility)
let scale = UIScreen.main.scale
```

`UIScreen.main` must only be accessed on the main thread. This is inside a `Task.detached` — a thread-safety violation.

**Fix:** Capture `UIScreen.main.scale` on the main thread before entering the detached task.

---

## 7. Search — Missing Debounce

### 7.1 `SearchPlaceView` fires a Google Places API call on every keystroke

**File:** `SearchPlaceView.swift:145-152`

```swift
.onChange(of: searchText) { _, newValue in
    Task {
        predictions = await placesService.autocomplete(query: newValue, ...)
    }
}
```

No debounce. Typing "coffee shop" fires 10 concurrent API requests. Stale responses can overwrite newer ones (no task cancellation). Also a billing concern — Google charges per autocomplete request.

**Fix:** Debounce (250-300ms) and cancel stale tasks. `JournalContainerView` already has this pattern (lines 129-135) — replicate it here.

---

## 8. View-Level Computed Property Waste

### 8.1 `TripDetailView.tripLogs` — full scan used 8+ times per render

**File:** `TripDetailView.swift:53-57`

```swift
private var tripLogs: [Log] {
    allLogs.filter { $0.tripID == trip.id }.sorted { $0.createdAt < $1.createdAt }
}
```

`allLogs` is unfiltered `@Query`. This scans all logs, filters, sorts. Then `ratingCounts`, `logsByDay`, `tripPlaces`, `chronologicalMapStops`, `curvedRouteCoordinates`, and `activeRouteCoordinates` all derive from `tripLogs`, causing **multiple evaluations** per render.

**Fix:** Use `@Query` with a `#Predicate` filtering by `tripID`, or compute once in `@State` and refresh on change.

---

### 8.2 `ratingCounts` triple-scans `tripLogs`

**File:** `TripDetailView.swift:91-97`

```swift
private var ratingCounts: (mustSee: Int, solid: Int, skip: Int) {
    (
        mustSee: tripLogs.filter { $0.rating == .mustSee }.count,
        solid: tripLogs.filter { $0.rating == .solid }.count,
        skip: tripLogs.filter { $0.rating == .skip }.count
    )
}
```

Three separate filter passes over `tripLogs` (which itself re-scans all logs).

**Fix:** Single pass with a `reduce` or dictionary grouping.

---

### 8.3 `curvedRouteCoordinates` — 1,050+ bezier calculations per render

**File:** `TripDetailView.swift:390-421`

Generates 21 bezier sample points per route segment. With 50 stops = 1,050 coordinate calculations. Evaluated up to 3 times per render (map content, expanded map, active route).

**Fix:** Cache the result and only recompute when stops change.

---

### 8.4 `MasonryTripsGrid` — `columnAssignments` evaluated 3x per render

**File:** `MasonryTripsGrid.swift:48-57`

`columnAssignments` is a computed property. `leftColumn` and `rightColumn` each re-evaluate it, so the column-balancing algorithm runs **3 times per render**.

**Fix:** Compute once in a single computed property that returns `(left, right)`.

---

### 8.5 `logCountsByTripID` iterates all logs per render

**File:** `MasonryTripsGrid.swift:30-38`

Receives `allLogs` (unfiltered) and iterates through every log to count by trip. Runs on every render triggered by card frame updates, search text changes, expand toggles.

---

### 8.6 `DateFormatter` instantiated per feed item render

**File:** `FeedItem.swift:145-155`

```swift
var dateRangeDisplay: String? {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d"
    ...
}
```

`DateFormatter` is expensive (~1ms to create). With 25 visible feed items, that's 25 allocations per render.

**Fix:** Use a `static let` formatter (like `TripDetailView.swift:22-26` already does).

---

## 9. Priority Matrix

### Critical (will break at scale)
| Issue | Trigger Threshold |
|---|---|
| No delta sync — full pull every 30s | >500 logs |
| Unfiltered `@Query` in views | >1,000 logs |
| No pin clustering on map | >200 visible pins |
| No LIMIT on follower/following lists | >1,000 followers |
| No LIMIT on `fetchUserLogs` | >500 logs per user |
| Image cache limit unenforced | >100 cached images |
| Main-thread image compression | >3 photos per log |

### High (noticeable degradation)
| Issue | Trigger Threshold |
|---|---|
| `getFollowingIDs` called repeatedly | >50 followers |
| Feed requires 5+ sequential round trips | Any network latency |
| `placesByID` dict rebuilt per render | >500 places |
| `searchCachedPlaces` full scan per keystroke | >200 places |
| No debounce on Google Places autocomplete | Any typing speed |
| Sequential photo uploads | >2 photos |
| `computeUnifiedPins` full rebuild on any change | >300 pins |

### Medium (inefficient but tolerable short-term)
| Issue | Trigger Threshold |
|---|---|
| No SwiftData indexes | >2,000 rows |
| `syncPlace` called per log (no dedup) | >5 pending logs |
| Serial social count queries | Noticeable at >200ms latency |
| `curvedRouteCoordinates` recomputed per render | >30 trip stops |
| `allFriends` iterated per render | >200 friend logs |
| Periodic sync with no foreground check | Always running |
