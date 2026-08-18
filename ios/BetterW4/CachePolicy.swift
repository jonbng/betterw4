//
//  CachePolicy.swift
//  BetterW4
//
//  One place where every cache lifetime is written down (features.md §2.5).
//
//  Android's SimpleCache never expires anything — a bug we are deliberately not porting. Here a
//  surface declares its TTL once, and both the page cache and the repositories read it from here,
//  so "how stale may the timetable be?" has exactly one answer in the codebase.
//

import Foundation

/// Every W4 surface the app caches. The raw value is the cache-key namespace on disk.
enum W4Surface: String, CaseIterable, Sendable {
    case home
    case timetableAcademics
    case timetableExtraAcademics
    case assessments
    case mailInbox
    case mailArchive
    case mailMessage
    case attendanceAcademics
    case attendanceExtraAcademics
    case attendanceMeters
    case grades
    case documents
    case trips
    case travel
    case people
    case profile
    case extraAcademics
    case resources
    case feeds
    case chrome
}

enum CachePolicy {

    /// How long a cached page may be served before the repository must refetch.
    ///
    /// The numbers follow one rule: how badly does a student suffer from stale data here?
    /// A timetable that is an hour out of date is misleading, a document CMS page is not.
    static func ttl(for surface: W4Surface) -> TimeInterval {
        switch surface {
        case .chrome:
            return 60                    // campus chip + bell, matching W4's own 60s poll
        case .mailInbox, .mailArchive:
            return 5 * 60
        case .home, .assessments, .attendanceMeters:
            return 15 * 60
        case .timetableAcademics, .timetableExtraAcademics:
            return 30 * 60
        case .attendanceAcademics, .attendanceExtraAcademics, .grades, .trips, .travel:
            return 30 * 60
        case .extraAcademics, .resources, .profile:
            return 60 * 60
        case .documents, .feeds:
            return 6 * 60 * 60
        case .mailMessage:
            return .infinity             // a sent message body never changes
        case .people:
            return 7 * 24 * 60 * 60      // the directory is a weekly sync, not a live feed
        }
    }

    /// True when a cached page fetched at `fetchedAt` may still be shown without refetching.
    static func isFresh(_ fetchedAt: Date, for surface: W4Surface, now: Date = TimeProvider.now) -> Bool {
        let ttl = ttl(for: surface)
        guard ttl.isFinite else { return true }
        return now.timeIntervalSince(fetchedAt) < ttl
    }
}

/// Where a value came from, so the UI can say "showing yesterday's copy" honestly instead of
/// pretending cached data is live.
enum W4Freshness: Equatable, Sendable {
    /// Straight from W4 in this call.
    case fresh
    /// Served from disk; `fetchedAt` is when W4 last answered.
    case cached(fetchedAt: Date, isStale: Bool)
    /// Demo mode — no network was touched.
    case demo

    var isFromCache: Bool {
        if case .cached = self { return true }
        return false
    }

    /// The moment W4 actually produced this data, when we know it.
    var fetchedAt: Date? {
        if case .cached(let fetchedAt, _) = self { return fetchedAt }
        return nil
    }
}

/// A value plus its provenance. Repositories return this rather than a bare model so that every
/// screen can render the "last updated" affordance without guessing.
struct W4Loaded<Value>: Sendable where Value: Sendable {
    let value: Value
    let freshness: W4Freshness

    init(_ value: Value, freshness: W4Freshness) {
        self.value = value
        self.freshness = freshness
    }

    func map<Other>(_ transform: (Value) -> Other) -> W4Loaded<Other> where Other: Sendable {
        W4Loaded<Other>(transform(value), freshness: freshness)
    }
}
