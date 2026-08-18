//
//  FeedsRepository.swift
//  BetterW4
//
//  `r=academics/feeds` — the eight per-user RSS / iCalendar URLs (features.md §1.14, §2.5;
//  README §4.8; plan Wave 5 item 5.8).
//
//  ── Why this repository is different from every other one ─────────────────────────────────────
//
//  Each feed URL carries `token=<secret>`. That token authenticates the owner to an endpoint that
//  is otherwise unauthenticated: anyone holding it can read this student's timetable and assessment
//  calendar forever, from anywhere, with no password and no 2FA. **It is password-equivalent.**
//
//  Three consequences, none of them negotiable:
//
//    1. **The response never touches `W4PageCache`.** Every other repository in this wave caches its
//       HTML to `Caches/W4Pages/…`. This one passes `persist: false`, because that directory is
//       plain text on disk, is excluded from backup but not from a file-system dump, and would hold
//       eight live secrets. The parsed feeds go to the **Keychain** instead, which is also the
//       cache: `PersonalFeedSnapshot` carries its own `fetchedAt`, and `CachePolicy.ttl(for: .feeds)`
//       decides when to refetch.
//    2. **Nothing here logs a URL.** Not on success, not on failure, not in `#if DEBUG`. The warning
//       helper below takes static text only. `PersonalFeed` already overrides `description` and
//       `debugDescription` to the redacted form so that a stray `print(feed)` in some future wave
//       cannot leak one; do not undo that by interpolating `feed.url` anywhere.
//    3. **Never `UserDefaults`, never a fixture.** `UserDefaults` is an unencrypted plist that rides
//       every backup and every sysdiagnose.
//
//  Product scope for v1 (features.md §1.14): the app does not *parse* personal feeds — it hands the
//  ICS URL to the system ("Add to Apple Calendar") and shows the RSS ones as links. Timetable data
//  keeps coming from HTML, which is the only place rooms, rotation days and the now-line exist.
//

import Foundation
import OSLog
import Security
import SwiftSoup

// MARK: - Snapshot

/// The feed list as this app holds it, plus when W4 last produced it.
///
/// `Codable` exists so this can be written to the **Keychain** — and for no other destination.
struct PersonalFeedSnapshot: Codable, Sendable, Equatable {
    let feeds: [PersonalFeed]
    let fetchedAt: Date

    init(feeds: [PersonalFeed], fetchedAt: Date) {
        self.feeds = feeds
        self.fetchedAt = fetchedAt
    }

    func feed(_ kind: PersonalFeedKind) -> PersonalFeed? {
        feeds.first { $0.kind == kind }
    }
}

extension PersonalFeedSnapshot: CustomStringConvertible, CustomDebugStringConvertible {
    /// Redacted on purpose: interpolating a snapshot into a log line must not be able to leak a
    /// token, however carelessly some future call site does it.
    var description: String { "PersonalFeedSnapshot(\(feeds.count) feeds)" }
    var debugDescription: String { description }
}

// MARK: - Secret storage

/// Where feed tokens live. One implementation writes the Keychain; tests inject an in-memory one so
/// the suite never depends on a Keychain entitlement.
protocol PersonalFeedStoring {
    func loadFeeds(for uwcId: String) -> PersonalFeedSnapshot?
    func saveFeeds(_ snapshot: PersonalFeedSnapshot, for uwcId: String)
    func deleteFeeds(for uwcId: String)
}

extension KeychainManager {

    /// The service `KeychainManager` files everything under.
    ///
    /// Duplicated here because the original is `private` to `KeychainManager.swift`, which is part
    /// of the frozen auth stack (D-29) and must not be edited. It must keep matching: `wipeAll()`
    /// deletes every item under this service on logout, and feed tokens have to go with them.
    private static let feedService = "dk.elliottf.betterw4"

    private static func feedAccount(for uwcId: String) -> String { "w4.feeds.\(uwcId)" }

    /// The stored feed snapshot for one student, or `nil`.
    func loadPersonalFeeds(for uwcId: String) -> PersonalFeedSnapshot? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainManager.feedService,
            kSecAttrAccount as String: KeychainManager.feedAccount(for: uwcId),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PersonalFeedSnapshot.self, from: data)
    }

    /// Persists the feed snapshot.
    ///
    /// `ThisDeviceOnly` deliberately: a token is a live credential, and it has no business riding an
    /// iCloud Keychain sync onto a device that never signed in. Losing it costs one refetch.
    func savePersonalFeeds(_ snapshot: PersonalFeedSnapshot, for uwcId: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainManager.feedService,
            kSecAttrAccount as String: KeychainManager.feedAccount(for: uwcId)
        ]

        if loadPersonalFeeds(for: uwcId) != nil {
            _ = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            return
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        _ = SecItemAdd(addQuery as CFDictionary, nil)
    }

    func deletePersonalFeeds(for uwcId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainManager.feedService,
            kSecAttrAccount as String: KeychainManager.feedAccount(for: uwcId)
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}

/// The production store: the Keychain, reached through `KeychainManager`.
struct KeychainPersonalFeedStore: PersonalFeedStoring {
    private let keychain: KeychainManager

    init(keychain: KeychainManager = .shared) {
        self.keychain = keychain
    }

    func loadFeeds(for uwcId: String) -> PersonalFeedSnapshot? {
        keychain.loadPersonalFeeds(for: uwcId)
    }

    func saveFeeds(_ snapshot: PersonalFeedSnapshot, for uwcId: String) {
        keychain.savePersonalFeeds(snapshot, for: uwcId)
    }

    func deleteFeeds(for uwcId: String) {
        keychain.deletePersonalFeeds(for: uwcId)
    }
}

// MARK: - Repository

actor FeedsRepository {

    static let shared = FeedsRepository()

    private let loader: W4PageLoader
    private let store: any PersonalFeedStoring
    private let resolveContext: @Sendable () throws -> W4RequestContext

    init(
        client: any W4RouteFetching = W4HTTPClient(),
        cache: W4PageCache = .shared,
        store: any PersonalFeedStoring = KeychainPersonalFeedStore(),
        context: @escaping @Sendable () throws -> W4RequestContext = { try W4RequestContext.require() }
    ) {
        // The cache is handed over so the loader type stays uniform, but every call below passes
        // `persist: false`. Nothing from `academics/feeds` is ever written to it.
        self.loader = W4PageLoader(client: client, cache: cache)
        self.store = store
        self.resolveContext = context
    }

    private var target: W4PageTarget {
        W4PageTarget(surface: .feeds, cacheKey: W4Routes.R.feeds, route: W4Routes.R.feeds)
    }

    // MARK: - Reading

    /// The student's personal feeds.
    ///
    /// Keychain-first: a stored snapshot inside `CachePolicy.ttl(for: .feeds)` is returned without a
    /// request. A failed refresh falls back to the stored snapshot however old it is — the URLs do
    /// not rotate on their own, so yesterday's copy still works.
    func feeds(
        forceRefresh: Bool = false,
        priority: FetchPriority = .important
    ) async throws -> W4Loaded<[PersonalFeed]> {
        let context = try resolveContext()
        if context.isDemo {
            return W4Loaded(Self.demoFeeds(), freshness: .demo)
        }

        let stored = store.loadFeeds(for: context.uwcId)
        if !forceRefresh, let stored, CachePolicy.isFresh(stored.fetchedAt, for: .feeds) {
            return W4Loaded(stored.feeds, freshness: .cached(fetchedAt: stored.fetchedAt, isStale: false))
        }

        do {
            let page = try await loader.load(
                target,
                context: context,
                forceRefresh: true,
                priority: priority,
                persist: false                 // ← the whole point: the HTML holds eight secrets
            )
            let parsed = Self.feeds(in: page.value.html)
            if parsed.isEmpty {
                // W4 answered, but with nothing we recognise. Keep whatever we already had rather
                // than overwriting good tokens with an empty list.
                Self.warn("academics/feeds returned no recognisable feed URLs")
                if let stored {
                    return W4Loaded(
                        stored.feeds,
                        freshness: .cached(
                            fetchedAt: stored.fetchedAt,
                            isStale: !CachePolicy.isFresh(stored.fetchedAt, for: .feeds)
                        )
                    )
                }
                return W4Loaded([], freshness: .fresh)
            }

            let snapshot = PersonalFeedSnapshot(feeds: parsed, fetchedAt: page.value.fetchedAt)
            store.saveFeeds(snapshot, for: context.uwcId)
            return W4Loaded(snapshot.feeds, freshness: .fresh)
        } catch {
            if W4PageLoader.mustPropagate(error) { throw error }
            guard let stored else { throw error }
            Self.warn("academics/feeds refresh failed; serving the stored feeds")
            return W4Loaded(
                stored.feeds,
                freshness: .cached(
                    fetchedAt: stored.fetchedAt,
                    isStale: !CachePolicy.isFresh(stored.fetchedAt, for: .feeds)
                )
            )
        }
    }

    /// The stored feeds without any request. `nil` when none have ever been fetched.
    func storedFeeds() -> W4Loaded<[PersonalFeed]>? {
        guard let context = try? resolveContext() else { return nil }
        if context.isDemo {
            return W4Loaded(Self.demoFeeds(), freshness: .demo)
        }
        guard let stored = store.loadFeeds(for: context.uwcId) else { return nil }
        return W4Loaded(
            stored.feeds,
            freshness: .cached(
                fetchedAt: stored.fetchedAt,
                isStale: !CachePolicy.isFresh(stored.fetchedAt, for: .feeds)
            )
        )
    }

    /// One feed, fetching the list first if it is missing or past its TTL.
    func feed(_ kind: PersonalFeedKind, forceRefresh: Bool = false) async throws -> PersonalFeed? {
        try await feeds(forceRefresh: forceRefresh).value.first { $0.kind == kind }
    }

    /// Forget every stored token for the signed-in student. Call on sign-out and on "Clear cache".
    ///
    /// `KeychainManager.wipeAll()` also removes them (same Keychain service), so this exists for the
    /// narrower case: revoking feeds without ending the session.
    func clear() {
        guard let context = try? resolveContext() else { return }
        store.deleteFeeds(for: context.uwcId)
    }

    // MARK: - Extraction

    /// Pulls feed URLs out of `academics/feeds`.
    ///
    /// **[U] — the page has never been captured.** So this does not assume a table, a list or any
    /// class name: it collects every URL-bearing attribute W4 could plausibly render a "copy this
    /// address" control with (`a[href]`, `input[value]`, `textarea`), keeps the ones on the W4 host
    /// whose `r=` route equals a known `PersonalFeedKind.route`, and drops everything else. If W4
    /// restyles the page tomorrow, this keeps working; if it renames a route, this returns fewer
    /// feeds instead of wrong ones.
    ///
    /// Pure and synchronous — no I/O, no clock, no logging of what it finds.
    static func feeds(in html: String) -> [PersonalFeed] {
        guard let document = try? SwiftSoup.parse(html) else { return [] }

        var candidates: [String] = []
        for element in (try? document.select("a[href]").array()) ?? [] {
            candidates.append((try? element.attr("href")) ?? "")
        }
        for element in (try? document.select("input[value]").array()) ?? [] {
            candidates.append((try? element.attr("value")) ?? "")
        }
        for element in (try? document.select("textarea").array()) ?? [] {
            candidates.append((try? element.text()) ?? "")
        }

        var byKind: [PersonalFeedKind: URL] = [:]
        let routes = Dictionary(
            uniqueKeysWithValues: PersonalFeedKind.allCases.map { ($0.route.lowercased(), $0) }
        )

        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            // Cheap gate before doing any URL work: every feed route contains "feeds".
            guard trimmed.lowercased().contains("feeds") else { continue }
            guard let url = absoluteW4URL(trimmed) else { continue }
            guard let route = W4Routes.route(of: url)?.lowercased(), let kind = routes[route] else { continue }
            if byKind[kind] == nil { byKind[kind] = url }
        }

        // Stable, declaration order — never document order, which W4 may reshuffle.
        return PersonalFeedKind.allCases.compactMap { kind in
            byKind[kind].map { PersonalFeed(kind: kind, url: $0) }
        }
    }

    /// Resolves an href to an absolute URL **on the W4 host only**. Anything else is discarded: a
    /// feed URL pointing off-host would mean we misread the page, and following it would post a
    /// W4 secret to a third party.
    private static func absoluteW4URL(_ raw: String) -> URL? {
        let lower = raw.lowercased()
        let url: URL?
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            url = URL(string: raw)
        } else if raw.hasPrefix("/") || lower.hasPrefix("index.php") || raw.hasPrefix("?r=") {
            url = W4Routes.resolve(raw)
        } else {
            url = nil
        }
        guard let url, W4Routes.isW4Host(url.host) else { return nil }
        return url
    }

    // MARK: - Demo

    /// Demo feeds point at the real routes and carry **no token at all**.
    ///
    /// That is the honest thing to show an App Review account: the row renders, "Add to Calendar"
    /// is visibly present, and no secret — not even a fake one shaped like a secret — is invented.
    static func demoFeeds() -> [PersonalFeed] {
        [PersonalFeedKind.combinedICS, .assessmentsICS].map {
            PersonalFeed(kind: $0, url: W4Routes.url($0.route))
        }
    }

    // MARK: - Logging

    /// Static text only, forever. No URL, no token, no query string, no count of characters, no
    /// "starts with". If you are tempted to add an interpolation here, do not.
    private static func warn(_ message: String) {
        Logger(subsystem: "dk.jonathanb.w4", category: "FeedsRepository")
            .warning("\(message, privacy: .public)")
    }
}
