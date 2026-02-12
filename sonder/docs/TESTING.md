# Sonder Test Suite

**105 tests across 21 suites** | ~0.3s execution time | Zero network access required

## Running Tests

### Xcode
Press **Cmd+U** to run all tests, or click the diamond icon next to any test in the gutter.

### Command Line
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project sonder.xcodeproj \
  -scheme sonder \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
  -only-testing:sonderTests \
  -parallel-testing-enabled NO
```

### Run a Single Suite
```bash
# Replace SuiteName with any suite (e.g., PlacesCacheServiceTests)
-only-testing:sonderTests/SuiteName
```

## File Structure

```
sonderTests/
├── Helpers/
│   ├── TestHelpers.swift          # In-memory ModelContainer factory, fixedDate(), encoders
│   └── TestDataFactory.swift      # enum TestData with factory methods for all models
├── Models/          (9 files, 45 tests)
│   ├── UserTests.swift            # Init, Codable roundtrip, snake_case keys
│   ├── PlaceTests.swift           # Init, coordinate property, Codable, lat/lng keys
│   ├── LogTests.swift             # Init, Rating/SyncStatus enums, Codable
│   ├── TripTests.swift            # Init, Codable, description mapping
│   ├── TripInvitationTests.swift  # Init, status enum, Codable
│   ├── FollowTests.swift          # Init, Codable, snake_case keys
│   ├── WantToGoTests.swift        # Init, Codable, snake_case keys
│   ├── RecentSearchTests.swift    # Init defaults, unique attribute
│   └── FeedItemTests.swift        # Rating convenience, Codable, delegation
├── DTOs/            (4 files, 9 tests)
│   ├── PlacePredictionTests.swift # id delegation, description format
│   ├── NearbyPlaceTests.swift     # id delegation
│   ├── PriceLevelTests.swift      # Raw values, display strings, Codable
│   └── WantToGoWithPlaceTests.swift # id/createdAt delegation, optional sourceUser
├── Services/        (7 files, 46 tests)
│   ├── PlacesCacheServiceTests.swift  # Recent searches CRUD, place caching, search
│   ├── TripServiceLogicTests.swift    # canEdit, isCollaborator, hasAccess, getLogsForTrip
│   ├── SyncEngineTests.swift          # getFailedLogs, updatePendingCount
│   ├── PhotoServiceTests.swift        # Image compression, upload state
│   ├── WantToGoServiceTests.swift     # isInWantToGo, getWantToGoList filtering/sorting
│   ├── SocialServiceTests.swift       # isFollowing direction checks
│   └── AuthenticationServiceTests.swift # generateUsername variants
└── Errors/          (1 file, 5 tests)
    └── ErrorDescriptionTests.swift    # All error enums have non-empty descriptions
```

## Test Inventory

| Suite | Tests | What's Covered |
|-------|------:|----------------|
| **UserTests** | 6 | Init, defaults, Codable roundtrip, snake_case keys, JSON decode |
| **PlaceTests** | 5 | Init, CLLocationCoordinate2D, Codable, lat/lng keys, Supabase JSON |
| **LogTests** | 9 | Init, Rating emoji/displayName/rawValues, SyncStatus, Codable |
| **TripTests** | 5 | Init, Codable, description mapping, collaboratorIDs, optional decode |
| **TripInvitationTests** | 5 | Init, status enum, CaseIterable, Codable, WithDetails delegation |
| **FollowTests** | 3 | Init, Codable roundtrip, snake_case keys |
| **WantToGoTests** | 3 | Init defaults, Codable roundtrip, snake_case keys |
| **RecentSearchTests** | 2 | Default timestamp, placeId storage |
| **FeedItemTests** | 7 | Rating convenience/fallback, delegation, FeedLogResponse mapping, Codable |
| **PlacePredictionTests** | 2 | id == placeId, description format |
| **NearbyPlaceTests** | 1 | id == placeId |
| **PriceLevelTests** | 3 | Raw values, display strings, Codable roundtrip |
| **WantToGoWithPlaceTests** | 3 | id/createdAt delegation, optional sourceUser |
| **PlacesCacheServiceTests** | 15 | Add/update/clear/trim recent searches, cache from details/nearby, get/search places |
| **TripServiceLogicTests** | 12 | canEdit (owner/collaborator/stranger), isCollaborator, hasAccess, getLogsForTrip |
| **SyncEngineTests** | 4 | getFailedLogs filtering, updatePendingCount |
| **PhotoServiceTests** | 3 | Image compression, pending count, upload state |
| **WantToGoServiceTests** | 5 | isInWantToGo (empty/found/wrongUser), getWantToGoList (filter/sort) |
| **SocialServiceTests** | 3 | isFollowing (true/false/wrong direction) |
| **AuthenticationServiceTests** | 4 | generateUsername (basic/special chars/uppercase/no @) |
| **ErrorDescriptionTests** | 5 | AuthError, SyncError, PhotoError, PlacesError, LocationError |

## Technical Details

### Framework
Swift Testing (`import Testing`, `@Test`, `#expect`) — not XCTest.

### SwiftData Isolation
Tests use in-memory `ModelContainer` instances with unique UUID names for full isolation:
```swift
let config = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
let container = try ModelContainer(for: ..., configurations: config)
```

### Important: Keep ModelContainer Alive
`ModelContext` holds a **weak** reference to its `ModelContainer`. Tests must retain the container for the duration of SwiftData operations:
```swift
// CORRECT - container stays alive
let (service, context, container) = try makeSUT()
_ = container

// WRONG - container deallocated, SwiftData crashes
let (service, context, _) = try makeSUT()
```

### No Network Calls
All tests are offline. Services that depend on Supabase are tested only for their local/logic methods. Network-dependent methods (sync, remote fetch) are not tested and would require protocol-based mocking.

### Production Code Changes
Two minor changes were made to support testing:
1. `AuthenticationService.generateUsername` — changed from `private` to `internal` for `@testable import` access
2. `SyncEngine.init` — added `startAutomatically: Bool = true` parameter to skip network monitoring in tests
