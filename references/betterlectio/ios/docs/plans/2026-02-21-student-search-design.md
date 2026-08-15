# Student Search Feature Design

## Overview

A student search feature with pinned friends, classmate browsing, and fuzzy search. Native iOS look and feel using SwiftUI context menus, `.searchable`, and lazy-loaded profile pictures from Lectio.

## Data Sources

### Lectio API Endpoints

- **Student list by letter:** `GET /lectio/{gymId}/FindSkema.aspx?type=elev&forbogstav={letter}`
  - Returns HTML list: `<li><a data-lectiocontextcard="S{id}" href="...?elevid={id}">{Name} ({class} {number})</a></li>`
  - Letters: A-Z + Æ, Ø, Å (29 total)
- **Profile picture ID:** Parsed from `GET /lectio/{gymId}/SkemaNy.aspx?elevid={id}`
  - Extract `pictureid` from `<img id="s_m_HeaderContent_picctrlthumbimage" src="/lectio/{gymId}/GetImage.aspx?pictureid={pictureId}">`
- **Profile picture image:** `GET /lectio/{gymId}/GetImage.aspx?pictureid={id}`

### Data Per Student

| Field | Source | Example |
|-------|--------|---------|
| studentId | `elevid=` param | `60678445652` |
| name | Link text before `(` | `Mads Erik Damborg` |
| className | Inside parentheses | `3b` |
| classNumber | Inside parentheses | `18` |
| pictureId | Lazy-loaded from schedule page | `74096290825` |

## Architecture

### New Files

| File | Purpose |
|------|---------|
| `StudentSearchView.swift` | Main search UI |
| `StudentSearchViewModel.swift` | State management, loading, fuzzy search |
| `StudentStore.swift` | SwiftData persistence for student records |

### Modified Files

| File | Change |
|------|--------|
| `Models.swift` | Add `StudentEntry` model |
| `LectioParser.swift` | Add `parseStudentList(from:)` and `parseStudentPictureId(from:)` |
| `LectioHTTPClient.swift` | Add `fetchStudentList(letter:)` and `fetchStudentPage(studentId:)` |
| `ContentView.swift` | Add "Students" card to HomeView + navigation destination |

## Models

### StudentEntry (Models.swift)

```swift
struct StudentEntry: Codable, Identifiable, Equatable, Hashable {
    let studentId: String
    let name: String
    let className: String   // e.g. "3b"
    let classNumber: String // e.g. "18"
    let gymId: Int
    var id: String { "\(studentId)_\(gymId)" }
}
```

### StudentRecord (SwiftData, StudentStore.swift)

```swift
@Model
final class StudentRecord {
    @Attribute(.unique) var uniqueKey: String  // "{studentId}_{gymId}"
    var studentId: String
    var name: String
    var className: String
    var classNumber: String
    var gymId: Int
    var pictureId: String?
    var lastFetched: Date
}
```

### Pinned Friends

Stored in `UserDefaults` as `[String]` (array of studentId strings). Key: `lectio.pinnedFriends.{currentStudentId}`.

## Data Loading Strategy

### Initial Load (fetch-all-on-first-open)

1. On first open of `StudentSearchView`, check if `StudentStore` has cached students for this `gymId`
2. If empty or stale, sequentially fetch all 29 letters with **1 second delay** between requests
3. Parse each response immediately and insert into SwiftData
4. Show progress indicator: "Loading students... 12/29"
5. Partial results are searchable as they arrive

### Profile Pictures

- **Immediate:** Show initials in colored circles (color derived from name hash)
- **Lazy-load:** As rows scroll into view, fetch the student's schedule page to extract `pictureId`, then load the image
- **Cache:** Store `pictureId` in `StudentRecord` once fetched; use `AsyncImage` or `URLSession` image cache for the actual image data
- **Pinned friends:** Eagerly fetch their photos on view appear (small set)
- **Rate limiting:** 1s delay between picture ID fetches to avoid timeouts

### Refresh

- Pull-to-refresh re-fetches all 29 letters (with 1s delay)
- On subsequent opens, load instantly from SwiftData cache

## Classmate Detection

1. Authenticated student has a class like "3b"
2. Extract year prefix: `"3b"` → `"3"`
3. Classmates = all cached students whose `className` starts with `"3"`
4. Sorted alphabetically by name

## Fuzzy Search

Client-side only, runs against the full cached student list.

### Algorithm

1. **Normalize** query and names: lowercase, strip diacritics (ø→o, æ→ae, å→a)
2. **Score** each student:
   - Exact prefix match → highest score
   - Word-start match (e.g. "mal" matches "**Mal**the") → high score
   - Subsequence match (e.g. "mds" matches "**M**a**d**s") → medium score
   - Edit distance / typo tolerance (e.g. "madz" matches "Mads") → lower score
3. **Filter** below minimum threshold
4. **Sort** by score descending

No external dependencies.

## UI Design

### Default State (empty search bar)

```
┌─────────────────────────────┐
│  🔍 Search students...      │  ← .searchable modifier
├─────────────────────────────┤
│  Pinned Friends             │
│  ┌──┐  ┌──┐  ┌──┐  ┌──┐   │
│  │MA│  │EF│  │SJ│  │LK│   │  ← 4-col LazyVGrid
│  └──┘  └──┘  └──┘  └──┘   │    circular photos/initials
│  Mads  Elli  Sara  Lars   │
├─────────────────────────────┤
│  Classmates                 │
│  ┌──┐ Mads Erik Damborg    │
│  │  │ 3b                    │  ← List rows with circular
│  └──┘                       │    pfp + name + class
│  ┌──┐ Malthe Rindum        │
│  │  │ 3v                    │
│  └──┘                       │
│  ...                        │
└─────────────────────────────┘
```

### Searching State (query entered)

```
┌─────────────────────────────┐
│  🔍 madz                    │
├─────────────────────────────┤
│  ┌──┐ Mads Erik Damborg    │
│  │  │ 3b                    │  ← fuzzy results sorted
│  └──┘                       │    by relevance score
│  ┌──┐ Mads Heinze Skov     │
│  │  │ 1a                    │
│  └──┘                       │
└─────────────────────────────┘
```

### Interactions

- **Long-press** any student → iOS `.contextMenu(menuItems:preview:)`:
  - Preview: large profile photo (or initials circle if not loaded yet)
  - Menu: "Pin Friend" / "Unpin Friend" toggle
- **Tap** any student → navigate to `ScheduleView` showing that student's schedule

## Navigation

- New card on `HomeView` in the existing `HStack` alongside "Grades" and "Homework"
- Title: "Students", icon: `person.2.fill`, color: `.green`
- `NavigationLink(value: "students")` → `.navigationDestination` routes to `StudentSearchView`
