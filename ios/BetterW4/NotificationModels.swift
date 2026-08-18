//
//  NotificationModels.swift
//  BetterW4
//
//  Domain models for the W4 notification bell (`#header div.notifications`).
//
//  These keep the `W4` prefix by plan decision D-5: `Notification` is a
//  Foundation type, so an unprefixed `Notification` model would shadow it
//  module-wide.
//
//  EVIDENCE. The container `div.notifications` is [V] and, in **both** captures
//  we have, it is **empty** — zero notifications is the normal state at this
//  school (bug B8). The populated shape below is [I]: reconstructed from the
//  real assets W4 serves (`notifications.js`, `notifications.css`), never seen
//  rendered. Class names named by those assets — `.btn-group`, `div.alert`,
//  `.dropdown-menu`, `h3.tasks`, `h3.emails`, `a.read`, `a.clear`,
//  `data-notification-id`, `data-notification-type`, `dl.email-list`,
//  `span.deadline`, `span.duration`, `span.icon`, and the severities
//  `normal` / `new` / `overdue` — are [V]. The item *text*, whether every item
//  carries an `href`, and the exact refresh payload are [U].
//

import Foundation

// MARK: - Enumerations

/// The badge / row severity, from the classes `notifications.css:28-67` styles [V].
enum W4NotificationSeverity: String, Codable, Sendable, CaseIterable {
    case normal
    case new
    case overdue
}

/// The two halves of the dropdown: `h3.tasks` + `dl`, and `h3.emails` + `dl.email-list` [V].
enum W4NotificationSection: String, Codable, Sendable, CaseIterable {
    case task
    case email
}

// MARK: - Items

/// One row in the bell dropdown.
struct W4Notification: Identifiable, Codable, Equatable, Hashable, Sendable {

    /// `data-notification-id` — the id `notifications/read` and
    /// `notifications/clear` expect. Rows without one are dropped by the parser:
    /// an unactionable row is worse than no row, and inventing an id would post
    /// garbage back to the server.
    let id: String

    /// The row's own text, without the trailing `span.deadline` / `span.duration`.
    let title: String

    /// `span.deadline` or `span.duration`, when present.
    let subtitle: String?

    /// The `r=` value of the row's link (`academics/deadlines`, `mailer/view`, …),
    /// or `nil` when the row has no href.
    let route: String?

    /// The raw `href` exactly as W4 rendered it. Kept alongside ``route`` because
    /// the route alone loses sibling query keys — `mailer/view&id=88` needs its id.
    let href: String?

    /// `data-notification-type` — the group key `notifications/readgroup` and
    /// `notifications/cleargroup` expect.
    let type: String?

    let section: W4NotificationSection
    let severity: W4NotificationSeverity

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        route: String? = nil,
        href: String? = nil,
        type: String? = nil,
        section: W4NotificationSection,
        severity: W4NotificationSeverity = .normal
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.route = route
        self.href = href
        self.type = type
        self.section = section
        self.severity = severity
    }

    /// Where tapping the row should go, on the single W4 host.
    var url: URL? {
        guard let raw = href ?? route, !raw.isEmpty else { return nil }
        return W4Routes.resolve(raw)
    }
}

/// One `<dt>` heading plus the `<dd><li>` rows beneath it.
struct W4NotificationGroup: Identifiable, Codable, Equatable, Sendable {

    /// `data-notification-type`, when the heading carries one.
    let type: String?

    /// The `<dt>` text, with the read/clear anchors removed.
    let title: String

    let severity: W4NotificationSeverity
    let items: [W4Notification]

    init(
        type: String?,
        title: String,
        severity: W4NotificationSeverity = .normal,
        items: [W4Notification] = []
    ) {
        self.type = type
        self.title = title
        self.severity = severity
        self.items = items
    }

    var id: String { type ?? title }
}

// MARK: - Snapshot

/// Everything the bell knows after one parse.
struct W4NotificationSnapshot: Codable, Equatable, Sendable {

    /// `div.alert` badge text when it is an integer, else the number of distinct
    /// parsed items. A `9+` badge [U] therefore reports the honest parsed count.
    let count: Int

    /// The badge's severity, or the most severe thing parsed when there is no badge.
    let severity: W4NotificationSeverity

    let taskGroups: [W4NotificationGroup]
    let emailGroups: [W4NotificationGroup]

    init(
        count: Int = 0,
        severity: W4NotificationSeverity = .normal,
        taskGroups: [W4NotificationGroup] = [],
        emailGroups: [W4NotificationGroup] = []
    ) {
        self.count = count
        self.severity = severity
        self.taskGroups = taskGroups
        self.emailGroups = emailGroups
    }

    /// The normal state at this school (bug B8): the real chrome ships an empty
    /// `div.notifications` in both captures. This is a success, not a failure.
    static let empty = W4NotificationSnapshot()

    var items: [W4Notification] {
        taskGroups.flatMap(\.items) + emailGroups.flatMap(\.items)
    }

    var isEmpty: Bool {
        count <= 0 && taskGroups.isEmpty && emailGroups.isEmpty
    }
}

// MARK: - Action routes

/// The eight bell endpoints, decoded from `var notification_urls = {…}` on the
/// real Home capture (`UWCRCN W4.html:24`) [V]. Every one is a jQuery `$.post`
/// with `X-Requested-With: XMLHttpRequest` whose response is an HTML fragment
/// the same parser reads back (`notifications.js:59-69`).
///
/// The raw values are deliberately W4's own keys from that object literal.
enum W4NotificationAction: String, Codable, Sendable, CaseIterable {
    case read
    case readGroup
    case readAll
    case readAllEmails
    case clear
    case clearGroup
    case clearAll
    case refresh

    /// `notifications/read` and friends. Mirrors `W4Routes.R.notifications*`.
    var route: String {
        switch self {
        case .read: return W4Routes.R.notificationsRead
        case .readGroup: return W4Routes.R.notificationsReadGroup
        case .readAll: return W4Routes.R.notificationsReadAll
        case .readAllEmails: return W4Routes.R.notificationsReadAllEmails
        case .clear: return W4Routes.R.notificationsClear
        case .clearGroup: return W4Routes.R.notificationsClearGroup
        case .clearAll: return W4Routes.R.notificationsClearAll
        case .refresh: return W4Routes.R.notificationsRefresh
        }
    }

    static let notificationIDField = "notification_id"
    static let notificationTypeField = "notification_type"

    /// The single POST field this action needs, or `nil` when its body is empty.
    var requiredField: String? {
        switch self {
        case .read, .clear:
            return Self.notificationIDField
        case .readGroup, .clearGroup:
            return Self.notificationTypeField
        case .readAll, .readAllEmails, .clearAll, .refresh:
            return nil
        }
    }

    /// Builds the `$.post` body.
    ///
    /// `identifier` is the `data-notification-id` for ``read`` / ``clear`` and the
    /// `data-notification-type` for ``readGroup`` / ``clearGroup``. Returns `nil`
    /// when the action needs one and none was supplied — never guess an id
    /// (`OQ-9`: only post `notifications/read` when a matching id is known).
    func body(_ identifier: String? = nil) -> [String: String]? {
        guard let field = requiredField else { return [:] }
        let trimmed = (identifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return [field: trimmed]
    }
}
