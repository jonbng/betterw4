//
//  MailModels.swift
//  BetterW4
//
//  Domain models for the W4 mailer (`mailer/inbox`, `mailer/archive`, `mailer/view&id=`).
//
//  W4's mailer is a Yii 1 `CGridView` of *individual emails*. It is not Lectio's `beskeder`:
//  there are no threads, no replies, no reactions, no message editing, no BBCode and no
//  signature protocol. Nothing in this file models any of those — see
//  `docs/W4_PORT_PLAN.md` §1.4 kill list and `docs/spec/features.md` §1.4.
//
//  Naming follows plan decision D-5: the `W4` prefix is for wire/protocol types and parsers
//  only, so every model the UI consumes here is unprefixed.
//
//  EVIDENCE. No `mailer/*` page has ever been captured (`docs/spec/parsers.md` §7, OQ-4).
//  The column sets below come from README §6 prose, the container from the Yii 1 framework
//  convention. Every field that depends on unseen markup is marked in its doc comment, and
//  the parsers that produce these values degrade to an empty result rather than guessing.
//

import Foundation

// MARK: - Folders

/// One of the mailer's two grids. W4 has exactly two: the inbox and the sent archive.
struct MailFolder: Identifiable, Codable, Hashable, Sendable {
    /// Stable folder key, also used as `MailMessage.folderID`.
    let id: String
    /// English display name. `mailer/archive` is presented as "Sent".
    let displayName: String
    /// The W4 route this grid is fetched from, without the `index.php?r=` prefix.
    let route: String

    init(id: String, displayName: String, route: String) {
        self.id = id
        self.displayName = displayName
        self.route = route
    }

    static let inbox = MailFolder(
        id: "inbox",
        displayName: "Inbox",
        route: W4Routes.R.mailerInbox
    )

    static let archive = MailFolder(
        id: "archive",
        displayName: "Sent",
        route: W4Routes.R.mailerArchive
    )

    static let all: [MailFolder] = [.inbox, .archive]

    static func folder(id: String) -> MailFolder? {
        all.first { $0.id == id }
    }

    /// The inbox is the only grid README §6 documents a `From` column for. This is a *hint*
    /// for logging, never a parsing rule — columns are always matched by header text.
    var expectsSenderColumn: Bool { id == MailFolder.inbox.id }
}

// MARK: - List rows

/// One row of a mailer grid.
struct MailMessage: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// The `id=` value from the row's `mailer/view` link.
    ///
    /// Never derived from `tr[id]` (Yii does not emit one) and never from a string hash of the
    /// subject (bug B18 — hashes collide, which makes two different emails the same row). When
    /// no `id=` is present the parser substitutes a stable content hash prefixed `w4mail-`.
    let id: String
    /// `MailFolder.id` this row was read from.
    let folderID: String
    let subject: String
    /// `nil` when the grid has no sender column at all — which is the documented shape of
    /// `mailer/archive`. Never a positional guess.
    let from: String?
    /// Parsed from the Received / Send date column in `Europe/Oslo`; `nil` when the column is
    /// absent or unparseable.
    let receivedAt: Date?
    /// UNVERIFIED: no unread marker has ever been captured. `false` unless the row or a
    /// descendant carries an `unread` class.
    let isUnread: Bool
    /// UNVERIFIED: no attachment marker has ever been captured. Set from a non-empty
    /// attachment column, or an attachment-looking link in the row.
    let hasAttachment: Bool
    /// The row link exactly as captured, so the client can re-fetch it verbatim.
    let href: String?

    init(
        id: String,
        folderID: String,
        subject: String,
        from: String? = nil,
        receivedAt: Date? = nil,
        isUnread: Bool = false,
        hasAttachment: Bool = false,
        href: String? = nil
    ) {
        self.id = id
        self.folderID = folderID
        self.subject = subject
        self.from = from
        self.receivedAt = receivedAt
        self.isUnread = isUnread
        self.hasAttachment = hasAttachment
        self.href = href
    }
}

// MARK: - Column layout

/// Which grid columns the header row actually offered, and where they sat.
///
/// Kept on the parse result on purpose: it is the difference between "this archive genuinely
/// has no sender" and "we read the wrong column and got lucky". Tests assert against it.
struct MailColumnLayout: Codable, Equatable, Sendable {
    /// Header labels in DOM order, lowercased and whitespace-collapsed.
    let headers: [String]
    let received: Int?
    let from: Int?
    let subject: Int?
    let attachment: Int?

    init(
        headers: [String] = [],
        received: Int? = nil,
        from: Int? = nil,
        subject: Int? = nil,
        attachment: Int? = nil
    ) {
        self.headers = headers
        self.received = received
        self.from = from
        self.subject = subject
        self.attachment = attachment
    }

    static let none = MailColumnLayout()

    var hasSenderColumn: Bool { from != nil }
    var hasDateColumn: Bool { received != nil }
    var hasSubjectColumn: Bool { subject != nil }
    var hasAttachmentColumn: Bool { attachment != nil }
}

// MARK: - Pagination

/// Yii 1 `div.pager` state.
///
/// UNVERIFIED (bug B10, OQ-4): no paginated mailer grid has been captured. The parser only
/// reports what it can see, and the UI is expected to offer "open on w4.uwcrcn.no" rather than
/// silently presenting page 1 as the whole mailbox.
struct MailPagination: Codable, Equatable, Hashable, Sendable {
    /// A pager exists and offers at least one link away from the current page.
    let hasMorePages: Bool
    /// The page marked `selected`, when the pager says so.
    let currentPage: Int?
    /// The highest numbered page link the pager offers. Not necessarily the true last page.
    let pageCount: Int?
    /// Yii's `div.summary`, e.g. "Displaying 1-20 of 37 results.", verbatim.
    let summary: String?
    /// `href` of the pager's "next" link, exactly as captured.
    let nextPageHref: String?

    init(
        hasMorePages: Bool,
        currentPage: Int? = nil,
        pageCount: Int? = nil,
        summary: String? = nil,
        nextPageHref: String? = nil
    ) {
        self.hasMorePages = hasMorePages
        self.currentPage = currentPage
        self.pageCount = pageCount
        self.summary = summary
        self.nextPageHref = nextPageHref
    }
}

// MARK: - List result

/// Why a mailer grid produced the rows it did.
enum MailListOutcome: String, Codable, Equatable, Sendable {
    /// A grid was found and at least one data row was read.
    case parsed
    /// W4 itself said there is nothing here: `td.empty`, `span.empty`, "No results found.",
    /// `div.note`, or a grid with no data rows at all.
    case emptyState
    /// No recognisable grid, or a grid whose rows yielded nothing usable. The parser degraded
    /// to no rows and logged a warning; this means the markup moved, **not** that the mailbox
    /// is empty, and the UI should say so rather than showing a cheerful "no mail" screen.
    case unrecognised
}

/// The result of parsing one page of a mailer grid.
struct MailListPage: Equatable, Sendable {
    let folder: MailFolder
    let messages: [MailMessage]
    let pagination: MailPagination?
    let outcome: MailListOutcome
    let columns: MailColumnLayout

    init(
        folder: MailFolder,
        messages: [MailMessage],
        pagination: MailPagination? = nil,
        outcome: MailListOutcome,
        columns: MailColumnLayout = .none
    ) {
        self.folder = folder
        self.messages = messages
        self.pagination = pagination
        self.outcome = outcome
        self.columns = columns
    }

    static func empty(
        folder: MailFolder,
        outcome: MailListOutcome,
        pagination: MailPagination? = nil,
        columns: MailColumnLayout = .none
    ) -> MailListPage {
        MailListPage(
            folder: folder,
            messages: [],
            pagination: pagination,
            outcome: outcome,
            columns: columns
        )
    }

    var hasMorePages: Bool { pagination?.hasMorePages ?? false }
    var isEmpty: Bool { messages.isEmpty }
}

// MARK: - Detail

/// A file linked from a read email.
///
/// UNVERIFIED: `mailer/view` has never been captured, so both the link shape and the download
/// route are inferred.
struct MailAttachment: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    /// `href` exactly as captured; may be relative to `https://w4.uwcrcn.no`.
    let url: String

    init(id: String, name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
    }
}

/// One read email (`mailer/view&id=N`). One message — never a thread.
struct MailMessageDetail: Identifiable, Codable, Equatable, Sendable {
    let id: String
    /// Best-effort heading. Empty when the page offered no heading element.
    let subject: String
    /// `nil` unless the page carried an explicit `From:` label.
    let from: String?
    /// Empty unless the page carried an explicit `To:` / `Recipients:` label.
    let recipients: [String]
    let sentAt: Date?
    /// The page body as TinyMCE-authored HTML, taken from `#content_inner` with the page
    /// chrome removed. Rendered through the shared HTML renderer, never trusted as markdown.
    ///
    /// UNVERIFIED: until `mailer/view` is captured this is the whole content container, so it
    /// may still repeat the header lines that were lifted into `from` / `recipients` / `sentAt`.
    let bodyHTML: String
    let attachments: [MailAttachment]

    init(
        id: String,
        subject: String,
        from: String? = nil,
        recipients: [String] = [],
        sentAt: Date? = nil,
        bodyHTML: String,
        attachments: [MailAttachment] = []
    ) {
        self.id = id
        self.subject = subject
        self.from = from
        self.recipients = recipients
        self.sentAt = sentAt
        self.bodyHTML = bodyHTML
        self.attachments = attachments
    }
}

// MARK: - Compose

/// A person the compose screen can address, from `mailer/extra&type=freeform`.
struct MailRecipient: Identifiable, Codable, Hashable, Sendable {
    /// The recipient token W4 itself hands out. Never invented client-side.
    let id: String
    let name: String
    /// Year / house / role, when the picker offers one.
    let subtitle: String?

    init(id: String, name: String, subtitle: String? = nil) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
    }
}

/// An unsent message. `bodyHTML` is HTML because W4's compose field is TinyMCE — not BBCode
/// (Lectio) and not markdown.
struct MailDraft: Equatable, Sendable {
    var subject: String
    var bodyHTML: String
    var recipients: [MailRecipient]
    var attachments: [OutgoingMessageAttachment]
    var sendCopyToMe: Bool

    init(
        subject: String = "",
        bodyHTML: String = "",
        recipients: [MailRecipient] = [],
        attachments: [OutgoingMessageAttachment] = [],
        sendCopyToMe: Bool = false
    ) {
        self.subject = subject
        self.bodyHTML = bodyHTML
        self.recipients = recipients
        self.attachments = attachments
        self.sendCopyToMe = sendCopyToMe
    }

    /// The non-file half of the `mailer/send&type=freeform` POST body.
    ///
    /// The attachments are deliberately absent: they are repeated
    /// `MailerForm[attachment][]` multipart parts streamed from disk, which is the transport
    /// layer's job, not a model's.
    func formFields() -> [String: String] {
        var fields: [String: String] = [
            MailComposeFields.subject: subject,
            MailComposeFields.message: bodyHTML,
            MailComposeFields.attachmentSource: MailComposeFields.attachmentSourceUpload
        ]
        // Yii reads an unchecked box as absent, so only send the flag when it is on.
        if sendCopyToMe {
            fields[MailComposeFields.sendCC] = "1"
        }
        return fields
    }
}

/// Literal `MailerForm[...]` field names, from README §5.2. These are wire strings: they are
/// spelled exactly as W4 expects them and must not be "tidied".
enum MailComposeFields {
    static let subject = "MailerForm[subject]"
    static let message = "MailerForm[message]"
    static let attachment = "MailerForm[attachment][]"
    static let sendCC = "MailerForm[sendCC]"
    static let attachmentSource = "MailerForm[attachmentSource]"
    static let attachmentSourceUpload = "upload"
    /// Yii's clicked-submit-button convention.
    static let submitButton = "yt0"
}

/// Server-side attachment limits (README §5.2, plan decision D-26). The legacy Lectio
/// `OutgoingMessageAttachment` constants (10 files × 25 MB) are Lectio's, not W4's; they are
/// left untouched in that file and superseded here.
enum MailAttachmentLimits {
    static let maximumCount = 5
    static let maximumByteCount: Int64 = 2 * 1_024 * 1_024
}
