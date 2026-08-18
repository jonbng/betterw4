//
//  HomeViewModel.swift
//  BetterW4
//
//  The Home screen's view model (plan Wave 6, vertical 6 — the W4-only surfaces).
//
//  One `r=site/index` response feeds this whole screen: the greeting, today's rotation day, both
//  attendance meters, birthdays, announcements and the configured Links block. `HomeRepository`
//  owns the fetch, the cache and the demo branch; this file owns nothing but presentation state.
//
//  The four behaviours from features.md §3 that this screen must keep:
//
//    1. a generation token guards every published mutation, so a slow response can never overwrite
//       a newer selection (or a newer account);
//    2. the cached snapshot paints first, then the network refreshes it;
//    3. the spinner appears only when there is nothing cached to show;
//    4. a transient failure never wipes what is on screen — the error surfaces only when the screen
//       would otherwise be blank. `W4Error.sessionExpired` is still posted so the app can re-login;
//       `.forbidden` is deliberately not, because wrong role is not a dead session.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var snapshot: HomeSnapshot?
    @Published private(set) var freshness: W4Freshness?
    /// Blocking spinner. True only while there is nothing cached to render.
    @Published private(set) var isLoading = false
    /// Set only when the screen would otherwise be blank (features.md §3 rule 4).
    @Published private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let repository: HomeRepository
    private var loadGeneration: UUID?
    private var activeStudentID: String?

    init(repository: HomeRepository = .shared) {
        self.repository = repository
    }

    // MARK: - Loading

    /// Cache-first load, then a live refresh. Safe to call on every `.task`.
    func load(student: Student? = nil) async {
        await run(student: student, forceRefresh: false)
    }

    /// Pull-to-refresh: skip the TTL, keep whatever is on screen if the fetch fails.
    func refresh(student: Student? = nil) async {
        await run(student: student, forceRefresh: true)
    }

    private func run(student: Student?, forceRefresh: Bool) async {
        let generation = UUID()
        loadGeneration = generation

        // Rule 5: switching accounts (most often demo ⇄ real) must never show the previous
        // student's Home page for even one frame.
        let identity = student?.studentId ?? W4RequestContext.current()?.uwcId
        if let identity, activeStudentID != identity {
            snapshot = nil
            freshness = nil
            errorMessage = nil
        }
        if let identity { activeStudentID = identity }

        // Rule 2: paint the cached copy before asking the network for anything.
        if !forceRefresh, snapshot == nil, let cached = await repository.cachedSnapshot() {
            guard loadGeneration == generation else { return }
            apply(cached)
        }

        // Rule 3: a spinner only when there is nothing to look at.
        if snapshot == nil { isLoading = true }

        do {
            let loaded = try await repository.snapshot(forceRefresh: forceRefresh)
            guard loadGeneration == generation else { return }
            apply(loaded)
            errorMessage = nil
        } catch {
            guard loadGeneration == generation else { return }
            handle(error)
        }

        if loadGeneration == generation { isLoading = false }
    }

    private func apply(_ loaded: W4Loaded<HomeSnapshot>) {
        snapshot = loaded.value
        freshness = loaded.freshness
    }

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if (error as? URLError)?.code == .cancelled { return }
        // Only `.sessionExpired` logs the user out; `.forbidden` never does.
        (error as? W4Error)?.notifyIfSessionExpired()
        // Rule 4: offline with a warm cache is a working app, not an error screen.
        guard snapshot == nil else { return }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Derived state

    var isDemo: Bool { freshness == .demo }

    var page: HomePage? { snapshot?.page }

    /// "Hello, Alex Andersen" when W4 named the student, a plain greeting otherwise.
    var greeting: String {
        if let name = page?.greetingName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Hello, \(name)"
        }
        return "Hello"
    }

    var uwcId: String? { page?.uwcId }

    /// Today's rotation day, read from the week grid Home embeds — "Day 3", "Weekend", …
    ///
    /// Matched on the calendar date rather than on W4's own `column current` class: a cached page
    /// keeps yesterday's highlight, and a rotation day that is one day out is worse than none.
    var todayRotationDay: String? {
        guard let days = snapshot?.week?.days else { return nil }
        let today = TimeProvider.now
        guard let day = days.first(where: { W4Dates.isSameDay($0.date, today) }) else { return nil }
        guard let rotation = day.rotationDay?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rotation.isEmpty else { return nil }
        return rotation
    }

    /// True when W4 marked today "no classes". Rendered next to the rotation day.
    var isTodayNoClasses: Bool {
        guard let days = snapshot?.week?.days else { return false }
        let today = TimeProvider.now
        return days.first { W4Dates.isSameDay($0.date, today) }?.isNoClasses ?? false
    }

    /// Today's Extra Academics line from the week header ("No EA", an activity name, …).
    var todayExtraAcademicsNote: String? {
        guard let days = snapshot?.week?.days else { return nil }
        let today = TimeProvider.now
        guard let note = days.first(where: { W4Dates.isSameDay($0.date, today) })?.eaNote else {
            return nil
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var meters: AttendanceMeters { snapshot?.meters ?? .empty }

    var birthdaysToday: [HomeBirthday] { page?.birthdaysToday ?? [] }
    var birthdaysTomorrow: [HomeBirthday] { page?.birthdaysTomorrow ?? [] }
    var hasBirthdays: Bool { !birthdaysToday.isEmpty || !birthdaysTomorrow.isEmpty }
    var birthdaysCalendarURL: URL? { page?.birthdaysCalendarURL }

    var announcements: [HomeAnnouncement] { page?.announcements ?? [] }

    /// W4's own empty-state sentence, verbatim ("No announcements..."), when it said one.
    var announcementsEmptyText: String? { page?.announcementsEmptyText }
    var announcementsRSSURL: URL? { page?.announcementsRSSURL }

    /// The `#links` block exactly as W4 configured it. Never hardcoded (features.md §1.16).
    var links: [HomeLink] { page?.links ?? [] }

    var serverVersion: String? { page?.serverVersion }
    var releaseNotesURL: URL? { page?.releaseNotesURL }

    /// True when the load finished but W4 gave us nothing renderable.
    var isEmpty: Bool {
        guard let snapshot else { return true }
        return snapshot.isEmpty
    }

    // MARK: - Links

    /// Where one Home link goes. Internal W4 destinations stay in the app; ManageBac, Google Sites,
    /// Drive and Forms leave for Safari (README §7 — ManageBac is a link, never a scrape).
    enum LinkDestination: Equatable {
        /// A CMS folder or page, rendered by `DocumentsView`.
        case documents(library: DocumentLibrary, route: String)
        /// `academics/trips`, rendered by `TripsView`.
        case trips
        /// Any other W4 route: the authenticated in-app page.
        case w4Page(URL)
        /// A third-party destination: Safari.
        case external(URL)
    }

    func destination(for link: HomeLink) -> LinkDestination {
        guard link.isInternalRoute else { return .external(link.url) }

        let route = link.route ?? W4Routes.route(of: link.url) ?? ""
        let name = W4Routes.splitRouteAndQuery(route).route.lowercased()

        if name.hasPrefix("documents") || name.hasPrefix("extraacademics/documents") {
            return .documents(library: DocumentLibrary.library(forRoute: route), route: route)
        }
        if name.hasPrefix(W4Routes.R.trips) {
            return .trips
        }
        return .w4Page(link.url)
    }

    /// An SF Symbol for a link row, chosen from the destination rather than from its title.
    func symbol(for link: HomeLink) -> String {
        switch destination(for: link) {
        case .documents: return "doc.text"
        case .trips: return "suitcase"
        case .w4Page: return "arrow.up.forward.square"
        case .external: return "safari"
        }
    }
}
