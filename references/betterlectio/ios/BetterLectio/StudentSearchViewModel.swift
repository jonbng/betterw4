//
//  StudentSearchViewModel.swift
//  BetterLectio
//

import Combine
import Foundation
import SwiftUI

@MainActor
class StudentSearchViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var allStudents: [StudentEntry] = []
    @Published var searchQuery = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pinnedFriendIds: Set<String> = []
    @Published var pictureIds: [String: String] = [:] // studentId -> pictureId
    /// Fallback class for current student when not found in dropdown (e.g. "3a")
    @Published var currentStudentClassName: String?

    // MARK: - Services

    private let httpClient = LectioHTTPClient()
    private let store = StudentStore.shared
    private let studentManager = StudentManager.shared
    private let keychainManager = KeychainManager.shared
    
    // MARK: - Computed Properties

    /// Pinned friends from allStudents
    var pinnedFriends: [StudentEntry] {
        allStudents.filter { pinnedFriendIds.contains($0.studentId) }
    }

    /// Classmates: same class as current student (e.g. 3a, not just same year)
    func classmates(for student: Student) -> [StudentEntry] {
        // Get current student's class from dropdown list or fallback from homepage
        let myClass: String
        if let record = allStudents.first(where: { $0.studentId == student.studentId }) {
            myClass = record.classLabel
        } else if let fallback = currentStudentClassName {
            myClass = fallback
        } else {
            return []
        }
        let normalized = myClass.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return [] }
        return allStudents.filter {
            $0.type == .student
                && $0.classLabel.trimmingCharacters(in: .whitespaces) == normalized
                && $0.studentId != student.studentId
        }
    }

    /// Search results using fuzzy matching (max 20 results)
    var searchResults: [StudentEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        return Array(fuzzySearch(query: query, in: allStudents).prefix(20))
    }

    /// All students in a given class (excluding teachers)
    func students(inClass className: String) -> [StudentEntry] {
        let normalized = className.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return [] }
        return allStudents.filter {
            $0.type == .student
                && $0.classLabel.trimmingCharacters(in: .whitespaces) == normalized
        }
    }

    var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Unique base class names extracted from all students (e.g. "1x", "2c", "3a")
    var uniqueClasses: [String] {
        let classes = Set(
            allStudents
                .filter { $0.type == .student }
                .map { $0.displayClass }
                .filter { !$0.isEmpty }
        )
        return classes.sorted()
    }

    /// Classes matching the current search query
    var classSearchResults: [String] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return Array(
            uniqueClasses
                .filter { $0.lowercased().contains(query) }
                .prefix(5)
        )
    }

    /// Count of students in a given class
    func studentCount(inClass className: String) -> Int {
        students(inClass: className).count
    }

    // MARK: - Load Students

    /// Loads students from cache or fetches from Lectio via StudentManager
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

        // If few students are cached (e.g. < 10), trigger sync if not already syncing
        if cached.count < 10 {
            isLoading = true
            await studentManager.syncStudents(for: student)
            allStudents = store.loadStudents(for: student.gymId)
            isLoading = false
        }
    }

    /// Manually triggers a full sync via StudentManager
    func refreshAllStudents(for student: Student) async {
        isLoading = true
        await studentManager.syncStudents(for: student)
        allStudents = store.loadStudents(for: student.gymId)
        isLoading = false
    }

    // MARK: - Pinned Friends (Kept here as it is UI state related)

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
        // Only teachers and students have profile pictures
        guard entry.type == .student || entry.type == .teacher else { return }

        // Already have it in memory
        if pictureIds[entry.studentId] != nil { return }

        // Check store
        if let cached = store.loadPictureId(for: entry.studentId, gymId: entry.gymId) {
            pictureIds[entry.studentId] = cached
            return
        }

        // Fetch via shared StudentStore method
        await store.fetchPictureIdIfNeeded(
            personId: entry.studentId,
            gymId: entry.gymId,
            isTeacher: entry.isTeacher,
            authenticatedStudentId: authenticatedStudent.studentId,
            personName: entry.name
        )

        // Update local cache from store
        if let pictureId = store.loadPictureId(for: entry.studentId, gymId: entry.gymId) {
            pictureIds[entry.studentId] = pictureId
        }
    }

    /// Returns the full image URL for a student (if picture ID is known)
    func pictureURL(for entry: StudentEntry) -> URL? {
        guard let pictureId = pictureIds[entry.studentId] else { return nil }
        return URL(string: "https://www.lectio.dk/lectio/\(entry.gymId)/GetImage.aspx?pictureid=\(pictureId)&fullsize=1")
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
