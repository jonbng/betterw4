//
//  TripsViewModel.swift
//  BetterW4
//
//  Boarding travel: `academics/trips` (My trips) and `academics/travel/travel.list`
//  (the four fixed journeys) — features.md §1.9, ui.md §4.12 / §4.13.
//
//  Two repositories, one screen, because that is how a student thinks about it: "when am I allowed
//  to leave, and have I filed the form for it". Read-only in v1 — planning a trip and filling in a
//  travel form open the W4 page in the in-app browser with the session cookie (plan D-24), because
//  neither form's POST payload has ever been captured and inventing one would post garbage.
//
//  Both halves load independently: a failed travel-forms fetch must not blank the trip list the
//  student actually opened the screen for.
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class TripsViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var tripList: TripList?
    @Published private(set) var tripsFreshness: W4Freshness?
    @Published private(set) var travelPage: TravelPage?
    @Published private(set) var travelFreshness: W4Freshness?
    @Published private(set) var contacts: [TravelContact] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let tripRepository: TripRepository
    private let travelRepository: TravelRepository
    private var loadGeneration: UUID?

    init(
        trips: TripRepository = TripRepository(),
        travel: TravelRepository = TravelRepository()
    ) {
        self.tripRepository = trips
        self.travelRepository = travel
    }

    // MARK: - Loading

    func load() async {
        await run(forceRefresh: false)
    }

    func refresh() async {
        await run(forceRefresh: true)
    }

    private func run(forceRefresh: Bool) async {
        let generation = UUID()
        loadGeneration = generation

        if !forceRefresh, tripList == nil {
            if let cached = await tripRepository.cachedTrips() {
                guard loadGeneration == generation else { return }
                tripList = cached.value
                tripsFreshness = cached.freshness
            }
            if let cached = await travelRepository.cachedTravelForms() {
                guard loadGeneration == generation else { return }
                travelPage = cached.value
                travelFreshness = cached.freshness
            }
        }

        if tripList == nil, travelPage == nil { isLoading = true }

        // The trip grid is what the screen is titled after, so it goes first through the serial
        // request gate.
        do {
            let loaded = try await tripRepository.loadTrips(forceRefresh: forceRefresh)
            guard loadGeneration == generation else { return }
            tripList = loaded.value
            tripsFreshness = loaded.freshness
            errorMessage = nil
        } catch {
            guard loadGeneration == generation else { return }
            handle(error)
        }

        do {
            let loaded = try await travelRepository.loadTravelFormsWithContacts(forceRefresh: forceRefresh)
            guard loadGeneration == generation else { return }
            travelPage = loaded.forms.value
            travelFreshness = loaded.forms.freshness
            if let contacts = loaded.contacts { self.contacts = contacts.value }
        } catch {
            guard loadGeneration == generation else { return }
            handle(error)
        }

        if loadGeneration == generation { isLoading = false }
    }

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if (error as? URLError)?.code == .cancelled { return }
        (error as? W4Error)?.notifyIfSessionExpired()
        // Only when the whole screen would be blank (features.md §3 rule 4).
        guard tripList == nil, travelPage == nil else { return }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Derived state

    var isDemo: Bool { tripsFreshness == .demo || travelFreshness == .demo }

    var trips: [Trip] { tripList?.trips ?? [] }

    /// W4's own empty sentence when it wrote one, so a real "No results found." is never replaced
    /// by our guess.
    var tripsEmptyMessage: String {
        let message = tripList?.emptyMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return message.isEmpty ? "No trips." : message
    }

    /// True when W4 paged the grid: we show one page and say so rather than pretending it is all.
    var hasMoreTrips: Bool { tripList?.hasMorePages ?? false }

    var canPlanNewTrip: Bool { tripList?.canPlanNewTrip ?? false }

    /// Where "Plan new trip" goes. The href when W4 rendered one, the trips page otherwise.
    var planNewTripURL: URL {
        if let href = tripList?.planNewTripHref, !href.isEmpty {
            return W4Routes.resolve(href)
        }
        return W4Routes.url(W4Routes.R.trips)
    }

    /// The four fixed journeys in academic-year order, then anything W4 rendered that is not one
    /// of them.
    var travelForms: [TravelForm] { travelPage?.sortedForms ?? [] }

    var travelEmptyMessage: String {
        let message = travelPage?.emptyMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return message.isEmpty ? "No travel forms." : message
    }

    var manageContactsURL: URL? {
        guard let page = travelPage else { return nil }
        if let route = page.manageContactsRoute, !route.isEmpty {
            return W4Routes.url(route)
        }
        if let href = page.manageContactsHref, !href.isEmpty {
            return W4Routes.resolve(href)
        }
        return nil
    }

    var manageContactsLabel: String {
        travelPage?.manageContactsLabel ?? "Manage my travel contacts"
    }

    var freshness: W4Freshness? { tripsFreshness ?? travelFreshness }

    var isEmpty: Bool {
        trips.isEmpty && travelForms.isEmpty && contacts.isEmpty
    }

    func url(for form: TravelForm) -> URL? {
        if let route = form.route, !route.isEmpty { return W4Routes.url(route) }
        if let href = form.href, !href.isEmpty { return W4Routes.resolve(href) }
        return nil
    }

    func url(for trip: Trip) -> URL? {
        if let route = trip.route, !route.isEmpty { return W4Routes.url(route) }
        if let href = trip.href, !href.isEmpty { return W4Routes.resolve(href) }
        return nil
    }

    /// Planning grey · Pending confirmation amber · Approved green · Cancelled red.
    static func tint(for status: TripStatus) -> Color {
        switch status {
        case .planning: return .secondary
        case .pendingConfirmation: return .orange
        case .approved: return .green
        case .cancelled: return .red
        case .unknown: return .secondary
        }
    }

    static func symbol(for status: TripStatus) -> String {
        switch status {
        case .planning: return "pencil.and.list.clipboard"
        case .pendingConfirmation: return "clock"
        case .approved: return "checkmark.seal"
        case .cancelled: return "xmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    /// `20-Sep-2026 08:00 → 21-Sep-2026 18:00`, using whatever W4 printed when we could not parse
    /// a date out of it.
    static func dateRange(for trip: Trip) -> String? {
        let out = trip.outgoingLabel ?? trip.outgoing.map(W4Dates.formatDateTime)
        let back = trip.returningLabel ?? trip.returning.map(W4Dates.formatDateTime)
        switch (out, back) {
        case (let out?, let back?): return "\(out) → \(back)"
        case (let out?, nil): return out
        case (nil, let back?): return back
        default: return nil
        }
    }
}
