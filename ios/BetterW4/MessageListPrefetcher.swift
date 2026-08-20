//
//  MessageListPrefetcher.swift
//  BetterW4
//
//  Warms the W4 inbox in the background so More ▸ Mail opens on content, and keeps the
//  badge honest (plan Wave 5 item 5.3).
//
//  Two rules, and they are the whole point of this file:
//
//    1. **Every request here is `.opportunistic`, always.** All W4 traffic goes through one serial
//       gate (`PriorityRequestLimiter`), and W4 is a single small Apache box serving ~200 students
//       (README §5.5). A prefetch that queues at `.important` sits in front of the screen the
//       student is actually looking at and makes the whole app feel slow to save a tab switch.
//       There is no parameter for this: the priority is a constant.
//    2. **One at a time.** The actor drops a second prefetch while one is in flight rather than
//       stacking requests behind the gate.
//
//  The unread badge is not published from here: `MailFileCache` posts
//  `.unreadMessageCountDidChange` whenever the inbox is written, so the badge updates whether the
//  inbox arrived from a prefetch, a pull-to-refresh or a screen appearing.
//
//  Retargeted in Wave 5 from the Lectio `Nyeste`/`Ulæst` folders. The two entry points keep their
//  names and signatures because `ContentView`, `MessagesViewModel` and `MessageThreadViewModel`
//  still call them; Wave 6 renames them along with the rest of the message UI.
//

import Foundation
import OSLog

private let mailPrefetchLog = Logger(subsystem: "dk.jonathanb.w4", category: "MailPrefetch")

enum MessageListPrefetcher {

    /// Non-negotiable. See rule 1 above.
    static let priority: FetchPriority = .opportunistic

    /// Warms the inbox if its 5-minute TTL has lapsed. Cheap and safe to call on every tab change.
    static func schedulePrefetch(for student: Student) {
        guard MailFeatureFlags.visible else { return }
        guard !student.isDemo else { return }
        Task(priority: .utility) {
            await coordinator.run(force: false, using: MailRepository.shared)
        }
    }

    /// Forces a refetch regardless of TTL. Call after anything that could have changed unread
    /// state — opening a message, or a future mark-as-read.
    ///
    /// Named for the Lectio `Ulæst` folder it used to refresh; on W4 there is no unread folder,
    /// only the inbox, and its unread rows are the badge.
    static func refreshUnreadFolder(for student: Student) {
        guard MailFeatureFlags.visible else { return }
        guard !student.isDemo else { return }
        Task(priority: .utility) {
            await coordinator.run(force: true, using: MailRepository.shared)
        }
    }

    /// The same work, awaitable and against an injected repository. Exists so a test can assert
    /// the priority the prefetch actually reaches the transport with.
    static func prefetchNow(force: Bool, using repository: MailRepository) async {
        await coordinator.run(force: force, using: repository)
    }

    private static let coordinator = Coordinator()

    private actor Coordinator {
        private var isRunning = false

        func run(force: Bool, using repository: MailRepository) async {
            guard !isRunning else { return }
            isRunning = true
            defer { isRunning = false }

            do {
                _ = try await repository.list(
                    folder: .inbox,
                    forceRefresh: force,
                    priority: MessageListPrefetcher.priority
                )
            } catch {
                // A prefetch is by definition something nobody asked for: it never surfaces an
                // error. `.sessionExpired` still reaches `AuthenticationViewModel` — the client
                // posts `.w4SessionExpired` at the point of classification, not from here.
                mailPrefetchLog.debug(
                    "inbox prefetch failed: \(String(describing: error), privacy: .public)"
                )
            }
        }
    }
}
