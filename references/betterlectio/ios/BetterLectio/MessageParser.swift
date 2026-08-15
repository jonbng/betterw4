//
//  MessageParser.swift
//  BetterLectio
//

import Foundation
import SwiftSoup

/// Parser for message threads and details from Lectio.
enum MessageParser {

    struct ParsedMessageThreadPage: Sendable {
        let detail: MessageThreadDetail
        let ownReactionCarrierTargets: [MessageLocator: String]
    }
    
    // MARK: - Parse Messages

    /// Parses message threads from beskeder2.aspx HTML
    static func parseMessageThreads(from html: String) throws -> [MessageThread] {
        let doc = try SwiftSoup.parse(html)
        var threads: [MessageThread] = []

        // Find the message table - mobile view has rows with class "unread" or no class
        // Desktop view has table with ID s_m_Content_Content_threadGV_ctl00
        let table = try doc.select("table[id*=threadGV]").first()
            ?? doc.select("table.ls-table-layout5").first()

        guard let messageTable = table else {
            print("⚠️ No message table found")
            return []
        }

        // Get all rows except header
        let rows = try messageTable.select("tr").dropFirst()

        for row in rows {
            // Check for unread class
            let rowClasses = try row.classNames()
            let isRead = !rowClasses.contains("unread")

            // Find the mobile view container
            let mobileContainer = try row.select("div.message-list-thread-container").first()

            // Get sender from mobile view
            let senderSpan = try mobileContainer?.select("span[title]").first()
                ?? row.select("span[title*=\"(\"]").first()
            let senderTitle = try senderSpan?.attr("title") ?? ""
            // Use title attribute for name — span text has flipped order for teachers
            let senderName = senderTitle.isEmpty ? (try senderSpan?.text() ?? "Ukendt") : senderTitle

            // Determine sender type from class
            let senderClasses = try senderSpan?.classNames() ?? []
            let senderType: SenderType
            if senderClasses.contains("prepend-fonticon-teacher") {
                senderType = .teacher
            } else if senderClasses.contains("prepend-fonticon-student") {
                senderType = .student
            } else {
                senderType = .unknown
            }

            // Get first sender (from desktop view)
            let firstSenderCell = try row.select("td").dropFirst(5).first
            let firstSenderSpan = try firstSenderCell?.select("span[title]").first()
            let firstSenderName = try firstSenderSpan?.text() ?? senderName

            // Get subject/title - look for the EmneMobil link or ch link
            let subjectLink = try mobileContainer?.select("a[id*=EmneMobil]").first()
                ?? row.select("a[id*=ch]").first()
                ?? row.select("a[onclick*=$LB2$]").first()
            var title = try subjectLink?.text() ?? ""

            // Extract thread ID from onclick
            var threadId = ""
            if let onclick = try subjectLink?.attr("onclick") {
                // Match pattern like $LB2$_MC_$_78776027331 or VIEWTHREAD_78776027331
                if let match = onclick.range(of: #"(\d{11,})"#, options: .regularExpression) {
                    threadId = String(onclick[match])
                }
            }

            // Get date - from mobile container or desktop cell
            let dateDiv = try mobileContainer?.select("div.message-list-thread-datetime").first()
            let date = try dateDiv?.text()
                ?? row.select("td.nowrap.textright").first()?.text()
                ?? ""

            // Get recipients
            let recipientsCell = try row.select("td").dropFirst(6).first
            let recipientsSpan = try recipientsCell?.select("span[title]").first()
                ?? recipientsCell?.select("span").first()
            let recipients = try recipientsSpan?.text() ?? ""

            // Check for flag
            let flagImg = try row.select("img[title*=flag]").first()
            let flagSrc = try flagImg?.attr("src") ?? ""
            let isFlagged = flagSrc.contains("flagon")

            // Check for attachment
            let attachmentIcon = try mobileContainer?.select("span.lpm-messageicons span").first()
                ?? row.select("span.prepend-fonticon-dokumenter").first()
            let hasAttachment = attachmentIcon != nil

            // Skip rows without thread ID (header, etc.)
            guard !threadId.isEmpty else { continue }

            threads.append(MessageThread(
                id: threadId,
                title: title,
                senderName: senderName,
                firstSenderName: firstSenderName,
                recipients: recipients,
                date: date,
                isRead: isRead,
                isFlagged: isFlagged,
                hasAttachment: hasAttachment,
                senderType: senderType
            ))
        }

        print("📨 Parsed \(threads.count) message threads")
        return threads
    }

    // MARK: - Parse Message Thread Detail

    /// Parses a message thread detail page into structured content
    static func parseMessageThreadDetail(from html: String, threadId: String) throws -> MessageThreadDetail {
        try parseMessageThreadPage(from: html, threadId: threadId).detail
    }

    static func parseMessageThreadPage(from html: String, threadId: String) throws -> ParsedMessageThreadPage {
        let doc = try SwiftSoup.parse(html)

        // Get recipients from header
        let recipientsDiv = try doc.select("div[id*=RecipientsReadMode]").first()
        let recipients = try recipientsDiv?.text() ?? ""

        var recipientIDs: [String] = []
        if let recipientsDiv {
            recipientIDs.append(contentsOf: try contextCardIDs(in: recipientsDiv))
        }

        // Get thread title from first message header
        let headerDiv = try doc.select("div[id*=messageThreadHeaderDiv]").first()
        let title = try doc.select("div.message-thread-message-header").first()?.text() ?? ""

        // Parse individual messages
        var rawMessages: [MessageReactionProtocol.RawMessage] = []
        let messageRows = try doc.select("table[id*=MessagesGV] tr")

        for (index, row) in messageRows.enumerated() {
            // Skip edit/reply rows
            if try row.select("textarea").first() != nil { continue }

            // Get sender info
            let senderDiv = try row.select("div.message-thread-message-sender").first()
            let senderText = try senderDiv?.text() ?? ""
            if let senderDiv {
                recipientIDs.append(contentsOf: try contextCardIDs(in: senderDiv))
            }
            let senderEntityID = try senderDiv?
                .select("[data-lectiocontextcard]")
                .first()?
                .attr("data-lectiocontextcard")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Parse sender name and date
            // Format: "Name (class), 04-03-2026 11:05:41"
            var senderName = "Ukendt"
            var date = ""
            let components = senderText.components(separatedBy: ", ")
            if components.count >= 2 {
                senderName = components[0]
                date = components[1]
            }

            // Get message title
            let messageTitle = try row.select("div.message-thread-message-header").first()?.text() ?? title

            // Get message content
            let contentDiv = try row.select("div.message-thread-message-content").first()
            var content = try contentDiv?.html() ?? ""

            if content.isEmpty {
                content = try contentDiv?.text() ?? ""
            }

            let rawContent = content
            let editAudit = MessageEditAudit.extract(from: content)
            content = stripAppSignatures(editAudit.html)

            // Parse attachments
            var attachments: [MessageAttachment] = []
            let attachmentLinks = try row.select("a[href*=document]").array()
            for link in attachmentLinks {
                let href = try link.attr("href")
                let name = try link.text()
                if !href.isEmpty {
                    attachments.append(MessageAttachment(
                        id: href,
                        name: name,
                        url: href
                    ))
                }
            }

            let editLink = try row.select("a[id*=EditModeToggleBtn], a[onclick*=EditModeToggleBtn]").first()
            let editScript = ((try? editLink?.attr("onclick")) ?? "") + ((try? editLink?.attr("href")) ?? "")
            let editTarget = firstCapture(in: editScript, pattern: #"__doPostBack\('([^']+)'"#) ?? ""

            rawMessages.append(MessageReactionProtocol.RawMessage(
                message: Message(
                    id: "\(threadId)_\(index)",
                    senderName: senderName,
                    date: date,
                    title: messageTitle,
                    content: content,
                    editedAt: editAudit.editedAt,
                    attachments: attachments,
                    senderEntityID: senderEntityID,
                    editPostbackTarget: editTarget
                ),
                rawContentHTML: rawContent,
                editPostbackTarget: editTarget
            ))
        }

        let resolved = MessageReactionProtocol.resolve(rawMessages)

        var seenRecipientIDs = Set<String>()
        let uniqueRecipientIDs = recipientIDs.filter { seenRecipientIDs.insert($0).inserted }

        let detail = MessageThreadDetail(
            threadId: threadId,
            title: title,
            recipients: recipients,
            recipientIDs: uniqueRecipientIDs,
            messages: resolved.messages,
            canReply: true
        )
        return ParsedMessageThreadPage(
            detail: detail,
            ownReactionCarrierTargets: resolved.ownCarriersByTarget.mapValues(\.editPostbackTarget)
        )
    }

    private static func contextCardIDs(in element: Element) throws -> [String] {
        var elements = try element.select("[data-lectiocontextcard]").array()
        if try element.hasAttr("data-lectiocontextcard") {
            elements.insert(element, at: 0)
        }

        return try elements.compactMap { element in
            let id = try element.attr("data-lectiocontextcard")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard id.hasPrefix("S") || id.hasPrefix("T") || id.hasPrefix("U") else { return nil }
            return id
        }
    }

    private static func stripAppSignatures(_ content: String) -> String {
        content
            .replacingOccurrences(of: "sendt med betterlectio", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "sendt med lectio next", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "sendt fra lectio+", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstCapture(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    // MARK: - Parse Message Form Fields

    /// Struct to hold dynamically discovered field names for the message reply form
    struct MessageReplyFieldNames {
        let titleField: String
        let contentField: String
        let sendButton: String
        let attachmentDocIdField: String?
    }

    /// Extracts form fields needed to send a message reply
    static func parseMessageReplyFormFields(from html: String) throws -> [(name: String, value: String)] {
        return try BaseParser.parseAllFormFields(from: html)
    }

    /// Dynamically finds the field names for title, content, and send button in a message thread reply form
    static func parseMessageReplyFieldNames(from html: String) -> MessageReplyFieldNames? {
        do {
            let doc = try SwiftSoup.parse(html)
            
            // Find the reply textarea (EditModeContentBBTB)
            // It's usually inside a row with SendMessageBtn
            guard let contentArea = try doc.select("textarea[id*=EditModeContentBBTB]").first(),
                  let contentName = try? contentArea.attr("name") else {
                print("⚠️ Could not find message reply content field")
                return nil
            }
            
            // Find the title input (EditModeHeaderTitleTB)
            guard let titleInput = try doc.select("input[id*=EditModeHeaderTitleTB]").first(),
                  let titleName = try? titleInput.attr("name") else {
                print("⚠️ Could not find message reply title field")
                return nil
            }
            
            // Find the send button (SendMessageBtn)
            // It's usually a link with href starting with javascript:__doPostBack('...', '')
            // or an input type="submit"
            var sendButtonName: String?
            
            // Try finding by ID first
            if let sendBtn = try doc.select("[id*=SendMessageBtn]").first() {
                // If it's an <a> tag, the name is in the __doPostBack call in href or onclick
                let href = try sendBtn.attr("href")
                let onclick = try sendBtn.attr("onclick")
                
                let scriptSource = onclick.contains("__doPostBack") ? onclick : href
                
                if scriptSource.contains("__doPostBack") {
                    if let range = scriptSource.range(of: "'([^']*)'", options: .regularExpression) {
                        sendButtonName = String(scriptSource[range]).replacingOccurrences(of: "'", with: "")
                    }
                } else {
                    sendButtonName = try? sendBtn.attr("name")
                }
            }
            
            guard let sendBtnName = sendButtonName, !sendBtnName.isEmpty else {
                print("⚠️ Could not find message reply send button name")
                return nil
            }
            
            // Optional: find attachment doc id field
            let attachmentField = try? doc.select("input[id*=AttachmentDocChooser_selectedDocumentId]").first()?.attr("name")
            
            return MessageReplyFieldNames(
                titleField: titleName,
                contentField: contentName,
                sendButton: sendBtnName,
                attachmentDocIdField: attachmentField
            )
        } catch {
            print("⚠️ Error parsing message reply field names: \(error)")
            return nil
        }
    }

    // MARK: - Folder Tree

    /// Parses the folder tree on beskeder2.aspx into a list of folders the user can pick.
    /// Returns `[]` if the tree can't be located — caller should fall back to `MessageFolder.defaults`.
    static func parseMessageFolders(from html: String) -> [MessageFolder] {
        guard let doc = try? SwiftSoup.parse(html) else { return [] }

        var result: [MessageFolder] = []
        var seen = Set<String>()

        // Desktop TreeView: anchor elements whose onclick/href call
        // __doPostBack('s$m$Content$Content$ListGridSelectionTree$...', '<folderId>').
        if let anchors = try? doc.select("a[onclick*=ListGridSelectionTree], a[href*=ListGridSelectionTree]") {
            for anchor in anchors {
                let onclick = (try? anchor.attr("onclick")) ?? ""
                let href    = (try? anchor.attr("href")) ?? ""
                let source  = onclick.isEmpty ? href : onclick
                guard let id = extractPostbackArgument(from: source) else { continue }

                let name = ((try? anchor.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !seen.contains(id) else { continue }
                seen.insert(id)
                result.append(MessageFolder(id: id, displayName: name))
            }
        }

        // Mobile view: a <select> with <option value="<folderId>">Name</option>.
        if result.isEmpty,
           let options = try? doc.select("select[id*=ListGridSelectionTree] option, select[name*=ListGridSelectionTree] option") {
            for option in options {
                let id   = ((try? option.attr("value")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let name = ((try? option.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, !name.isEmpty, !seen.contains(id) else { continue }
                seen.insert(id)
                result.append(MessageFolder(id: id, displayName: name))
            }
        }

        return result
    }

    /// Extracts the second argument of `__doPostBack('target','argument')` — the folder ID.
    private static func extractPostbackArgument(from source: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"__doPostBack\('[^']*','([^']*)'\)"#) else { return nil }
        let range = NSRange(source.startIndex..., in: source)
        guard let match = regex.firstMatch(in: source, range: range),
              let argRange = Range(match.range(at: 1), in: source) else { return nil }
        let arg = String(source[argRange]).trimmingCharacters(in: .whitespaces)
        return arg.isEmpty ? nil : arg
    }
}
