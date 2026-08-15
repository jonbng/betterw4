# Student Search Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a student search feature with pinned friends grid, classmate list, fuzzy search, profile pictures, and context menu pinning.

**Architecture:** New `StudentSearchView` with `StudentSearchViewModel` for state, `StudentStore` (SwiftData) for caching student records. Extends existing `LectioHTTPClient` and `LectioParser` with new fetch/parse methods. Navigated to from HomeView via NavigationStack.

**Tech Stack:** SwiftUI, SwiftData, SwiftSoup, AsyncImage

---

### Task 1: Add StudentEntry model

**Files:**
- Modify: `BetterLectio/Models.swift` (append after the `ScheduleData` struct, before end of file)

**Step 1: Add the model**

Add at the end of `Models.swift`:

```swift
// MARK: - Student Search Models

struct StudentEntry: Codable, Identifiable, Equatable, Hashable {
    let studentId: String
    let name: String
    let className: String
    let classNumber: String
    let gymId: Int

    var id: String { "\(studentId)_\(gymId)" }

    /// Returns initials from the student's name (first letter of first and last name)
    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts.first!.prefix(1))\(parts.last!.prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// Consistent color derived from name hash
    var color: Int {
        abs(name.hashValue) % 12
    }
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild build -project BetterLectio.xcodeproj -scheme BetterLectio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add BetterLectio/Models.swift
git commit -m "Add StudentEntry model for student search"
```

---

### Task 2: Add student list parser to LectioParser

**Files:**
- Modify: `BetterLectio/LectioParser.swift` (add new methods at the end, before closing `}`)

**Step 1: Add parseStudentList method**

Add to `LectioParser`:

```swift
// MARK: - Parse Student List

/// Parses the FindSkema.aspx student list page into StudentEntry array.
/// Each student is an `<a>` inside `<li>` in the `.ls-columnlist` container.
/// Format: `<a data-lectiocontextcard="S{id}" href="...?elevid={id}">{Name} ({class} {number})</a>`
func parseStudentList(from html: String, gymId: Int) throws -> [StudentEntry] {
    let doc = try SwiftSoup.parse(html)

    guard let listContainer = try doc.select("div.x-listen").first() else {
        print("⚠️ Student list container not found")
        return []
    }

    let links = try listContainer.select("ul.ls-columnlist li a")
    var students: [StudentEntry] = []

    for link in links {
        let href = try link.attr("href")
        let text = try link.text().trimmingCharacters(in: .whitespaces)

        // Extract studentId from href: "...?elevid=60678445652"
        guard let elevIdRange = href.range(of: "elevid=(\\d+)", options: .regularExpression),
              let idStart = href.range(of: "elevid=")?.upperBound else {
            continue
        }
        let studentId = String(href[idStart...].prefix(while: { $0.isNumber }))
        guard !studentId.isEmpty else { continue }

        // Parse name and class info from text: "Mads Erik Damborg (3b 18)"
        let name: String
        let className: String
        let classNumber: String

        if let parenOpen = text.lastIndex(of: "("),
           let parenClose = text.lastIndex(of: ")") {
            name = String(text[text.startIndex..<parenOpen]).trimmingCharacters(in: .whitespaces)
            let classInfo = String(text[text.index(after: parenOpen)..<parenClose])
            let classParts = classInfo.split(separator: " ", maxSplits: 1)
            className = classParts.first.map(String.init) ?? ""
            classNumber = classParts.count > 1 ? String(classParts[1]) : ""
        } else {
            name = text
            className = ""
            classNumber = ""
        }

        guard !name.isEmpty else { continue }

        students.append(StudentEntry(
            studentId: studentId,
            name: name,
            className: className,
            classNumber: classNumber,
            gymId: gymId
        ))
    }

    print("👥 Parsed \(students.count) students from HTML")
    return students
}

// MARK: - Parse Student Picture ID

/// Parses the student's schedule page to extract their profile picture ID.
/// Looks for: `<img id="s_m_HeaderContent_picctrlthumbimage" src="...?pictureid={id}">`
func parseStudentPictureId(from html: String) -> String? {
    do {
        let doc = try SwiftSoup.parse(html)
        guard let img = try doc.select("img#s_m_HeaderContent_picctrlthumbimage").first() else {
            return nil
        }
        let src = try img.attr("src")
        // Extract pictureid from: "/lectio/94/GetImage.aspx?pictureid=74096247556"
        guard let range = src.range(of: "pictureid=(\\d+)", options: .regularExpression) else {
            return nil
        }
        let match = String(src[range])
        return match.replacingOccurrences(of: "pictureid=", with: "")
    } catch {
        print("⚠️ Failed to parse picture ID: \(error)")
        return nil
    }
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild build -project BetterLectio.xcodeproj -scheme BetterLectio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add BetterLectio/LectioParser.swift
git commit -m "Add student list and picture ID parsers"
```

---

### Task 3: Add HTTP client methods for student fetching

**Files:**
- Modify: `BetterLectio/LectioHTTPClient.swift` (add new methods before closing `}`)

**Step 1: Add fetchStudentList and fetchStudentPage methods**

Add to `LectioHTTPClient`:

```swift
// MARK: - Fetch Student List

/// Fetches the student list page for a given first-letter filter.
/// URL: /lectio/{gymId}/FindSkema.aspx?type=elev&forbogstav={letter}
func fetchStudentList(
    credentials: LectioCredentials,
    studentId: String,
    schoolId: Int,
    letter: String
) async throws -> String {
    let encodedLetter = letter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? letter
    let urlString = "https://www.lectio.dk/lectio/\(schoolId)/FindSkema.aspx?type=elev&forbogstav=\(encodedLetter)"

    guard let url = URL(string: urlString) else {
        throw LectioError.invalidURL
    }

    let (data, _) = try await fetchWithCookies(
        url: url,
        credentials: credentials,
        studentId: studentId
    )

    guard let html = String(data: data, encoding: .utf8) else {
        throw LectioError.parsingError("Could not decode student list HTML")
    }

    return html
}

// MARK: - Fetch Student Page (for picture ID)

/// Fetches a student's schedule page to extract their picture ID.
/// URL: /lectio/{gymId}/SkemaNy.aspx?elevid={targetStudentId}
func fetchStudentPage(
    credentials: LectioCredentials,
    studentId: String,
    schoolId: Int,
    targetStudentId: String
) async throws -> String {
    let urlString = "https://www.lectio.dk/lectio/\(schoolId)/SkemaNy.aspx?elevid=\(targetStudentId)"

    guard let url = URL(string: urlString) else {
        throw LectioError.invalidURL
    }

    let (data, _) = try await fetchWithCookies(
        url: url,
        credentials: credentials,
        studentId: studentId
    )

    guard let html = String(data: data, encoding: .utf8) else {
        throw LectioError.parsingError("Could not decode student page HTML")
    }

    return html
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild build -project BetterLectio.xcodeproj -scheme BetterLectio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add BetterLectio/LectioHTTPClient.swift
git commit -m "Add HTTP client methods for student list and page fetching"
```

---

### Task 4: Create StudentStore (SwiftData persistence)

**Files:**
- Create: `BetterLectio/StudentStore.swift`

**Step 1: Create the file**

```swift
//
//  StudentStore.swift
//  BetterLectio
//

import Foundation
import SwiftData

@Model
final class StudentRecord {
    @Attribute(.unique) var uniqueKey: String
    var studentId: String
    var name: String
    var className: String
    var classNumber: String
    var gymId: Int
    var pictureId: String?
    var lastFetched: Date

    init(
        uniqueKey: String,
        studentId: String,
        name: String,
        className: String,
        classNumber: String,
        gymId: Int,
        pictureId: String? = nil,
        lastFetched: Date
    ) {
        self.uniqueKey = uniqueKey
        self.studentId = studentId
        self.name = name
        self.className = className
        self.classNumber = classNumber
        self.gymId = gymId
        self.pictureId = pictureId
        self.lastFetched = lastFetched
    }
}

/// Local student storage backed by SwiftData.
class StudentStore {
    static let shared = StudentStore()
    private let container: ModelContainer
    private let context: ModelContext

    private init() {
        do {
            container = try ModelContainer(for: StudentRecord.self)
            context = ModelContext(container)
            context.autosaveEnabled = true
        } catch {
            fatalError("Failed to initialize StudentStore SwiftData container: \(error)")
        }
    }

    // MARK: - Load

    /// Loads all cached students for a school.
    func loadStudents(for gymId: Int) -> [StudentEntry] {
        do {
            let descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.gymId == gymId },
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )
            return try context.fetch(descriptor).map(Self.toStudentEntry)
        } catch {
            print("❌ Failed to load cached students: \(error)")
            return []
        }
    }

    /// Checks if we have any cached students for a school.
    func hasCachedStudents(for gymId: Int) -> Bool {
        do {
            var descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.gymId == gymId }
            )
            descriptor.fetchLimit = 1
            return try !context.fetch(descriptor).isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Upsert

    /// Upserts a batch of students from a single letter fetch.
    func upsertStudents(_ students: [StudentEntry]) throws {
        let now = TimeProvider.now
        for student in students {
            let key = "\(student.studentId)_\(student.gymId)"
            var descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.uniqueKey == key }
            )
            descriptor.fetchLimit = 1

            if let record = try context.fetch(descriptor).first {
                record.name = student.name
                record.className = student.className
                record.classNumber = student.classNumber
                record.lastFetched = now
            } else {
                let record = StudentRecord(
                    uniqueKey: key,
                    studentId: student.studentId,
                    name: student.name,
                    className: student.className,
                    classNumber: student.classNumber,
                    gymId: student.gymId,
                    lastFetched: now
                )
                context.insert(record)
            }
        }
        try context.save()
    }

    // MARK: - Picture ID

    /// Saves a picture ID for a student.
    func savePictureId(_ pictureId: String, for studentId: String, gymId: Int) {
        do {
            let key = "\(studentId)_\(gymId)"
            var descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.uniqueKey == key }
            )
            descriptor.fetchLimit = 1

            if let record = try context.fetch(descriptor).first {
                record.pictureId = pictureId
                try context.save()
            }
        } catch {
            print("❌ Failed to save picture ID: \(error)")
        }
    }

    /// Loads the picture ID for a student (if cached).
    func loadPictureId(for studentId: String, gymId: Int) -> String? {
        do {
            let key = "\(studentId)_\(gymId)"
            var descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.uniqueKey == key }
            )
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first?.pictureId
        } catch {
            return nil
        }
    }

    // MARK: - Clear

    func clearStudents(for gymId: Int) {
        do {
            let descriptor = FetchDescriptor<StudentRecord>(
                predicate: #Predicate { $0.gymId == gymId }
            )
            let records = try context.fetch(descriptor)
            for record in records {
                context.delete(record)
            }
            try context.save()
        } catch {
            print("❌ Failed to clear students: \(error)")
        }
    }

    // MARK: - Conversion

    private static func toStudentEntry(_ record: StudentRecord) -> StudentEntry {
        StudentEntry(
            studentId: record.studentId,
            name: record.name,
            className: record.className,
            classNumber: record.classNumber,
            gymId: record.gymId
        )
    }
}
```

**Step 2: Add StudentRecord to the app's ModelContainer**

The `StudentRecord` model uses its own `ModelContainer` (same pattern as `ScheduleStore`), so no changes to `BetterLectioApp.swift` are needed.

**Step 3: Verify it compiles**

Run: `xcodebuild build -project BetterLectio.xcodeproj -scheme BetterLectio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add BetterLectio/StudentStore.swift
git commit -m "Add StudentStore with SwiftData persistence"
```

---

### Task 5: Create StudentSearchViewModel

**Files:**
- Create: `BetterLectio/StudentSearchViewModel.swift`

**Step 1: Create the file**

```swift
//
//  StudentSearchViewModel.swift
//  BetterLectio
//

import Foundation
import SwiftUI

@MainActor
class StudentSearchViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var allStudents: [StudentEntry] = []
    @Published var searchQuery = ""
    @Published var isLoading = false
    @Published var loadingProgress: (current: Int, total: Int) = (0, 29)
    @Published var errorMessage: String?
    @Published var pinnedFriendIds: Set<String> = []
    @Published var pictureIds: [String: String] = [:] // studentId -> pictureId

    // MARK: - Services

    private let httpClient = LectioHTTPClient()
    private let parser = LectioParser()
    private let store = StudentStore.shared
    private let keychainManager = KeychainManager.shared
    private var pictureFetchingIds: Set<String> = []

    // All letters to fetch (A-Z + Æ, Ø, Å)
    private let letters: [String] = {
        var result = (65...90).map { String(UnicodeScalar($0)) } // A-Z
        result.append(contentsOf: ["Æ", "Ø", "Å"])
        return result
    }()

    // MARK: - Computed Properties

    /// Pinned friends from allStudents
    var pinnedFriends: [StudentEntry] {
        allStudents.filter { pinnedFriendIds.contains($0.studentId) }
    }

    /// Classmates: same year group as current student
    func classmates(for student: Student) -> [StudentEntry] {
        // Find current student's class in the cached list
        let currentStudentRecord = allStudents.first { $0.studentId == student.studentId }
        guard let yearPrefix = currentStudentRecord?.className.prefix(1),
              !yearPrefix.isEmpty,
              yearPrefix.first?.isNumber == true else {
            return []
        }
        let prefix = String(yearPrefix)
        return allStudents.filter {
            $0.className.hasPrefix(prefix) && $0.studentId != student.studentId
        }
    }

    /// Search results using fuzzy matching
    var searchResults: [StudentEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return fuzzySearch(query: query, in: allStudents)
    }

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Load Students

    /// Loads students from cache or fetches from Lectio
    func loadStudents(for student: Student) async {
        // Load from cache first
        let cached = store.loadStudents(for: student.gymId)
        if !cached.isEmpty {
            allStudents = cached
            loadPictureIdsFromStore(for: student.gymId)
            print("✅ Loaded \(cached.count) cached students")
        }

        // Load pinned friends from UserDefaults
        loadPinnedFriends(for: student.studentId)

        // If no cache, fetch from Lectio
        if cached.isEmpty {
            await fetchAllStudents(for: student)
        }
    }

    /// Fetches all students from Lectio (A-Z + Æ, Ø, Å) with 1s delay between requests
    func fetchAllStudents(for student: Student) async {
        guard let credentials = keychainManager.loadCredentials(for: student.studentId),
              credentials.isValid else {
            errorMessage = "Session expired. Please login again."
            return
        }

        isLoading = true
        errorMessage = nil
        loadingProgress = (0, letters.count)

        for (index, letter) in letters.enumerated() {
            do {
                let html = try await httpClient.fetchStudentList(
                    credentials: credentials,
                    studentId: student.studentId,
                    schoolId: student.gymId,
                    letter: letter
                )

                let students = try parser.parseStudentList(from: html, gymId: student.gymId)
                try store.upsertStudents(students)

                // Reload from store for consistency
                allStudents = store.loadStudents(for: student.gymId)
                loadingProgress = (index + 1, letters.count)

                print("📨 Fetched letter \(letter): \(students.count) students (total: \(allStudents.count))")
            } catch {
                print("⚠️ Failed to fetch letter \(letter): \(error.localizedDescription)")
                // Continue with next letter, don't abort entire fetch
            }

            // 1 second delay between requests
            if index < letters.count - 1 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        isLoading = false
        print("✅ Finished fetching all students: \(allStudents.count) total")
    }

    // MARK: - Pinned Friends

    private func pinnedFriendsKey(for studentId: String) -> String {
        "lectio.pinnedFriends.\(studentId)"
    }

    func loadPinnedFriends(for studentId: String) {
        let key = pinnedFriendsKey(for: studentId)
        let ids = UserDefaults.standard.stringArray(forKey: key) ?? []
        pinnedFriendIds = Set(ids)
    }

    func togglePin(for targetStudentId: String, currentStudentId: String) {
        if pinnedFriendIds.contains(targetStudentId) {
            pinnedFriendIds.remove(targetStudentId)
        } else {
            pinnedFriendIds.insert(targetStudentId)
        }
        let key = pinnedFriendsKey(for: currentStudentId)
        UserDefaults.standard.set(Array(pinnedFriendIds), forKey: key)
    }

    func isPinned(_ studentId: String) -> Bool {
        pinnedFriendIds.contains(studentId)
    }

    // MARK: - Profile Pictures

    /// Fetches picture ID for a student if not already cached
    func fetchPictureIdIfNeeded(for entry: StudentEntry, authenticatedStudent: Student) async {
        // Already have it
        if pictureIds[entry.studentId] != nil { return }

        // Check store
        if let cached = store.loadPictureId(for: entry.studentId, gymId: entry.gymId) {
            pictureIds[entry.studentId] = cached
            return
        }

        // Prevent duplicate fetches
        guard !pictureFetchingIds.contains(entry.studentId) else { return }
        pictureFetchingIds.insert(entry.studentId)
        defer { pictureFetchingIds.remove(entry.studentId) }

        guard let credentials = keychainManager.loadCredentials(for: authenticatedStudent.studentId),
              credentials.isValid else { return }

        do {
            let html = try await httpClient.fetchStudentPage(
                credentials: credentials,
                studentId: authenticatedStudent.studentId,
                schoolId: entry.gymId,
                targetStudentId: entry.studentId
            )

            if let pictureId = parser.parseStudentPictureId(from: html) {
                pictureIds[entry.studentId] = pictureId
                store.savePictureId(pictureId, for: entry.studentId, gymId: entry.gymId)
            }
        } catch {
            print("⚠️ Failed to fetch picture for \(entry.name): \(error.localizedDescription)")
        }
    }

    /// Eagerly fetches pictures for pinned friends
    func fetchPinnedFriendPictures(for student: Student) async {
        for friend in pinnedFriends {
            await fetchPictureIdIfNeeded(for: friend, authenticatedStudent: student)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    /// Returns the full image URL for a student (if picture ID is known)
    func pictureURL(for entry: StudentEntry) -> URL? {
        guard let pictureId = pictureIds[entry.studentId] else { return nil }
        return URL(string: "https://www.lectio.dk/lectio/\(entry.gymId)/GetImage.aspx?pictureid=\(pictureId)")
    }

    private func loadPictureIdsFromStore(for gymId: Int) {
        for student in allStudents {
            if let pid = store.loadPictureId(for: student.studentId, gymId: gymId) {
                pictureIds[student.studentId] = pid
            }
        }
    }

    // MARK: - Fuzzy Search

    private func fuzzySearch(query: String, in students: [StudentEntry]) -> [StudentEntry] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var scored: [(student: StudentEntry, score: Double)] = []

        for student in students {
            let normalizedName = normalize(student.name)
            let score = fuzzyScore(query: normalizedQuery, target: normalizedName)
            if score > 0.3 {
                scored.append((student, score))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .map { $0.student }
    }

    /// Normalizes a string: lowercase, strip diacritics
    private func normalize(_ string: String) -> String {
        string
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    /// Calculates a fuzzy match score (0.0 to 1.0) between query and target
    private func fuzzyScore(query: String, target: String) -> Double {
        // Exact prefix match (highest)
        if target.hasPrefix(query) {
            return 1.0
        }

        // Word-start match: query matches the start of any word
        let words = target.split(separator: " ").map(String.init)
        for word in words {
            if word.hasPrefix(query) {
                return 0.9
            }
        }

        // Multi-word query: each query word matches start of a target word
        let queryWords = query.split(separator: " ").map(String.init)
        if queryWords.count > 1 {
            var matchCount = 0
            for qWord in queryWords {
                if words.contains(where: { $0.hasPrefix(qWord) }) {
                    matchCount += 1
                }
            }
            if matchCount == queryWords.count {
                return 0.85
            }
        }

        // Subsequence match
        if isSubsequence(query: query, target: target) {
            let ratio = Double(query.count) / Double(target.count)
            return 0.5 + (ratio * 0.3)
        }

        // Edit distance for typo tolerance
        let distance = levenshteinDistance(query, target.prefix(query.count + 2).description)
        let maxLen = max(query.count, target.count)
        guard maxLen > 0 else { return 0 }
        let similarity = 1.0 - (Double(distance) / Double(maxLen))
        if similarity > 0.5 {
            return similarity * 0.6
        }

        return 0
    }

    private func isSubsequence(query: String, target: String) -> Bool {
        var queryIndex = query.startIndex
        var targetIndex = target.startIndex

        while queryIndex < query.endIndex && targetIndex < target.endIndex {
            if query[queryIndex] == target[targetIndex] {
                queryIndex = query.index(after: queryIndex)
            }
            targetIndex = target.index(after: targetIndex)
        }

        return queryIndex == query.endIndex
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                dp[i][j] = min(
                    dp[i - 1][j] + 1,
                    dp[i][j - 1] + 1,
                    dp[i - 1][j - 1] + cost
                )
            }
        }

        return dp[m][n]
    }
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild build -project BetterLectio.xcodeproj -scheme BetterLectio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add BetterLectio/StudentSearchViewModel.swift
git commit -m "Add StudentSearchViewModel with fuzzy search and picture loading"
```

---

### Task 6: Create StudentSearchView

**Files:**
- Create: `BetterLectio/StudentSearchView.swift`

**Step 1: Create the file**

```swift
//
//  StudentSearchView.swift
//  BetterLectio
//

import SwiftUI

struct StudentSearchView: View {
    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @StateObject private var viewModel = StudentSearchViewModel()

    private static let avatarColors: [Color] = [
        .blue, .purple, .orange, .pink, .green, .red,
        .teal, .indigo, .cyan, .brown, .mint, .yellow
    ]

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.allStudents.isEmpty {
                loadingView
            } else {
                mainContent
            }
        }
        .navigationTitle("Students")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchQuery, prompt: "Search students...")
        .onAppear {
            Task {
                await viewModel.loadStudents(for: student)
                await viewModel.fetchPinnedFriendPictures(for: student)
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading students...")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("\(viewModel.loadingProgress.current)/\(viewModel.loadingProgress.total)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ProgressView(
                value: Double(viewModel.loadingProgress.current),
                total: Double(viewModel.loadingProgress.total)
            )
            .progressViewStyle(.linear)
            .frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if viewModel.isSearching {
                    searchResultsSection
                } else {
                    if !viewModel.pinnedFriends.isEmpty {
                        pinnedFriendsSection
                    }
                    classmatesSection
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .refreshable {
            await viewModel.fetchAllStudents(for: student)
        }
    }

    // MARK: - Pinned Friends Section

    private var pinnedFriendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pinned Friends")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                ForEach(viewModel.pinnedFriends) { entry in
                    NavigationLink(value: "student_\(entry.studentId)") {
                        pinnedFriendCell(entry)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.togglePin(for: entry.studentId, currentStudentId: student.studentId)
                        } label: {
                            Label("Unpin Friend", systemImage: "pin.slash")
                        }
                    } preview: {
                        studentPreview(entry)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func pinnedFriendCell(_ entry: StudentEntry) -> some View {
        VStack(spacing: 6) {
            avatarView(for: entry, size: 56)

            Text(entry.name.split(separator: " ").first.map(String.init) ?? entry.name)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }

    // MARK: - Classmates Section

    private var classmatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Classmates")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)

            let classmates = viewModel.classmates(for: student)
            if classmates.isEmpty {
                Text("No classmates found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 32)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(classmates) { entry in
                        studentRow(entry)
                    }
                }
            }
        }
    }

    // MARK: - Search Results Section

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let results = viewModel.searchResults
            if results.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No results found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(results) { entry in
                        studentRow(entry)
                    }
                }
            }
        }
    }

    // MARK: - Student Row

    private func studentRow(_ entry: StudentEntry) -> some View {
        NavigationLink(value: "student_\(entry.studentId)") {
            HStack(spacing: 12) {
                avatarView(for: entry, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(entry.className)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                viewModel.togglePin(for: entry.studentId, currentStudentId: student.studentId)
            } label: {
                if viewModel.isPinned(entry.studentId) {
                    Label("Unpin Friend", systemImage: "pin.slash")
                } else {
                    Label("Pin Friend", systemImage: "pin")
                }
            }
        } preview: {
            studentPreview(entry)
        }
        .task {
            await viewModel.fetchPictureIdIfNeeded(for: entry, authenticatedStudent: student)
        }
    }

    // MARK: - Avatar View

    private func avatarView(for entry: StudentEntry, size: CGFloat) -> some View {
        Group {
            if let url = viewModel.pictureURL(for: entry) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        initialsView(for: entry, size: size)
                    default:
                        initialsView(for: entry, size: size)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                initialsView(for: entry, size: size)
            }
        }
    }

    private func initialsView(for entry: StudentEntry, size: CGFloat) -> some View {
        Text(entry.initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Self.avatarColors[entry.color % Self.avatarColors.count])
            .clipShape(Circle())
    }

    // MARK: - Context Menu Preview

    private func studentPreview(_ entry: StudentEntry) -> some View {
        VStack(spacing: 12) {
            avatarView(for: entry, size: 120)

            Text(entry.name)
                .font(.title3)
                .fontWeight(.semibold)

            Text(entry.className)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 240)
    }
}

#Preview {
    NavigationStack {
        StudentSearchView(
            student: Student(studentId: "12345", gymId: 94, name: "Test Student"),
            authViewModel: AuthenticationViewModel()
        )
    }
}
```

**Step 2: Verify it compiles**

Run: `xcodebuild build -project BetterLectio.xcodeproj -scheme BetterLectio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add BetterLectio/StudentSearchView.swift
git commit -m "Add StudentSearchView with pinned friends grid, classmate list, and search"
```

---

### Task 7: Wire up navigation from HomeView

**Files:**
- Modify: `BetterLectio/ContentView.swift`

**Step 1: Add Students card to HomeView**

In `HomeView`, find the `HStack` with the placeholder cards:

```swift
// Current code:
HStack(spacing: 16) {
    HomeCard(title: "Grades", icon: "chart.bar.fill", color: .purple)
    HomeCard(title: "Homework", icon: "doc.text.fill", color: .orange)
}
```

Replace it with:

```swift
HStack(spacing: 16) {
    NavigationLink(value: "students") {
        HomeCard(title: "Students", icon: "person.2.fill", color: .green)
    }
    .buttonStyle(.plain)
    HomeCard(title: "Homework", icon: "doc.text.fill", color: .orange)
}
```

**Step 2: Add navigation destination for students**

In `ContentView`, find the `.navigationDestination`:

```swift
.navigationDestination(for: String.self) { value in
    if value == "schedule" {
        ScheduleView(student: student, authViewModel: authViewModel)
    }
}
```

Replace with:

```swift
.navigationDestination(for: String.self) { value in
    if value == "schedule" {
        ScheduleView(student: student, authViewModel: authViewModel)
    } else if value == "students" {
        StudentSearchView(student: student, authViewModel: authViewModel)
    } else if value.hasPrefix("student_") {
        let targetId = String(value.dropFirst("student_".count))
        let targetStudent = Student(studentId: targetId, gymId: student.gymId, name: nil)
        ScheduleView(student: targetStudent, authViewModel: authViewModel)
    }
}
```

**Step 3: Verify it compiles**

Run: `xcodebuild build -project BetterLectio.xcodeproj -scheme BetterLectio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add BetterLectio/ContentView.swift
git commit -m "Wire up student search navigation from HomeView"
```

---

### Task 8: Verify end-to-end on simulator

**Step 1: Build and run on simulator**

Run: `xcodebuild build -project BetterLectio.xcodeproj -scheme BetterLectio -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED with no warnings related to new code

**Step 2: Review all changes**

Run: `git diff HEAD~7 --stat` to confirm all expected files were created/modified:
- `Models.swift` — StudentEntry added
- `LectioParser.swift` — parseStudentList + parseStudentPictureId added
- `LectioHTTPClient.swift` — fetchStudentList + fetchStudentPage added
- `StudentStore.swift` — new file
- `StudentSearchViewModel.swift` — new file
- `StudentSearchView.swift` — new file
- `ContentView.swift` — navigation wired up

**Step 3: Final commit (if any fixes needed)**

Address any compilation issues and commit fixes.
