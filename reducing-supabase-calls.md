# Reducing Supabase Database Calls

## Current Problem

The app is making ~500 Supabase requests per hour during normal use. At scale, this will hit Supabase rate limits and inflate costs.

---

## Request Audit

### 1. SyncEngine (480-600 req/hr) — THE PRIMARY ISSUE

The `SyncEngine` runs `syncNow()` **every 30 seconds**. Each cycle makes 4-7 requests:

| Step | Table | Query Type | Runs Every Cycle? |
|------|-------|------------|-------------------|
| `syncPendingTrips()` | `trips` | UPSERT | Only if dirty items |
| `syncPendingLogs()` | `places`, `logs` | UPSERT | Only if dirty items |
| `syncPendingDeletions()` | `logs` | DELETE | Only if pending |
| `pullRemoteTrips()` (owned) | `trips` | SELECT | **Yes** |
| `pullRemoteTrips()` (collab) | `trips` | SELECT | **Yes** |
| `pullRemoteLogs()` | `logs` | SELECT (all rows) | **Yes** |
| `pullRemoteLogs()` (places) | `places` | SELECT | Only if missing |

**Minimum per cycle: 4-5 requests**
**At 30s intervals: 120 cycles/hr x 4-5 = 480-600 requests/hr**

Key issue: `pullRemoteLogs` fetches **every log for the user** with no incremental filter. This is a full table scan every 30 seconds.

### 2. RootView duplicate calls (4 extra on launch)

`sonderApp.swift` calls `socialService.refreshCounts()` in **two places** that both fire on launch:

```
Line 203: .onChange(of: authService.currentUser?.id) → refreshCounts (2 requests)
Line 221: .task { refreshCounts }                    → refreshCounts (2 requests)
```

Both fire when the user ID is set on app launch = 4 requests instead of 2.

### 3. View `.task` calls (no staleness guard)

| View | Trigger | Requests | Caching? |
|------|---------|----------|----------|
| FeedView `.task` | Tab appear | 8-10 | followingIDs has 60s cache |
| ExploreMapView `.task` | Tab appear | 4-6 | 30s throttle (`lastFullLoadAt`) |
| ProfileView `.task` | Tab appear | 3 | **None** |
| TripsListView `.task` | View appear | 2-3 | **None** |
| OtherUserProfileView `.task` | Navigation push | 5-6 | **None** |
| WantToGoListView `.task` | Navigation push | 1 | **None** |

### 4. `needsResync` double-sync

If `syncNow()` is called while a sync is already running, the `needsResync` flag triggers an immediate second full sync cycle — doubling requests for that window.

---

## Fixes (Priority Order)

### Fix 1: Increase SyncEngine interval (30s → 300s)

**Impact: ~480 req/hr → ~60 req/hr**
**Effort: 1 line change**

```swift
// SyncEngine.swift, line 329
// Before:
try? await Task.sleep(for: .seconds(30))

// After:
try? await Task.sleep(for: .seconds(300))
```

30 seconds is overkill for a travel journal app. 5 minutes is plenty for background sync. Users still get instant sync on their own writes (push sync is immediate).

### Fix 2: Incremental pull sync with `updated_at` filter

**Impact: Eliminates redundant full-table scans**
**Effort: Medium**

Instead of fetching ALL logs every cycle, only fetch rows changed since the last sync:

```swift
// Before (pullRemoteLogs):
let remoteLogs: [RemoteLog] = try await supabase
    .from("logs")
    .select()
    .eq("user_id", value: userID)
    .execute()
    .value

// After:
var query = supabase
    .from("logs")
    .select()
    .eq("user_id", value: userID)

if let lastSync = lastSyncDate {
    query = query.gte("updated_at", value: ISO8601DateFormatter().string(from: lastSync))
}

let remoteLogs: [RemoteLog] = try await query.execute().value
```

Apply the same pattern to `pullRemoteTrips`. This means most sync cycles return 0 rows and are essentially free.

**Caveat**: Need a full sync on first launch (no `lastSyncDate`), and should do a periodic full sync (e.g., every 10th cycle) to catch any edge cases like server-side deletes.

### Fix 3: Remove duplicate `refreshCounts` in RootView

**Impact: -2 requests on every app launch**
**Effort: 1 deletion**

Remove the `.task` block since `.onChange` already handles it:

```swift
// sonderApp.swift — DELETE this block (lines 219-227):
.task {
    if let userID = authService.currentUser?.id {
        await socialService.refreshCounts(for: userID)
        proximityService.configure(wantToGoService: wantToGoService, userID: userID)
        proximityService.setupNotificationCategories()
        await proximityService.resumeMonitoringIfAuthorized()
    }
}
```

The `.onChange(of: authService.currentUser?.id)` block already fires when the user ID is set (including initial set), so the `.task` is redundant.

**Note**: Move the proximity setup into `.onChange` if it isn't already there (it is — lines 205-207).

### Fix 4: Add staleness cache to `refreshCounts`

**Impact: Eliminates repeat calls within 60s window**
**Effort: Small**

```swift
// SocialService.swift
private var lastCountsRefresh: Date?

func refreshCounts(for userID: String) async {
    // Skip if refreshed within last 60 seconds
    if let last = lastCountsRefresh, Date().timeIntervalSince(last) < 60 {
        return
    }
    followerCount = await getFollowerCount(for: userID)
    followingCount = await getFollowingCount(for: userID)
    countsLoaded = true
    lastCountsRefresh = Date()
}
```

This prevents ProfileView tab switches from firing 2 requests each time.

### Fix 5: Combine trip pull queries into one

**Impact: -1 request per sync cycle**
**Effort: Small**

Instead of two separate queries (owned + collaborator), use an `or` filter:

```swift
// Before: 2 queries
let ownedTrips = try await supabase.from("trips").select().eq("created_by", value: userID)...
let collabTrips = try await supabase.from("trips").select().contains("collaborator_ids", value: [userID])...

// After: 1 query
let allTrips: [RemoteTrip] = try await supabase
    .from("trips")
    .select()
    .or("created_by.eq.\(userID),collaborator_ids.cs.{\(userID)}")
    .execute()
    .value
```

### Fix 6: Skip push steps when nothing is dirty

**Impact: Avoids unnecessary function call overhead**
**Effort: Small**

`syncPendingTrips()` and `syncPendingLogs()` already check for dirty items internally, but they still execute the session check. Add early returns:

```swift
func syncNow() async {
    // ... session check ...

    // Push only if there's pending work
    let hasPendingLogs = (try? modelContext.fetchCount(
        FetchDescriptor<Log>(predicate: #Predicate { $0.syncStatus != "synced" })
    )) ?? 0 > 0

    let hasPendingTrips = (try? modelContext.fetchCount(
        FetchDescriptor<Trip>(predicate: #Predicate { $0.syncStatus != "synced" })
    )) ?? 0 > 0

    if hasPendingLogs || hasPendingTrips {
        try await syncPendingTrips()
        try await syncPendingLogs()
    }
    // ...
}
```

### Fix 7: Use Supabase Realtime instead of polling for pulls

**Impact: Eliminates pull polling entirely**
**Effort: Large (but the pattern already exists in FeedService)**

The app already uses Realtime subscriptions in `FeedService.subscribeToRealtimeUpdates()`. Apply the same pattern to SyncEngine:

```swift
// Subscribe to changes on the logs table for this user
let channel = supabase.channel("sync-\(userID)")

channel.postgresChange(InsertAction.self, table: "logs", filter: "user_id=eq.\(userID)") { insert in
    // Merge the new/updated log locally
}

channel.postgresChange(UpdateAction.self, table: "logs", filter: "user_id=eq.\(userID)") { update in
    // Update local log
}

channel.postgresChange(DeleteAction.self, table: "logs", filter: "user_id=eq.\(userID)") { delete in
    // Remove local log
}

await channel.subscribe()
```

This replaces polling with push — zero requests for pull sync. Keep a slow fallback poll (every 10-15 min) for reliability.

---

## Expected Impact

| Fix | Requests Saved/hr | Cumulative |
|-----|-------------------|------------|
| Fix 1: 30s → 300s interval | ~420 | ~80/hr |
| Fix 2: Incremental pull | ~40 | ~40/hr |
| Fix 3: Remove duplicate refreshCounts | ~2 per launch | ~38/hr |
| Fix 4: Cache refreshCounts | ~5-10 (tab switching) | ~30/hr |
| Fix 5: Combine trip queries | ~12 | ~18/hr |
| Fix 7: Realtime (replaces polling) | Remaining pulls | ~5-10/hr |

Fixes 1-4 alone bring the app from ~500 req/hr down to ~30-40 req/hr.

---

## Implementation Order

1. **Fix 1** — Immediate, 1 line, biggest impact
2. **Fix 3** — Immediate, delete duplicate code
3. **Fix 4** — Quick, add timestamp check
4. **Fix 5** — Quick, combine queries
5. **Fix 2** — Medium effort, requires `updated_at` column awareness
6. **Fix 6** — Small, optional optimization
7. **Fix 7** — Large effort, but the long-term right answer
