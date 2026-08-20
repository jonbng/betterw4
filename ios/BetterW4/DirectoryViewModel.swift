//
//  DirectoryViewModel.swift
//  BetterW4
//
//  The people directory, on top of `DirectoryRepository` and `ProfileRepository`.
//
//  W4's people surface is small and flat: students (all / first year / second year) and staff
//  (my teachers / current staff), every one of them keyed on a UWC id. There are no classes as
//  entities, no courses, no rooms in the people directory, and no per-person timetable route —
//  so this view model has exactly two kinds of row, `.student` and `.staff`.
//
//  Behaviours preserved from the pre-port app (`docs/spec/features.md` §3):
//    * **Cache first, then refresh.** Every load paints the stored table before it asks W4.
//    * **A spinner only when there is nothing to show.** A refresh over cached rows is silent.
//    * **Generation guards.** A slow answer for a screen the student has already left can never
//      overwrite the newer one.
//    * **Never wipe on a transient error.** A failed refresh keeps the rows that were on screen
//      and says nothing; the error banner is only for an empty screen.
//    * **`.forbidden` does not log anybody out.** Only `.sessionExpired` posts `.w4SessionExpired`.
//
//  Search runs off this actor: `DirectoryRepository.search` is an `actor` method, so the scan
//  happens on the repository's executor and only the ranked result hops back to the main actor.
//
//  PII: names and UWC ids are never logged.
//

import Combine
import Foundation

// MARK: - Presentation

/// Which slice of W4's people the directory screen is showing.
enum DirectoryPresentation: Hashable {
    /// Students: pinned classmates, then the year lists.
    case full
    /// The signed-in student's own IB year.
    case classmates
    /// `people/students/staff&type=teachers`, falling back to all current staff.
    case teachers
    case firstYear
    case secondYear
    case staff

    var title: String {
        switch self {
        case .full: return "Students"
        case .classmates: return "Classmates"
        case .teachers: return "Teachers"
        case .firstYear: return "First year"
        case .secondYear: return "Second year"
        case .staff: return "Staff"
        }
    }

    /// The W4 list this presentation refreshes from, or `nil` when it reads the whole table.
    var source: PeopleDirectorySource? {
        switch self {
        case .full, .classmates: return nil
        case .teachers: return .myTeachers
        case .firstYear: return .firstYear
        case .secondYear: return .secondYear
        case .staff: return .currentStaff
        }
    }

    /// The two roles the directory switcher offers.
    var showsStaff: Bool {
        switch self {
        case .teachers, .staff: return true
        case .full, .classmates, .firstYear, .secondYear: return false
        }
    }

    var yearFilter: DirectoryYearFilter {
        switch self {
        case .firstYear: return .first
        case .secondYear: return .second
        case .full, .classmates, .teachers, .staff: return .all
        }
    }
}

/// Year slice shown under Students.
enum DirectoryYearFilter: Hashable {
    case all
    case first
    case second

    var presentation: DirectoryPresentation {
        switch self {
        case .all: return .full
        case .first: return .firstYear
        case .second: return .secondYear
        }
    }
}

// MARK: - Sections

/// One titled block of people on the directory screen.
struct DirectoryPeopleSection: Identifiable, Sendable {
    let id: String
    let title: String
    let people: [DirectoryPerson]

    init(id: String, title: String, people: [DirectoryPerson]) {
        self.id = id
        self.title = title
        self.people = people
    }
}

/// The legacy section shape the message composer's recipient picker still reads.
struct DirectorySearchSection: Identifiable, Sendable {
    let title: String
    let entities: [DirectoryEntity]

    var id: String { title }
}

// MARK: - View model

@MainActor
final class DirectoryViewModel: ObservableObject {

    // MARK: Published state

    /// Everybody the app knows about, whatever the current presentation is. Search and the
    /// legacy composer API read this.
    @Published private(set) var allPeople: [DirectoryPerson] = []
    /// The rows the current presentation shows.
    @Published private(set) var visiblePeople: [DirectoryPerson] = []
    @Published private(set) var pinnedPeople: [DirectoryPerson] = []
    @Published private(set) var pinnedUwcIds: Set<String> = []
    @Published private(set) var searchResults: [DirectoryPerson] = []

    /// True only while there is nothing on screen yet. A refresh over cached rows is silent.
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    /// Where the rows on screen came from, so the footer can be honest about a stale copy.
    @Published private(set) var freshness: W4Freshness?
    /// Only ever set while the screen is empty — a failed refresh never clears good rows.
    @Published private(set) var errorMessage: String?
    /// W4's own empty-state text (`div.note`), e.g. "No users found".
    @Published private(set) var notice: String?

    @Published var searchQuery = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            scheduleSearch()
        }
    }

    // MARK: Dependencies

    private let directory: DirectoryRepository
    private let profiles: ProfileRepository

    // MARK: Private state

    /// Bumped by every load. A response tagged with an older generation is dropped, so a slow
    /// answer for a screen the student has left cannot overwrite the newer one.
    private var generation = 0
    private var searchGeneration = 0
    private var searchTask: Task<Void, Never>?
    @Published private(set) var presentation: DirectoryPresentation = .full
    /// Last Students-side slice, so Teachers → Students restores All / 1st / 2nd.
    private var studentPresentation: DirectoryPresentation = .full
    /// The signed-in student's own IB year, from `site/profile`. Drives "Classmates".
    private var myYear: String?
    private var myUwcId: String?

    init(
        directory: DirectoryRepository = .shared,
        profiles: ProfileRepository = .shared
    ) {
        self.directory = directory
        self.profiles = profiles
    }

    // MARK: - Loading

    /// Switch the Students/Teachers slice without a full reload when the catalog is already here.
    func show(_ presentation: DirectoryPresentation) async {
        guard self.presentation != presentation else { return }
        rememberStudentSlice(presentation)
        self.presentation = presentation
        notice = nil
        applyVisible(for: presentation)
        rerunSearchIfNeeded()
        if visiblePeople.isEmpty && pinnedPeople.isEmpty {
            await load(presentation)
        }
    }

    /// Restore the last Students year filter after leaving Teachers.
    func showStudents() async {
        await show(studentPresentation.showsStaff ? .full : studentPresentation)
    }

    private func rememberStudentSlice(_ presentation: DirectoryPresentation) {
        if !presentation.showsStaff {
            studentPresentation = presentation
        }
    }

    /// Cache-first load: paint what is stored, then refresh in the background.
    func load(_ presentation: DirectoryPresentation) async {
        generation += 1
        let token = generation
        rememberStudentSlice(presentation)
        self.presentation = presentation
        notice = nil

        let pins = await directory.pinnedUwcIds()
        guard isCurrent(token) else { return }
        pinnedUwcIds = pins

        let stored = await directory.storedPeople()
        guard isCurrent(token) else { return }
        applyAllPeople(stored)

        if let source = presentation.source,
           let cached = await directory.cachedPeople(source: source) {
            guard isCurrent(token) else { return }
            apply(page: cached.value, freshness: cached.freshness)
        } else {
            // The stored table carries no timestamp of its own, so `freshness` stays unset until
            // the refresh below answers. An unknown age is better than an invented one.
            applyVisible(for: presentation)
        }

        // A spinner is only ever justified by an empty screen.
        isLoading = visiblePeople.isEmpty && pinnedPeople.isEmpty
        errorMessage = nil

        await resolveMyYear(token: token)
        await refresh(force: false, token: token)
    }

    /// Pull-to-refresh: always goes to W4, and still never clears what is on screen.
    func refresh() async {
        generation += 1
        await refresh(force: true, token: generation)
    }

    private func refresh(force: Bool, token: Int) async {
        guard isCurrent(token) else { return }
        isRefreshing = true
        // Generation only: a cancelled task must still put the spinner away for this screen.
        defer {
            if token == generation {
                isRefreshing = false
                isLoading = false
            }
        }

        do {
            if let source = presentation.source {
                let loaded = try await directory.people(source: source, forceRefresh: force)
                guard isCurrent(token) else { return }
                apply(page: loaded.value, freshness: loaded.freshness)
                let stored = await directory.storedPeople()
                guard isCurrent(token) else { return }
                applyAllPeople(stored)
            } else {
                let loaded = try await directory.syncFullDirectory(forceRefresh: force)
                guard isCurrent(token) else { return }
                applyAllPeople(loaded.value)
                applyVisible(for: presentation)
                freshness = loaded.freshness
                notice = loaded.value.isEmpty ? "No people found" : nil
            }
            errorMessage = nil
            rerunSearchIfNeeded()
        } catch {
            guard isCurrent(token) else { return }
            if error is CancellationError { return }
            // Only a dead session logs anybody out. `.forbidden` is a wrong-role answer and
            // must leave the session alone (features.md §3).
            (error as? W4Error)?.notifyIfSessionExpired()
            // Never wipe: rows already on screen survive a failed refresh untouched.
            if visiblePeople.isEmpty && pinnedPeople.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Reloads after "clear caches", without the instant-paint stage.
    func reloadAfterCacheClear() async {
        allPeople = []
        visiblePeople = []
        pinnedPeople = []
        freshness = nil
        await load(presentation)
    }

    private func isCurrent(_ token: Int) -> Bool {
        token == generation && !Task.isCancelled
    }

    // MARK: - Applying

    private func apply(page: DirectoryPeoplePage, freshness: W4Freshness) {
        visiblePeople = page.people
        notice = page.people.isEmpty ? (page.notice ?? "No people found") : nil
        self.freshness = freshness
        rebuildPinned()
    }

    private func applyAllPeople(_ people: [DirectoryPerson]) {
        allPeople = people
        rebuildPinned()
    }

    private func applyVisible(for presentation: DirectoryPresentation) {
        switch presentation {
        case .full:
            visiblePeople = students
        case .classmates:
            visiblePeople = self.classmates
        case .teachers, .staff:
            visiblePeople = staff
        case .firstYear:
            visiblePeople = students.filter { $0.year == "1" }
        case .secondYear:
            visiblePeople = students.filter { $0.year == "2" }
        }
        if visiblePeople.isEmpty, !allPeople.isEmpty {
            notice = "No people found"
        }
    }

    private func rebuildPinned() {
        guard !pinnedUwcIds.isEmpty else {
            pinnedPeople = []
            return
        }
        pinnedPeople = allPeople
            .filter { pinnedUwcIds.contains($0.uwcId) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// `site/profile` tells us our own IB year, which is the only thing "classmates" can mean
    /// on W4. A failure here is silent: the section just stays empty.
    ///
    /// Only the two screens that show a classmates list ask for it — the year lists and the staff
    /// list would be paying for a request they never read.
    private func resolveMyYear(token: Int) async {
        switch presentation {
        case .full, .classmates: break
        case .teachers, .firstYear, .secondYear, .staff: return
        }
        if let loaded = try? await profiles.myProfile() {
            guard isCurrent(token) else { return }
            myUwcId = loaded.value.person.uwcId
            myYear = loaded.value.person.year
            if presentation == .classmates { applyVisible(for: presentation) }
        }
    }

    // MARK: - Derived lists

    var students: [DirectoryPerson] {
        allPeople.filter { $0.kind == .student }
    }

    var staff: [DirectoryPerson] {
        allPeople.filter { $0.kind == .staff }
    }

    /// The signed-in student's year group, minus the student themselves.
    var classmates: [DirectoryPerson] {
        guard let myYear, !myYear.isEmpty else { return [] }
        return students.filter { $0.year == myYear && $0.uwcId != myUwcId }
    }

    var isSearching: Bool {
        !DirectorySearchText.normalize(searchQuery).isEmpty
    }

    /// The sections the directory screen renders when nothing is being searched for.
    var sections: [DirectoryPeopleSection] {
        var result: [DirectoryPeopleSection] = []

        let pins = pinnedPeople.filter(matchesCurrentSlice)
        if !pins.isEmpty {
            result.append(DirectoryPeopleSection(id: "pinned", title: "Pinned", people: pins))
        }

        switch presentation {
        case .full:
            let mates = self.classmates
            if !mates.isEmpty {
                let title = myYear.map { "Year \($0)" } ?? "Classmates"
                result.append(DirectoryPeopleSection(id: "classmates", title: title, people: mates))
            }
            let firstYear = students.filter { $0.year == "1" }
            let secondYear = students.filter { $0.year == "2" }
            let placed = Set(mates.map(\.uwcId))
            let restOfFirst = firstYear.filter { !placed.contains($0.uwcId) }
            let restOfSecond = secondYear.filter { !placed.contains($0.uwcId) }
            if !restOfFirst.isEmpty {
                result.append(DirectoryPeopleSection(id: "year1", title: "First year", people: restOfFirst))
            }
            if !restOfSecond.isEmpty {
                result.append(DirectoryPeopleSection(id: "year2", title: "Second year", people: restOfSecond))
            }
            let unplaced = students.filter { $0.year == nil && !placed.contains($0.uwcId) }
            if !unplaced.isEmpty {
                result.append(DirectoryPeopleSection(id: "students", title: "Students", people: unplaced))
            }
        case .classmates, .teachers, .firstYear, .secondYear, .staff:
            if !visiblePeople.isEmpty {
                result.append(
                    DirectoryPeopleSection(
                        id: "list",
                        title: presentation.title,
                        people: visiblePeople
                    )
                )
            }
        }

        return result
    }

    // MARK: - Search

    /// Debounced, ranked, and off this actor. Pins first, then classmates, then everybody else,
    /// each bucket keeping the repository's prefix-before-substring order.
    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery
        guard !DirectorySearchText.normalize(query).isEmpty else {
            searchResults = []
            return
        }

        searchGeneration += 1
        let token = searchGeneration
        let pinned = pinnedUwcIds
        let mates = Set(self.classmates.map(\.uwcId))

        let repository = directory
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            // `search` is an actor method: the scan happens off the main actor.
            let hits = await repository.search(query, limit: 40)
            guard !Task.isCancelled, let self else { return }
            guard token == self.searchGeneration, self.searchQuery == query else { return }
            let scoped = hits.filter { self.matchesCurrentSlice($0) }
            self.searchResults = Self.rank(scoped, pinned: pinned, classmates: mates)
        }
    }

    private func rerunSearchIfNeeded() {
        guard isSearching else { return }
        scheduleSearch()
    }

    private func matchesCurrentSlice(_ person: DirectoryPerson) -> Bool {
        if presentation.showsStaff { return person.kind == .staff }
        guard person.kind == .student else { return false }
        switch presentation {
        case .firstYear: return person.year == "1"
        case .secondYear: return person.year == "2"
        default: return true
        }
    }

    nonisolated static func rank(
        _ hits: [DirectoryPerson],
        pinned: Set<String>,
        classmates: Set<String>
    ) -> [DirectoryPerson] {
        var pinnedHits: [DirectoryPerson] = []
        var classmateHits: [DirectoryPerson] = []
        var rest: [DirectoryPerson] = []
        for person in hits {
            if pinned.contains(person.uwcId) {
                pinnedHits.append(person)
            } else if classmates.contains(person.uwcId) {
                classmateHits.append(person)
            } else {
                rest.append(person)
            }
        }
        return pinnedHits + classmateHits + rest
    }

    // MARK: - Pins

    func isPinned(_ person: DirectoryPerson) -> Bool {
        pinnedUwcIds.contains(person.uwcId)
    }

    func togglePin(_ person: DirectoryPerson) {
        // Optimistic: the pin is local state, so the row flips immediately and the store catches up.
        if pinnedUwcIds.contains(person.uwcId) {
            pinnedUwcIds.remove(person.uwcId)
        } else {
            pinnedUwcIds.insert(person.uwcId)
        }
        rebuildPinned()
        let pinned = pinnedUwcIds.contains(person.uwcId)
        let uwcId = person.uwcId
        let repository = directory
        Task {
            await repository.setPinned(pinned, uwcId: uwcId)
        }
    }

    // MARK: - Lookup

    func person(uwcId: String) -> DirectoryPerson? {
        let id = uwcId.lowercased()
        return allPeople.first { $0.uwcId == id } ?? visiblePeople.first { $0.uwcId == id }
    }

    /// The photo W4 serves for a person: `{uwc_id}.jpg`. Views fall back to initials.
    nonisolated func photoURL(for person: DirectoryPerson) -> URL? {
        person.photoURL ?? W4PeopleParser.photoURL(forUWCId: person.uwcId)
    }
}

// MARK: - Legacy composer bridge

/// The message composer's recipient picker still speaks `DirectoryEntity`. Everything below is a
/// view of the same W4 people, in that shape — no second sync, no second store. Delete it with
/// the picker.
extension DirectoryViewModel {

    var entities: [DirectoryEntity] {
        allPeople.map(DirectoryStore.legacyEntity)
    }

    var teachers: [DirectoryEntity] {
        staff.map(DirectoryStore.legacyEntity)
    }

    var messageRecipients: [DirectoryEntity] {
        allPeople.map(DirectoryStore.legacyEntity)
    }

    func classmates(for student: Student) -> [DirectoryEntity] {
        self.classmates.map(DirectoryStore.legacyEntity)
    }

    func myTeachers(for student: Student) -> [DirectoryEntity] {
        staff.map(DirectoryStore.legacyEntity)
    }

    func searchSections() -> [DirectorySearchSection] {
        guard isSearching else { return [] }
        let people = searchResults.filter { $0.kind == .student }.map(DirectoryStore.legacyEntity)
        let staffHits = searchResults.filter { $0.kind == .staff }.map(DirectoryStore.legacyEntity)
        return [
            DirectorySearchSection(title: "People", entities: people),
            DirectorySearchSection(title: "Staff", entities: staffHits)
        ].filter { !$0.entities.isEmpty }
    }

    func loadDirectory(for student: Student) async {
        await load(.full)
    }

    func refreshDirectory(for student: Student) async {
        await refresh()
    }
}
