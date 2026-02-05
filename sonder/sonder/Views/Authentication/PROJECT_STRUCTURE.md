# Wandr Project Structure - Complete Breakdown

## 📁 Directory Architecture

```
sonder/
├── 📱 sonderApp.swift                    # App entry point
├── 📋 Wandr_Product_Spec_v3.md          # Product specification
│
├── 📂 Config/                            # Configuration & setup
│   └── SupabaseConfig.swift            # Backend API configuration
│
├── 📂 Models/                            # Data models (SwiftData)
│   ├── User.swift                       # User account model
│   ├── Place.swift                      # Location/place model
│   ├── Log.swift                        # Place rating/review model
│   └── Trip.swift                       # Trip organization model
│
├── 📂 Services/                          # Business logic layer
│   ├── AuthenticationService.swift      # Sign in/out logic
│   └── SyncEngine.swift                 # Offline sync logic
│
└── 📂 Views/                             # User interface (SwiftUI)
    ├── 📂 Authentication/
    │   └── AuthenticationView.swift     # Sign in screen
    ├── 📂 Feed/
    │   └── FeedView.swift               # Friends' activity feed
    ├── 📂 Map/
    │   └── MapView.swift                # Map of logged places
    ├── 📂 Trips/
    │   └── TripsView.swift              # Trip list/management
    ├── 📂 Profile/
    │   └── ProfileView.swift            # User profile & settings
    └── MainTabView.swift                # Tab bar navigation
```

---

## 📱 Root Level Files

### `sonderApp.swift`
**Purpose:** The main entry point of the entire iOS application.

**What it does:**
- Configures SwiftData (local database) with all models
- Initializes `AuthenticationService` for user login/logout
- Initializes `SyncEngine` for syncing local data to Supabase
- Decides whether to show authentication screen or main app
- Provides shared services to all views via SwiftUI's Environment

**Key responsibilities:**
```swift
@main struct sonderApp: App {
    // Sets up local database (SwiftData)
    let modelContainer: ModelContainer
    
    // Manages user authentication state
    @State private var authService = AuthenticationService()
    
    // Syncs data between local device and Supabase cloud
    @State private var syncEngine: SyncEngine?
    
    var body: some Scene {
        // Shows login screen OR main app based on auth state
        if authService.isAuthenticated {
            MainTabView()  // ✅ User signed in
        } else {
            AuthenticationView()  // ❌ User not signed in
        }
    }
}
```

---

## 📂 Config/ - Configuration Files

### `SupabaseConfig.swift`
**Purpose:** Centralized configuration for your Supabase backend.

**What it does:**
- Stores your Supabase project URL
- Stores your Supabase anonymous API key
- Creates a single `SupabaseClient` instance used throughout the app

**Why it's separate:**
- Easy to update credentials in one place
- Keeps sensitive keys organized
- Prevents hardcoding URLs/keys in multiple files

**Usage example:**
```swift
// Any file can import and use:
let supabase = SupabaseConfig.client
```

---

## 📂 Models/ - Data Models (SwiftData)

These are the **data structures** that represent your app's information. They use SwiftData for local storage and sync to Supabase.

### `User.swift`
**Purpose:** Represents a user account in the app.

**Properties:**
- `id` - Unique user identifier (from Supabase Auth)
- `username` - Display name
- `avatarURL` - Profile picture URL
- `bio` - User bio (max 280 characters, like Twitter)
- `isPublic` - Whether profile is public or friends-only
- `createdAt`, `updatedAt` - Timestamps

**Used by:**
- AuthenticationService (creates users on sign up)
- ProfileView (displays user info)
- Feed (shows friends' usernames)

---

### `Place.swift`
**Purpose:** Represents a physical location (restaurant, landmark, etc.)

**Properties:**
- `id` - Google Place ID (unique identifier from Google Places API)
- `name` - Place name ("Blue Bottle Coffee")
- `address` - Full street address
- `latitude`, `longitude` - GPS coordinates
- `types` - Categories (["cafe", "restaurant"])
- `photoReference` - Google photo reference ID

**Why it exists:**
- Separates place data from user logs (many users can log the same place)
- Caches place info locally so you don't re-fetch from Google
- Stores standardized location data for mapping

**Used by:**
- Log (references which place was logged)
- MapView (displays places on map)
- Search (finds places user has been)

---

### `Log.swift`
**Purpose:** Represents a single place rating/experience by a user.

**Properties:**
- `id` - Unique log ID
- `userID` - Who created this log
- `placeID` - Which place was logged
- `rating` - Skip 👎 / Solid 👍 / Must-See 🔥
- `photoURL` - Optional user photo of the place
- `note` - Optional text note (max 280 characters)
- `tags` - Array of tags (["coffee", "brunch", "outdoor-seating"])
- `tripID` - Optional: associated trip
- `syncStatus` - synced / pending / failed (for offline support)
- `createdAt`, `updatedAt` - Timestamps

**Rating enum:**
```swift
enum Rating {
    case skip      // 👎 Skip - Wouldn't recommend
    case solid     // 👍 Solid - Good, would go again
    case mustSee   // 🔥 Must-See - Exceptional, go out of your way
}
```

**This is the core of the app!** Everything revolves around creating and viewing logs.

**Used by:**
- Feed (shows recent logs from friends)
- Map (pins on map show logged places)
- Profile (user's personal log history)
- Trips (logs grouped by trip)

---

### `Trip.swift`
**Purpose:** Optional organizational container for grouping logs.

**Properties:**
- `id` - Unique trip ID
- `name` - Trip name ("Tokyo Summer 2026")
- `coverPhotoURL` - Cover image
- `startDate`, `endDate` - Optional date range
- `collaboratorIDs` - Array of user IDs who can add logs to this trip
- `createdBy` - Trip creator's user ID

**Why optional:**
- Users can log places without creating trips
- Trips are just an organizational tool, not required
- Allows retroactive organization (add old logs to new trips)

**Used by:**
- TripsView (list of all trips)
- Log creation (optionally associate with trip)
- Collaborative logging (friends can contribute to shared trips)

---

## 📂 Services/ - Business Logic

Services handle the **operations and state management** that don't belong in views or models.

### `AuthenticationService.swift`
**Purpose:** Manages user authentication and session state.

**What it does:**
- **Sign in with Apple** - Handles Apple authentication flow
- **Sign in with Google** - Handles Google authentication flow (placeholder for now)
- **Session management** - Checks if user has active session
- **User creation** - Creates user profile in Supabase on first sign in
- **Sign out** - Logs user out and clears session

**Key properties:**
```swift
@Observable class AuthenticationService {
    var currentUser: User?           // Currently signed-in user
    var isAuthenticated: Bool        // true if user is signed in
    var isLoading: Bool              // true during sign in process
    var error: Error?                // Any authentication errors
}
```

**Used by:**
- sonderApp.swift (decides which screen to show)
- AuthenticationView (triggers sign in)
- ProfileView (displays user info, sign out button)

**Flow:**
1. User taps "Sign in with Apple" in `AuthenticationView`
2. `AuthenticationService.signInWithApple()` is called
3. Service exchanges Apple credential for Supabase session
4. Creates/updates user in Supabase database
5. Sets `currentUser` and `isAuthenticated = true`
6. `sonderApp` automatically switches to `MainTabView`

---

### `SyncEngine.swift`
**Purpose:** Synchronizes local data (SwiftData) with cloud backend (Supabase).

**What it does:**
- **Offline-first** - Saves all logs locally immediately
- **Background sync** - Automatically uploads pending data every 30 seconds
- **Retry logic** - Re-attempts failed syncs
- **Status tracking** - Tracks which logs need to be synced

**Key methods:**
- `syncNow()` - Manually trigger sync (called automatically on a timer)
- `syncPendingLogs()` - Uploads logs marked as "pending" or "failed"
- `syncPlace()` - Ensures place data exists in Supabase before uploading log

**Sync flow:**
1. User creates a log offline ✅ Saved to local SwiftData with status = `.pending`
2. SyncEngine wakes up every 30 seconds
3. Finds all logs with `.pending` or `.failed` status
4. Uploads place data first (if not already in Supabase)
5. Uploads log data
6. Marks log as `.synced` ✅

**Why this matters:**
- **Instant feedback** - User sees their log immediately, no waiting for network
- **Reliable** - Works offline, syncs when connection restored
- **No data loss** - Failed syncs are retried automatically

**Used by:**
- sonderApp.swift (initializes sync engine)
- Automatically runs in background

---

## 📂 Views/ - User Interface

SwiftUI views that users see and interact with.

### `Authentication/AuthenticationView.swift`
**Purpose:** The sign-in screen shown when user is not authenticated.

**What it shows:**
- Wandr logo and tagline
- "Sign in with Apple" button
- "Sign in with Google" button (placeholder)

**User interaction:**
1. Tap "Sign in with Apple"
2. Apple's native auth sheet appears
3. User authenticates with Face ID/Touch ID
4. `AuthenticationService.signInWithApple()` is called
5. If successful, automatically navigates to main app

---

### `MainTabView.swift`
**Purpose:** The main tab bar navigation structure.

**Contains:**
- Feed tab (square.grid.2x2 icon)
- Map tab (map icon)
- Trips tab (airplane icon)
- Profile tab (person icon)

**Architecture:**
```swift
TabView {
    FeedView()      // Tag 0
    MapView()       // Tag 1
    TripsView()     // Tag 2
    ProfileView()   // Tag 3
}
```

**Note:** Currently includes placeholder views for Feed, Map, Trips. These will be separated into their own files in Phase 2+.

---

### `Feed/FeedView.swift`
**Purpose:** Shows chronological feed of friends' recent place logs.

**Current state:** Placeholder (will be built in Phase 4)

**Future features:**
- List of friends' logs (newest first)
- Each item shows: friend name, place name, rating, photo
- Tap to see details
- Save places to "Want to Go" list

---

### `Map/MapView.swift`
**Purpose:** Displays all logged places on an interactive map.

**Current state:** Placeholder (will be built in Phase 3)

**Future features:**
- Apple MapKit integration
- Color-coded pins by rating (red = skip, yellow = solid, green = must-see)
- Tap pin to see log details
- Filter by rating, tags, trips

---

### `Trips/TripsView.swift`
**Purpose:** Lists all trips and allows creating/managing them.

**Current state:** Placeholder (will be built in Phase 5)

**Future features:**
- Grid of trip cards with cover photos
- "Create Trip" button
- Tap trip to see map + logs for that trip
- Invite collaborators

---

### `Profile/ProfileView.swift`
**Purpose:** User profile with stats and settings.

**Current state:** Basic implementation showing username and sign out button.

**Future features (Phase 3):**
- Map of all places as hero image
- Stats: Total places, countries, cities, top tags
- Privacy settings (public/friends-only)
- Account management

---

## 🔄 How Everything Connects

### Example: Creating a Log (Future Phase 2)

1. **User taps "+" button** in FeedView or MapView
2. **SearchPlaceView** opens → User searches for place via Google Places API
3. **Place saved** to local SwiftData → `Place` model created
4. **RatePlaceView** opens → User selects Skip/Solid/Must-See
5. **AddDetailsView** opens → User optionally adds photo, note, tags
6. **Log created** → Saved to SwiftData with `syncStatus = .pending`
7. **SyncEngine wakes up** → Uploads place + log to Supabase
8. **Log appears** in user's profile, on map, and in friends' feeds

---

## 🎯 Data Flow Architecture

```
User Interaction
      ↓
   Views (SwiftUI)
      ↓
   Services (Business Logic)
      ↓
   Models (SwiftData) ← Local storage
      ↓
   SyncEngine
      ↓
   Supabase (Cloud) ← Remote storage
      ↓
   Other Users' Devices
```

**Offline-first approach:**
- All writes go to local SwiftData first (instant)
- SyncEngine handles uploading to Supabase in background
- All reads come from local SwiftData (fast, works offline)
- Periodic syncs pull new data from Supabase (friends' logs)

---

## 🏗️ Architecture Patterns Used

### 1. **MVVM (Model-View-ViewModel)**
- **Models:** User, Place, Log, Trip
- **Views:** All SwiftUI views
- **ViewModels (Services):** AuthenticationService, SyncEngine

### 2. **Observable Pattern**
```swift
@Observable class AuthenticationService {
    var currentUser: User?  // Views automatically update when this changes
}
```

### 3. **Environment Injection**
```swift
// In sonderApp:
.environment(authService)

// In any view:
@Environment(AuthenticationService.self) private var authService
```

### 4. **Repository Pattern**
- SwiftData = Local repository
- Supabase = Remote repository
- SyncEngine = Synchronization layer

---

## 📊 Current Phase: Phase 1 Complete ✅

**What's working:**
- ✅ SwiftData local storage configured
- ✅ Supabase backend connected
- ✅ Authentication flow (Apple sign in)
- ✅ Tab bar navigation structure
- ✅ Offline sync engine foundation
- ✅ Data models defined

**What's placeholder:**
- ⏳ Google Places API integration
- ⏳ Place search functionality
- ⏳ Log creation flow
- ⏳ Map visualization
- ⏳ Feed functionality
- ⏳ Trip management

---

## 🚀 Next Steps (Phase 2: Core Logging)

1. **Google Places API integration** - Search for places
2. **SearchPlaceView** - Find and select places
3. **RatePlaceView** - Pick Skip/Solid/Must-See rating
4. **AddDetailsView** - Photo, note, tags
5. **Photo upload** - Compress and upload to Supabase Storage

This will enable the core functionality: logging places!

---

## 💡 Key Design Decisions

### Why SwiftData + Supabase?
- **SwiftData:** Native Apple framework, perfect for offline-first local storage
- **Supabase:** PostgreSQL backend with real-time features, perfect for social features

### Why Offline-First?
- Users can log places with no internet (hiking, traveling)
- Instant feedback, no loading spinners
- Reliable data persistence

### Why Separate Models from Views?
- Models can be reused across multiple views
- Easier testing
- Clear separation of concerns

### Why Services Layer?
- Views stay simple and focused on UI
- Business logic is reusable
- Easier to mock for testing

---

## 📖 Quick Reference

| File | What it does | When you need it |
|------|-------------|------------------|
| `sonderApp.swift` | App setup | Rarely (already configured) |
| `SupabaseConfig.swift` | API keys | When changing backend |
| `User.swift` | User data structure | Adding user features |
| `Place.swift` | Location data | Working with places/maps |
| `Log.swift` | Rating/review data | Core logging features |
| `Trip.swift` | Trip organization | Trip features |
| `AuthenticationService.swift` | Sign in/out | Auth-related features |
| `SyncEngine.swift` | Data sync | Rarely (already works) |
| `AuthenticationView.swift` | Login screen | Changing login UI |
| `MainTabView.swift` | Tab bar | Adding/removing tabs |
| `FeedView.swift` | Friends' feed | Social features (Phase 4) |
| `MapView.swift` | Map display | Map features (Phase 3) |
| `TripsView.swift` | Trip list | Trip features (Phase 5) |
| `ProfileView.swift` | User profile | Profile features (Phase 3) |

---

**This architecture is designed to scale** as you add features in Phases 2-6! Each directory has a clear purpose, making it easy to know where new code should go.
