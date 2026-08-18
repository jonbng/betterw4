//
//  W4MailDetailParser.swift
//  BetterW4
//
//  Parses one read email: `index.php?r=mailer/view&id={n}`.
//
//  EVIDENCE — read this before changing a selector.
//  `mailer/view` has NEVER been captured (`docs/spec/parsers.md` §7, plan OQ-4, capture wishlist
//  item 3). The Android port does not parse it at all — `MessageRepository.kt:109-123` dumps the
//  whole `#content_inner` into a single synthetic thread entry. So the only things here that rest
//  on evidence are:
//    * the route and the `id=` parameter                                              [V] (School
//      side-menu capture + README §6);
//    * `#content_inner` as the page's content container                               [V] (§0.3);
//    * "the body is TinyMCE-authored HTML"                                            [V] (README
//      §5.2 — the compose field is `MailerForm[message]`, a TinyMCE editor);
//    * `parsers.md` §7's v1 instruction: subject from `#content_inner h1, h2`, attachments from
//      `a[href*=download], a[href*=attachment]`.                                       [I]
//  EVERY other selector below — the `CDetailView` header table, the `<dt>/<dd>` list, the
//  "From:" prose lines, the `div.message-body` body container — is INFERRED. It is a ladder of
//  plausible shapes, each of which degrades to the next, and the last rung is the documented v1
//  behaviour: hand back the whole content container.
//
//  Consequences, and they are binding:
//    * nothing here throws out of `parse`, nothing force-unwraps, nothing assumes a node exists;
//    * an unreadable page yields a detail with an empty subject and an empty body plus a logged
//      warning — never a crash and never invented content;
//    * `bodyHTML` is kept **raw**. It is not sanitised, not converted, not turned into text here.
//      `MailMessageDetail.bodyHTML` documents that it may still repeat the header lines that were
//      lifted into `from` / `recipients` / `sentAt`, because on the fallback rung it is literally
//      the whole container. Rendering is the renderer's job — see `blocks(of:baseURL:)`, which
//      delegates to the shared `HTMLContentRenderer` (item 4.1). There is no second renderer.
//
//  Pure and synchronous by design (plan D-30): no I/O, no actor hops, no singletons, no clock.
//

import Foundation
import OSLog
import SwiftSoup

private let w4MailDetailLog = Logger(subsystem: "dk.jonathanb.w4", category: "W4MailDetailParser")

// MARK: - Mail detail parser

nonisolated enum W4MailDetailParser {

    // MARK: Entry points

    /// Parses `mailer/view&id={id}` into a single message.
    ///
    /// - Parameters:
    ///   - html: the response body, whole page or fragment.
    ///   - id: the message id the request was made with. It is taken as authoritative and is
    ///     never re-derived from the page — bug B18's lesson is that guessing an identity out of
    ///     page content merges unrelated messages. If the caller has no id, it passes `""` and
    ///     gets `""` back.
    /// - Returns: always a detail. A parse failure is an empty subject and an empty body, logged.
    static func parse(_ html: String, id: String) -> MailMessageDetail {
        do {
            let document = try SwiftSoup.parse(html)
            let root = try W4MailHTML.contentRoot(document)

            // Order matters: everything is read off the intact tree before `bodyMarkup` strips
            // script/style out of it.
            let fields = try headerFields(in: root)
            let parsedSubject = try subjectText(in: root, fields: fields)
            let parsedFrom = fieldValue(in: fields, keys: fromLabels)
            let parsedRecipients = recipientList(from: fieldValue(in: fields, keys: recipientLabels))
            let parsedSentAt = timestamp(fieldValue(in: fields, keys: dateLabels))
            let parsedAttachments = try attachmentLinks(in: root, messageID: id)
            let parsedBody = try bodyMarkup(in: root)

            if parsedBody.isEmpty {
                w4MailDetailLog.warning(
                    "mailer/view id=\(id, privacy: .public): no body markup found"
                )
            }

            return MailMessageDetail(
                id: id,
                subject: parsedSubject,
                from: parsedFrom,
                recipients: parsedRecipients,
                sentAt: parsedSentAt,
                bodyHTML: parsedBody,
                attachments: parsedAttachments
            )
        } catch {
            let reason = String(describing: error)
            w4MailDetailLog.warning("mailer/view \(id, privacy: .public): failed: \(reason, privacy: .public)")
            return MailMessageDetail(id: id, subject: "", bodyHTML: "")
        }
    }

    /// The one supported way to turn a parsed body into drawable blocks.
    ///
    /// The parser deliberately keeps `bodyHTML` raw; this delegates to the shared renderer from
    /// item 4.1 rather than growing a second one.
    static func blocks(of detail: MailMessageDetail, baseURL: URL? = nil) -> [ContentBlock] {
        HTMLContentRenderer.blocks(fromHTML: detail.bodyHTML, baseURL: baseURL)
    }

    // MARK: Header fields

    /// Labels this parser will lift out of the page. Anything else is body text, not a header —
    /// the whitelist is what stops a paragraph beginning "Note: bring a raincoat" from being
    /// read as metadata.
    private static let knownLabels: Set<String> = [
        "from", "sender",
        "to", "recipient", "recipients", "cc",
        "subject", "title",
        "received", "received date", "sent", "sent date", "send date", "date"
    ]

    private static let fromLabels = ["from", "sender"]
    private static let recipientLabels = ["to", "recipients", "recipient", "cc"]
    private static let dateLabels = [
        "received", "received date", "sent", "sent date", "send date", "date"
    ]
    private static let subjectLabels = ["subject", "title"]

    /// Elements a "Label: value" line could plausibly live in.
    private static let proseSelector = "p, div, li, span, td, h3, h4, h5"

    /// A header line is short. Anything longer is prose that happens to contain a colon.
    private static let maxLabelledLineLength = 240

    /// Every `label -> value` pair the page offers, from three shapes, most trustworthy first.
    private static func headerFields(in root: Element) throws -> [String: String] {
        var fields: [String: String] = [:]

        // (1) [I] Yii 1 `CDetailView`: <tr><th>From</th><td>House Leader</td></tr>.
        for row in try root.select("tr").array() {
            let cells = row.children().array().filter { (cell: Element) -> Bool in
                let tag = cell.tagName().lowercased()
                return tag == "th" || tag == "td"
            }
            guard cells.count == 2 else { continue }
            let key = W4MailHTML.normalizedHeader(try cells[0].text())
            let value = W4MailHTML.normalizedText(try cells[1].text())
            guard knownLabels.contains(key), !value.isEmpty, fields[key] == nil else { continue }
            fields[key] = value
        }

        // (2) [I] Definition list: <dt>From</dt><dd>House Leader</dd>.
        for term in try root.select("dt").array() {
            guard let definition = try term.nextElementSibling(),
                  definition.tagName().lowercased() == "dd" else { continue }
            let key = W4MailHTML.normalizedHeader(try term.text())
            let value = W4MailHTML.normalizedText(try definition.text())
            guard knownLabels.contains(key), !value.isEmpty, fields[key] == nil else { continue }
            fields[key] = value
        }

        // (3) [I] Prose: <div><strong>From:</strong> House Leader</div>.
        var proseValues: [String: String] = [:]
        var proseLengths: [String: Int] = [:]
        for element in try root.select(proseSelector).array() {
            let line = W4MailHTML.normalizedText(try element.text())
            guard !line.isEmpty, line.count <= maxLabelledLineLength else { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = W4MailHTML.normalizedHeader(String(line[line.startIndex..<colon]))
            guard knownLabels.contains(key) else { continue }
            let value = W4MailHTML.normalizedText(String(line[line.index(after: colon)...]))
            guard !value.isEmpty else { continue }
            // The innermost element wins: it is the shortest line that still carries the label,
            // so an ancestor <div> that swallows the whole header block cannot outvote it.
            if let length = proseLengths[key], length <= line.count { continue }
            proseLengths[key] = line.count
            proseValues[key] = value
        }
        for (key, value) in proseValues where fields[key] == nil {
            fields[key] = value
        }

        return fields
    }

    private static func fieldValue(in fields: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = fields[key], !value.isEmpty { return value }
        }
        return nil
    }

    // MARK: Subject

    /// Labelled subject first, then the first heading in the content container
    /// (`parsers.md` §7: "extract subject from `#content_inner h1, h2`" **[I]**).
    ///
    /// UNVERIFIED: on the captured Documents page that heading is the *page title*
    /// ("Documents"), not a subject. Whether `mailer/view` puts the subject there or a generic
    /// "View message" is unknown until the page is captured.
    private static func subjectText(in root: Element, fields: [String: String]) throws -> String {
        if let labelled = fieldValue(in: fields, keys: subjectLabels) { return labelled }
        for heading in try root.select("h1, h2, h3").array() {
            let text = W4MailHTML.normalizedText(try heading.text())
            if !text.isEmpty { return text }
        }
        return ""
    }

    // MARK: Recipients

    /// Splits a recipient line on `,` and `;` only. No other separator is invented — a name
    /// containing " and " must not be torn in half.
    private static func recipientList(from raw: String?) -> [String] {
        guard let raw else { return [] }
        let parts = raw
            .split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { W4MailHTML.normalizedText(String($0)) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty { return parts }
        let single = W4MailHTML.normalizedText(raw)
        return single.isEmpty ? [] : [single]
    }

    // MARK: Timestamp

    /// Single call site for the shared date helper (plan D-11: Oslo, en_GB_POSIX, fixed
    /// Gregorian calendar). Never `TimeZone.current`.
    private static func timestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let exact = W4Dates.parseDateTime(raw) { return exact }
        // "14-Aug-2026 12:04 (Oslo)" and friends: keep the day rather than losing the field.
        return W4Dates.firstDate(in: raw)
    }

    // MARK: Body

    /// Body-container ladder, most specific first. Every rung is **[I]**; the fallback — the whole
    /// content container — is the documented v1 behaviour from `parsers.md` §7.
    private static let bodyLadder = [
        "div.message-body",
        "div.mail-body",
        "div.email-body",
        "div.message-content",
        "div.mailer-body"
    ]

    private static func bodyMarkup(in root: Element) throws -> String {
        var container = root
        for query in bodyLadder {
            if let candidate = try root.select(query).first() {
                container = candidate
                break
            }
        }
        // Script and style are never body content, and a raw <script> handed to a renderer or a
        // web view is a liability. Everything else is preserved verbatim.
        for node in try container.select("script, style, noscript").array() {
            try node.remove()
        }
        return try container.html().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Attachments

    /// `parsers.md` §7 v1: `a[href*=download], a[href*=attachment]`, plus W4's own `/files/`
    /// prefix (**[V]** as a path — `/files/user_photos/` appears in real captures — but never
    /// **[V]** as a mail attachment link).
    private static func isAttachmentLink(_ href: String) -> Bool {
        let lowered = href.lowercased()
        return lowered.contains("download")
            || lowered.contains("attachment")
            || lowered.contains("/files/")
    }

    private static func attachmentLinks(
        in root: Element,
        messageID: String
    ) throws -> [MailAttachment] {
        var attachments: [MailAttachment] = []
        var seenURLs: Set<String> = []
        var usedIDs: Set<String> = []

        for anchor in try root.select("a[href]").array() {
            let href = try anchor.attr("href").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty, isAttachmentLink(href), !seenURLs.contains(href) else { continue }
            seenURLs.insert(href)

            var name = W4MailHTML.normalizedText(try anchor.text())
            if name.isEmpty { name = fileName(fromHref: href) }
            if name.isEmpty { name = "Attachment \(attachments.count + 1)" }

            let id = attachmentID(
                href: href,
                messageID: messageID,
                index: attachments.count,
                used: &usedIDs
            )
            attachments.append(MailAttachment(id: id, name: name, url: href))
        }

        return attachments
    }

    /// Last path segment of `href`, when it looks like a file name. `/index.php?...` does not.
    private static func fileName(fromHref href: String) -> String {
        let path = href
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? href
        guard let last = path.split(separator: "/").last else { return "" }
        let decoded = String(last).removingPercentEncoding ?? String(last)
        let candidate = W4MailHTML.normalizedText(decoded)
        guard candidate.contains("."), !candidate.lowercased().hasSuffix(".php") else { return "" }
        return candidate
    }

    /// A stable, non-colliding id for one attachment.
    ///
    /// A bare `id=` is only accepted when it differs from the message id: on an unknown page an
    /// `id=` is far more likely to be the message's own than the file's, and two attachments
    /// sharing an id silently collapse into one row (the same failure mode as bug B18).
    private static func attachmentID(
        href: String,
        messageID: String,
        index: Int,
        used: inout Set<String>
    ) -> String {
        var candidate = W4MailHTML.numericQueryValue(in: href, key: "attachment_id")
            ?? W4MailHTML.numericQueryValue(in: href, key: "file_id")
            ?? W4MailHTML.numericQueryValue(in: href, key: "doc_id")
        if candidate == nil,
           let bare = W4MailHTML.numericQueryValue(in: href, key: "id"),
           bare != messageID {
            candidate = bare
        }

        let prefix = messageID.nilIfEmpty ?? "w4mail"
        var resolved = candidate ?? "\(prefix)-a\(index)"
        if used.contains(resolved) { resolved = "\(resolved)-\(index)" }
        used.insert(resolved)
        return resolved
    }
}
