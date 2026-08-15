//
//  LectioHTTPClient+Messages.swift
//  BetterLectio
//

import Foundation
import SwiftSoup

extension LectioHTTPClient {

    /// Fetches the messages list page (beskeder2.aspx) for a specific folder.
    ///
    /// Lectio stores the active folder in session/ViewState, so a bare
    /// `?mappeid=X` GET does not switch folders. We route through
    /// `postBeskederListPageBack` with an empty `__EVENTARGUMENT` — a pure
    /// folder-switch post that returns the target folder's HTML.
    func fetchMessages(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        folder: MessageFolder = .newest,
        priority: FetchPriority = .important
    ) async throws -> String {
        try await postBeskederListPageBack(
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            folder: folder,
            eventArgument: "",
            contextForLogging: "POST switch folder \(folder.id)",
            priority: priority
        )
    }

    /// Opens a specific message thread, switching folder context in the same POST.
    /// Mirrors lectioDartWrapper's `MessageController.get`.
    func fetchMessageThread(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        threadId: String,
        folder: MessageFolder = .newest,
        priority: FetchPriority = .important
    ) async throws -> String {
        try await postBeskederListPageBack(
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            folder: folder,
            eventArgument: "$LB2$_MC_$_\(threadId)",
            contextForLogging: "POST open message thread \(threadId)",
            priority: priority
        )
    }

    /// Sends a reply to a message thread
    func sendMessageReply(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        threadId: String,
        folder: MessageFolder = .newest,
        title: String,
        content: String,
        attachments: [OutgoingMessageAttachment] = [],
        attachmentStateChanged: ((UUID, OutgoingAttachmentUploadState) async -> Void)? = nil,
        priority: FetchPriority = .important
    ) async throws {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/beskeder2.aspx"
        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        // 1. Fetch the thread page to get VIEWSTATE and form fields
        // We have to open the thread first just like when viewing it
        var html = try await fetchMessageThread(
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            threadId: threadId,
            folder: folder,
            priority: priority
        )
        let messageCountBeforeSend = Self.messageCount(inThreadHTML: html)

        html = try await attachOutgoingFiles(
            attachments,
            to: html,
            formURL: url,
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            priority: priority,
            stateChanged: attachmentStateChanged
        )

        let formFields = try BaseParser.parseAllFormFields(from: html)
        
        // 2. Find the SendMessageBtn inside the messages grid
        // It's usually something like s$m$Content$Content$MessageThreadCtrl$MessagesGV$ctl18$SendMessageBtn
        guard let fieldNames = MessageParser.parseMessageReplyFieldNames(from: html) else {
            throw LectioError.parsingError("Kunne ikke finde svar-felter på siden")
        }

        var formParts: [String] = []
        let overrideKeys: Set<String> = [
            fieldNames.titleField,
            fieldNames.contentField,
            "__EVENTTARGET",
            "__EVENTARGUMENT",
            "__LASTFOCUS"
        ]

        for field in formFields {
            if overrideKeys.contains(field.name) { continue }
            formParts.append("\(formURLEncode(field.name))=\(formURLEncode(field.value))")
        }

        formParts.append("\(formURLEncode(fieldNames.titleField))=\(formURLEncode(title))")
        formParts.append("\(formURLEncode(fieldNames.contentField))=\(formURLEncode(content))")
        
        if let attachmentField = fieldNames.attachmentDocIdField {
            formParts.removeAll { $0.hasPrefix("\(formURLEncode(attachmentField))=") }
            formParts.append("\(formURLEncode(attachmentField))=")
        }

        formParts.insert("__EVENTTARGET=\(formURLEncode(fieldNames.sendButton))", at: 0)
        formParts.insert("__EVENTARGUMENT=", at: 1)

        let bodyString = formParts.joined(separator: "&")
        let headers = [
            "Referer": "https://www.lectio.dk/lectio/\(schoolId)/beskeder2.aspx?mappeid=\(folder.id)",
            "Origin": "https://www.lectio.dk",
            "Content-Type": "application/x-www-form-urlencoded"
        ]

        let (data, _, _) = try await performRequest(
            url: url,
            method: "POST",
            body: bodyString.data(using: .utf8),
            headers: headers,
            credentials: credentials,
            studentId: studentId,
            contextForLogging: "POST reply to thread \(threadId)",
            priority: priority
        )

        let responseHtml = decodeHTML(from: data)
        if responseHtml.contains("Du er blevet logget ud") {
            throw LectioError.cookieExpired
        }
        guard Self.messageCount(inThreadHTML: responseHtml) > messageCountBeforeSend else {
            throw LectioError.parsingError("Lectio bekræftede ikke, at svaret blev sendt")
        }
    }

    /// Sets, changes, or clears the current user's reaction using Lectio's
    /// ordinary reply/edit postbacks. No BetterLectio backend is involved.
    func setMessageReaction(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        threadId: String,
        folder: MessageFolder = .newest,
        target: MessageLocator,
        emoji: MessageReactionEmoji?,
        showSignature: Bool,
        priority: FetchPriority = .important
    ) async throws -> MessageThreadDetail {
        guard let formURL = URL(string: "https://www.lectio.dk/lectio/\(schoolId)/beskeder2.aspx") else {
            throw LectioError.invalidURL
        }
        let initialHTML = try await fetchMessageThread(
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            threadId: threadId,
            folder: folder,
            priority: priority
        )
        let initial = try MessageParser.parseMessageThreadPage(from: initialHTML, threadId: threadId)
        guard initial.detail.messages.contains(where: { $0.locator == target }) else {
            throw LectioError.parsingError("Den valgte besked findes ikke længere")
        }
        let envelope: MessageReactionEnvelope = emoji.map { .set(emoji: $0, target: target) }
            ?? .clear(target: target)
        let body = MessageReactionProtocol.carrierBody(for: envelope, showSignature: showSignature)
        let responseHTML: String

        if let editTarget = initial.ownReactionCarrierTargets[target], !editTarget.isEmpty {
            let openEdit = try await postMessageForm(
                url: formURL,
                credentials: credentials,
                studentId: studentId,
                schoolId: schoolId,
                formFields: try BaseParser.parseAllFormFields(from: initialHTML),
                eventTarget: editTarget,
                priority: priority
            ).html
            guard let fields = Self.parseReactionEditFields(from: openEdit, editTarget: editTarget) else {
                throw LectioError.parsingError("Kunne ikke åbne reaktionen til redigering")
            }
            responseHTML = try await postMessageForm(
                url: formURL,
                credentials: credentials,
                studentId: studentId,
                schoolId: schoolId,
                formFields: try BaseParser.parseAllFormFields(from: openEdit),
                eventTarget: fields.saveTarget,
                overrideFields: [
                    fields.titleField: fields.title,
                    fields.bodyField: body
                ],
                priority: priority
            ).html
        } else {
            guard let fields = MessageParser.parseMessageReplyFieldNames(from: initialHTML) else {
                throw LectioError.parsingError("Kunne ikke finde svar-felter på siden")
            }
            let formFields = try BaseParser.parseAllFormFields(from: initialHTML)
            let title = formFields.filter { $0.name == fields.titleField }.first?.value
                .flatMap { $0.isEmpty ? nil : $0 } ?? "Re: \(initial.detail.title)"
            responseHTML = try await postMessageForm(
                url: formURL,
                credentials: credentials,
                studentId: studentId,
                schoolId: schoolId,
                formFields: formFields,
                eventTarget: fields.sendButton,
                overrideFields: [
                    fields.titleField: title,
                    fields.contentField: body
                ],
                priority: priority
            ).html
        }

        guard !Self.messagePostbackHasValidationError(responseHTML) else {
            throw LectioError.parsingError("Lectio afviste reaktionen")
        }
        let confirmed = try MessageParser.parseMessageThreadPage(from: responseHTML, threadId: threadId)
        guard let message = confirmed.detail.messages.first(where: { $0.locator == target }),
              message.ownReaction == emoji,
              confirmed.ownReactionCarrierTargets[target] != nil else {
            throw LectioError.parsingError("Lectio bekræftede ikke reaktionen")
        }
        return confirmed.detail
    }

    struct ReactionEditFields: Equatable {
        let titleField: String
        let bodyField: String
        let saveTarget: String
        let title: String
        let body: String
    }

    static func parseReactionEditFields(from html: String, editTarget: String) -> ReactionEditFields? {
        let suffix = "$EditModeToggleBtn"
        guard editTarget.hasSuffix(suffix) else { return nil }
        let prefix = String(editTarget.dropLast(suffix.count))
        guard let document = try? SwiftSoup.parse(html),
              let bodyFields = try? document.select("textarea[name*=EditModeContentBBTB]").array(),
              let body = bodyFields.first(where: { ((try? $0.attr("name")) ?? "").hasPrefix(prefix + "$") }),
              let titleFields = try? document.select("input[name*=EditModeHeaderTitleTB]").array(),
              let title = titleFields.first(where: { ((try? $0.attr("name")) ?? "").hasPrefix(prefix + "$") }) else {
            return nil
        }
        var scope: Element? = body
        while let element = scope, element.tagName() != "tr" {
            scope = try? element.parent()
        }
        let links = (try? scope?.select("a[onclick*=__doPostBack], a[href*=__doPostBack]").array()) ?? []
        let targets = links.compactMap { link -> String? in
            let script = ((try? link.attr("onclick")) ?? "") + ((try? link.attr("href")) ?? "")
            guard let regex = try? NSRegularExpression(pattern: #"__doPostBack\('([^']+)'"#),
                  let match = regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
                  let range = Range(match.range(at: 1), in: script) else { return nil }
            return String(script[range])
        }
        let saveButtonOptions: String.CompareOptions = [.regularExpression, .caseInsensitive]
        let saveTarget = targets.first {
            $0.hasPrefix(prefix + "$") &&
                $0.range(of: #"\$(Send|Save|Update)MessageBtn$"#, options: saveButtonOptions) != nil
        }
        guard let saveTarget,
              let titleName = try? title.attr("name"),
              let bodyName = try? body.attr("name") else { return nil }
        return ReactionEditFields(
            titleField: titleName,
            bodyField: bodyName,
            saveTarget: saveTarget,
            title: (try? title.attr("value")) ?? "",
            body: (try? body.val()) ?? ""
        )
    }

    private static func messageFormURL(from html: String, fallback: URL) -> URL {
        guard let document = try? SwiftSoup.parse(html),
              let forms = try? document.select("form[action]"),
              let form = forms.first(),
              let action = try? form.attr("action"), !action.isEmpty,
              let resolved = URL(string: action, relativeTo: fallback)?.absoluteURL else {
            return fallback
        }
        return resolved
    }

    func beginMessageEdit(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        threadId: String,
        folder: MessageFolder,
        locator: MessageLocator
    ) async throws -> MessageEditDraft {
        guard let formURL = URL(string: "https://www.lectio.dk/lectio/\(schoolId)/beskeder2.aspx") else {
            throw LectioError.invalidURL
        }
        let html = try await fetchMessageThread(
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            threadId: threadId,
            folder: folder
        )
        let parsed = try MessageParser.parseMessageThreadPage(from: html, threadId: threadId)
        guard let target = parsed.detail.messages.first(where: { $0.locator == locator })?.editPostbackTarget,
              !target.isEmpty else {
            throw LectioError.parsingError("Beskeden kan ikke længere redigeres")
        }
        let editHTML = try await postMessageForm(
            url: Self.messageFormURL(from: html, fallback: formURL),
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            formFields: try BaseParser.parseAllFormFields(from: html),
            eventTarget: target
        ).html
        guard let fields = Self.parseReactionEditFields(from: editHTML, editTarget: target) else {
            throw LectioError.parsingError("Kunne ikke åbne beskeden til redigering")
        }
        let split = Self.splitEditableSignature(fields.body)
        let editAction = Self.messageFormURL(from: editHTML, fallback: formURL)
        return MessageEditDraft(
            locator: locator,
            title: fields.title,
            body: split.body,
            signatureSuffix: split.signature,
            editHTML: editHTML,
            formAction: editAction.absoluteString,
            titleField: fields.titleField,
            bodyField: fields.bodyField,
            saveTarget: fields.saveTarget
        )
    }

    func saveMessageEdit(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        threadId: String,
        draft: MessageEditDraft,
        title: String,
        body: String
    ) async throws -> MessageThreadDetail {
        guard title.count <= 100, body.count + draft.signatureSuffix.count <= 100_000 else {
            throw LectioError.parsingError("Beskeden overskrider Lectios tegnbegrænsning")
        }
        guard let formURL = URL(string: draft.formAction) else {
            throw LectioError.invalidURL
        }
        let response = try await postMessageForm(
            url: formURL,
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            formFields: try BaseParser.parseAllFormFields(from: draft.editHTML),
            eventTarget: draft.saveTarget,
            overrideFields: [
                draft.titleField: title,
                draft.bodyField: body + draft.signatureSuffix
            ]
        ).html
        guard !Self.messagePostbackHasValidationError(response) else {
            throw LectioError.parsingError("Lectio afviste redigeringen")
        }
        return try MessageParser.parseMessageThreadPage(from: response, threadId: threadId).detail
    }

    static func splitEditableSignature(_ body: String) -> (body: String, signature: String) {
        let pattern = #"(\n\n\[url=https://betterlectio\.dk/download\]Sendt med BetterLectio\[/url\])\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let range = Range(match.range(at: 1), in: body) else { return (body, "") }
        return (String(body[..<range.lowerBound]), String(body[range]))
    }

    /// Marks a message as read by sending the read postback
    func markMessageAsRead(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        threadId: String,
        folder: MessageFolder = .newest,
        priority: FetchPriority = .important
    ) async throws {
        try await postBeskederListPageBack(
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            folder: folder,
            eventArgument: "READMESSAGE_\(threadId)",
            contextForLogging: "POST mark message as read \(threadId)",
            priority: priority
        )
    }

    /// Toggles the read/unread state of a message via the same endpoint as `markMessageAsRead`.
    /// The server-side behavior is a toggle, so calling this on a read message marks it unread and vice versa.
    func toggleMessageReadStatus(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        threadId: String,
        folder: MessageFolder = .newest,
        priority: FetchPriority = .important
    ) async throws {
        try await postBeskederListPageBack(
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            folder: folder,
            eventArgument: "READMESSAGE_\(threadId)",
            contextForLogging: "POST toggle read status \(threadId)",
            priority: priority
        )
    }

    /// Toggles the flag state of a message.
    func toggleMessageFlag(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        threadId: String,
        priority: FetchPriority = .important
    ) async throws {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/beskeder2.aspx"
        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        let eventArg = "FLAGMESSAGE_\(threadId)"
        let bodyString = "__EVENTTARGET=__Page&__EVENTARGUMENT=\(formURLEncode(eventArg))"
        let headers = [
            "Referer": "https://www.lectio.dk/lectio/\(schoolId)/beskeder2.aspx",
            "Content-Type": "application/x-www-form-urlencoded"
        ]

        _ = try await performRequest(
            url: url,
            method: "POST",
            body: bodyString.data(using: .utf8),
            headers: headers,
            credentials: credentials,
            studentId: studentId,
            contextForLogging: "POST toggle flag \(threadId)",
            priority: priority
        )
    }

    /// Deletes (hides) a message.
    ///
    /// Matches `MesssageController.delete` in lectioDartWrapper: GET the folder list page so we have
    /// VIEWSTATE and other ASP.NET fields, then POST `__Page` with `HIDEMESSAGE_<id>` and the folder
    /// tree field — a bare `__EVENTTARGET`/`__EVENTARGUMENT` pair is rejected by the server.
    func deleteMessage(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        threadId: String,
        folder: MessageFolder = .newest,
        priority: FetchPriority = .important
    ) async throws {
        print("🗑️ [MessageDelete] HTTP HIDEMESSAGE start threadId=\(threadId) mappeid=\(folder.id)")
        try await postBeskederListPageBack(
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            folder: folder,
            eventArgument: "HIDEMESSAGE_\(threadId)",
            contextForLogging: "POST delete message \(threadId)",
            priority: priority
        )
        print("🗑️ [MessageDelete] HTTP HIDEMESSAGE finished OK threadId=\(threadId)")
    }

    /// GET folder list, then POST `__Page` with a full ASP.NET form (VIEWSTATE + folder tree),
    /// matching lectioDartWrapper `postLoggedInPageSoup`. Returns the HTML of the POST response
    /// so callers that need the new folder's / thread's page can parse it; action-only callers
    /// can ignore the return value.
    @discardableResult
    private func postBeskederListPageBack(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        folder: MessageFolder,
        eventArgument: String,
        contextForLogging: String,
        priority: FetchPriority
    ) async throws -> String {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/beskeder2.aspx?mappeid=\(folder.id)"
        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        let (pageData, _, _) = try await performRequest(
            url: url,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )
        let pageHtml = decodeHTML(from: pageData)
        let formFields = try BaseParser.parseAllFormFields(from: pageHtml)

        let foldersFieldName = "s$m$Content$Content$ListGridSelectionTree$folders"
        var formParts: [String] = []
        let skipFields: Set<String> = ["__EVENTTARGET", "__EVENTARGUMENT", foldersFieldName]

        for field in formFields {
            if skipFields.contains(field.name) { continue }
            formParts.append("\(formURLEncode(field.name))=\(formURLEncode(field.value))")
        }

        formParts.append("\(formURLEncode(foldersFieldName))=\(formURLEncode(folder.id))")

        formParts.insert("__EVENTTARGET=__Page", at: 0)
        formParts.insert("__EVENTARGUMENT=\(formURLEncode(eventArgument))", at: 1)

        let bodyString = formParts.joined(separator: "&")
        let headers = [
            "Referer": "https://www.lectio.dk/lectio/\(schoolId)/beskeder2.aspx",
            "Origin": "https://www.lectio.dk",
            "Content-Type": "application/x-www-form-urlencoded"
        ]

        let (data, _, _) = try await performRequest(
            url: url,
            method: "POST",
            body: bodyString.data(using: .utf8),
            headers: headers,
            credentials: credentials,
            studentId: studentId,
            contextForLogging: contextForLogging,
            priority: priority
        )

        return decodeHTML(from: data)
    }

    /// Sends a new message through Lectio's multi-step ASP.NET compose flow.
    func sendNewMessage(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        recipients: [MessageRecipient],
        title: String,
        content: String,
        attachments: [OutgoingMessageAttachment] = [],
        attachmentStateChanged: ((UUID, OutgoingAttachmentUploadState) async -> Void)? = nil,
        priority: FetchPriority = .important
    ) async throws -> String {
        let baseURLString = "https://www.lectio.dk/lectio/\(schoolId)/beskeder2.aspx"
        guard let baseURL = URL(string: baseURLString) else {
            throw LectioError.invalidURL
        }

        // Step 1: GET messages page
        let (pageData, _, _) = try await performRequest(
            url: baseURL,
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )
        var currentHTML = decodeHTML(from: pageData)

        // Step 2: POST to open compose form
        var formFields = try BaseParser.parseAllFormFields(from: currentHTML)
        let newMsgTarget = findNewMessageButton(in: currentHTML)

        let step2Result = try await postMessageForm(
            url: baseURL,
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            formFields: formFields,
            eventTarget: newMsgTarget,
            priority: priority
        )
        currentHTML = step2Result.html

        // Step 3: Add each recipient
        for recipient in recipients {
            let recipientCountBefore = Self.parseComposeRecipientNames(from: currentHTML).count
            formFields = try BaseParser.parseAllFormFields(from: currentHTML)
            let lectioId = recipient.lectioRecipientID

            let addResult = try await postMessageForm(
                url: baseURL,
                credentials: credentials,
                studentId: studentId,
                schoolId: schoolId,
                formFields: formFields,
                eventTarget: "s$m$Content$Content$MessageThreadCtrl$AddRecipientBtn",
                overrideFields: [
                    "s$m$Content$Content$MessageThreadCtrl$addRecipientDD$inpid": lectioId,
                    "s$m$Content$Content$MessageThreadCtrl$addRecipientDD$inp": recipient.name
                ],
                priority: priority
            )
            guard Self.parseComposeRecipientNames(from: addResult.html).count > recipientCountBefore else {
                throw LectioError.parsingError("Lectio bekræftede ikke modtageren \(recipient.name)")
            }
            currentHTML = addResult.html
        }

        // Upload and attach one file at a time. Each postback returns a new
        // ViewState which must be used by the following attachment or send.
        currentHTML = try await attachOutgoingFiles(
            attachments,
            to: currentHTML,
            formURL: baseURL,
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            priority: priority,
            stateChanged: attachmentStateChanged
        )

        // Step 4: Send the message
        formFields = try BaseParser.parseAllFormFields(from: currentHTML)
        let liveFields = MessageParser.parseMessageReplyFieldNames(from: currentHTML)
        let titleField = liveFields?.titleField ?? "s$m$Content$Content$MessageThreadCtrl$MessagesGV$ctl02$EditModeHeaderTitleTB$tb"
        let contentField = liveFields?.contentField ?? "s$m$Content$Content$MessageThreadCtrl$MessagesGV$ctl02$EditModeContentBBTB$TbxNAME$tb"
        let sendTarget = liveFields?.sendButton ?? "s$m$Content$Content$MessageThreadCtrl$MessagesGV$ctl02$SendMessageBtn"
        let attachmentField = liveFields?.attachmentDocIdField ?? "s$m$Content$Content$MessageThreadCtrl$MessagesGV$ctl02$AttachmentDocChooser$selectedDocumentId"

        let (responseHTML, finalURL) = try await postMessageForm(
            url: baseURL,
            credentials: credentials,
            studentId: studentId,
            schoolId: schoolId,
            formFields: formFields,
            eventTarget: sendTarget,
            overrideFields: [
                titleField: title,
                contentField: content,
                attachmentField: ""
            ],
            priority: priority
        )

        if Self.messagePostbackHasValidationError(responseHTML) {
            throw LectioError.parsingError("Kunne ikke sende besked – server returnerede fejl")
        }

        let threadId = Self.extractThreadId(from: finalURL, html: responseHTML)
        guard let threadId else {
            throw LectioError.parsingError("Kunne ikke finde tråd-ID for sendt besked")
        }
        return threadId
    }

    /// Fetches raw binary data for a message attachment via the authenticated session.
    func fetchAttachmentData(
        relativePath: String,
        credentials: LectioCredentials,
        studentId: String,
        priority: FetchPriority = .important
    ) async throws -> Data {
        let urlString = "https://www.lectio.dk\(relativePath)"
        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }
        let (data, _, _) = try await performRequest(url: url, credentials: credentials, studentId: studentId, priority: priority)
        return data
    }

    // MARK: - Message Helpers

    static func parseUploadedDocumentID(from response: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
           let value = object["serializedId"] as? String,
           !value.isEmpty {
            return value
        }
        guard let text = String(data: response, encoding: .utf8) else { return nil }
        let pattern = #"serializedId['\"\s:]+['\"]([^'\"]+)['\"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func findAttachmentPostbackFields(in html: String) -> (documentID: String, target: String)? {
        let pattern = #"name\s*=\s*[\"']([^\"']*AttachmentDocChooser\$selectedDocumentId)[\"']"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let field = String(html[range])
            return (field, String(field.dropLast("$selectedDocumentId".count)))
        }

        let idPattern = #"id\s*=\s*[\"']([^\"']*AttachmentDocChooser_selectedDocumentId)[\"']"#
        if let regex = try? NSRegularExpression(pattern: idPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let field = String(html[range]).replacingOccurrences(of: "_", with: "$")
            return (field, String(field.dropLast("$selectedDocumentId".count)))
        }
        guard html.localizedCaseInsensitiveContains("AttachmentDocChooser") else { return nil }
        let fallback = "s$m$Content$Content$MessageThreadCtrl$MessagesGV$ctl02$AttachmentDocChooser$selectedDocumentId"
        return (fallback, String(fallback.dropLast("$selectedDocumentId".count)))
    }

    static func parseAttachedFileNames(from html: String) -> [String] {
        guard let document = try? SwiftSoup.parse(html),
              let rows = try? document.select("table[id*=AttachmentsGV] tr") else { return [] }
        return rows.array().compactMap { row in
            let hasDeleteControl = ((try? row.select("a[onclick*=AttachmentsGV], a[href*=AttachmentsGV]").isEmpty()) == false)
            guard hasDeleteControl else { return nil }
            if let link = try? row.select("a[href*=LectioFileHandler]").first(),
               let text = try? link.text(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let cell = try? row.select("td").first(),
                  let text = try? cell.text() else { return nil }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func parseComposeRecipientNames(from html: String) -> [String] {
        guard let document = try? SwiftSoup.parse(html),
              let rows = try? document.select("table[id*=ThreadRecipientsGV] tr") else { return [] }
        return rows.array().compactMap { row in
            if ((try? row.select(".noRecord").isEmpty()) == false) { return nil }
            guard let cell = try? row.select("td").first(),
                  let text = try? cell.text() else { return nil }
            let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        }
    }

    static func attachmentPostbackSucceeded(html: String, expectedFileName: String) -> Bool {
        guard html.contains("__VIEWSTATE") else { return false }
        let expected = expectedFileName.precomposedStringWithCanonicalMapping
        return parseAttachedFileNames(from: html).contains {
            $0.precomposedStringWithCanonicalMapping.compare(expected, options: [.caseInsensitive]) == .orderedSame
        }
    }

    static func messagePostbackHasValidationError(_ html: String) -> Bool {
        let lower = html.lowercased()
        return lower.contains("validation-summary-errors") ||
            lower.contains("field-validation-error") ||
            lower.contains("fejlhandled.aspx") ||
            lower.contains("du er blevet logget ud")
    }

    static func messageCount(inThreadHTML html: String) -> Int {
        guard let document = try? SwiftSoup.parse(html),
              let rows = try? document.select("table[id*=MessagesGV] tr") else { return 0 }
        return rows.array().reduce(into: 0) { count, row in
            let hasContent = (try? row.select("div.message-thread-message-content").first()) != nil
            let isEditor = (try? row.select("textarea").first()) != nil
            if hasContent && !isEditor { count += 1 }
        }
    }

    private func attachOutgoingFiles(
        _ attachments: [OutgoingMessageAttachment],
        to initialHTML: String,
        formURL: URL,
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        priority: FetchPriority,
        stateChanged: ((UUID, OutgoingAttachmentUploadState) async -> Void)?
    ) async throws -> String {
        var html = initialHTML
        for attachment in attachments {
            await stateChanged?(attachment.id, .uploading)
            do {
                let serializedID = try await uploadMessageDocument(
                    attachment,
                    credentials: credentials,
                    studentId: studentId,
                    schoolId: schoolId,
                    priority: priority
                )
                guard let fields = Self.findAttachmentPostbackFields(in: html) else {
                    throw LectioError.parsingError("Kunne ikke finde vedhæftningsfeltet")
                }
                let jsonData = try JSONSerialization.data(withJSONObject: ["serializedId": serializedID])
                let json = String(decoding: jsonData, as: UTF8.self)
                let formFields = try BaseParser.parseAllFormFields(from: html)
                let responseHTML = try await postMessageForm(
                    url: formURL,
                    credentials: credentials,
                    studentId: studentId,
                    schoolId: schoolId,
                    formFields: formFields,
                    eventTarget: fields.target,
                    eventArgument: "documentId",
                    overrideFields: [fields.documentID: json],
                    priority: priority
                ).html
                guard Self.attachmentPostbackSucceeded(
                    html: responseHTML,
                    expectedFileName: attachment.displayName
                ) else {
                    throw LectioError.parsingError("Lectio bekræftede ikke vedhæftningen")
                }
                html = responseHTML
                await stateChanged?(attachment.id, .attached)
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    await stateChanged?(attachment.id, .pending)
                    throw CancellationError()
                }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await stateChanged?(attachment.id, .failed(message))
                throw OutgoingAttachmentUploadError(
                    attachmentID: attachment.id,
                    fileName: attachment.displayName,
                    reason: message
                )
            }
        }
        return html
    }

    private func uploadMessageDocument(
        _ attachment: OutgoingMessageAttachment,
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        priority: FetchPriority
    ) async throws -> String {
        guard attachment.size > 0, attachment.size <= OutgoingMessageAttachment.maximumByteCount else {
            throw LectioError.parsingError("Filen er tom eller større end 25 MB")
        }
        let boundary = "BetterLectio-\(UUID().uuidString)"
        let multipartFile = try Self.makeMultipartBodyFile(for: attachment, boundary: boundary)
        defer { try? FileManager.default.removeItem(at: multipartFile) }

        guard let url = URL(string: "https://www.lectio.dk/lectio/\(schoolId)/dokumentupload.aspx") else {
            throw LectioError.invalidURL
        }
        let (data, _, _) = try await performFileUploadRequest(
            url: url,
            bodyFileURL: multipartFile,
            headers: [
                "Content-Type": "multipart/form-data; boundary=\(boundary)",
                "Origin": "https://www.lectio.dk"
            ],
            credentials: credentials,
            studentId: studentId,
            priority: priority
        )
        guard let serializedID = Self.parseUploadedDocumentID(from: data) else {
            throw LectioError.parsingError("Lectio returnerede et ugyldigt upload-svar")
        }
        return serializedID
    }

    nonisolated static func makeMultipartBodyFile(
        for attachment: OutgoingMessageAttachment,
        boundary: String
    ) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterLectioMessageAttachments", isDirectory: true)
            .appendingPathComponent("multipart-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw LectioError.parsingError("Kunne ikke klargøre filen til upload")
        }

        do {
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            let safeName = attachment.displayName
                .replacingOccurrences(of: "\"", with: "'")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
            try output.write(contentsOf: Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n".utf8))
            try output.write(contentsOf: Data("Content-Type: \(attachment.mimeType)\r\n\r\n".utf8))

            let input = try FileHandle(forReadingFrom: attachment.localURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 256 * 1_024), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func extractThreadId(from url: URL?, html: String) -> String? {
        if let url,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
           !id.isEmpty {
            return id
        }

        let htmlPatterns = [
            #"type=visbesked[^"&]*&(?:amp;)?id=(\d+)"#,
            #"visbesked[^"]*[?&]id=(\d+)"#,
        ]
        for pattern in htmlPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let idRange = Range(match.range(at: 1), in: html) {
                return String(html[idRange])
            }
        }
        return nil
    }

    private func findNewMessageButton(in html: String) -> String {
        let postbackPatterns = [
            "__doPostBack\\('([^']*NewThread[^']*)'",
            "__doPostBack\\('([^']*NewMessage(?!Same)[^']*)'",
            "__doPostBack\\('([^']*CreateThread[^']*)'",
            "__doPostBack\\('([^']*NyBesked[^']*)'",
        ]

        for pattern in postbackPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches {
                guard let range = Range(match.range(at: 1), in: html) else { continue }
                let target = String(html[range])
                if !target.contains("SameReceivers") {
                    return target
                }
            }
        }

        let candidates = [
            "s$m$Content$Content$NewThreadBtn",
            "s$m$Content$Content$NewMessageBtn",
            "s$m$Content$Content$ListGridSelectionToolbar$NewThreadBtn",
            "s$m$Content$Content$CreateNewMessageBtn",
        ]

        for candidate in candidates {
            let idForm = candidate.replacingOccurrences(of: "$", with: "_")
            if html.contains(idForm) {
                return candidate
            }
        }

        return "s$m$Content$Content$NewThreadBtn"
    }

    private func postMessageForm(
        url: URL,
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        formFields: [(name: String, value: String)],
        eventTarget: String,
        eventArgument: String = "",
        overrideFields: [String: String] = [:],
        priority: FetchPriority = .important
    ) async throws -> (html: String, finalURL: URL?) {
        let headers = [
            "Referer": "https://www.lectio.dk/lectio/\(schoolId)/beskeder2.aspx",
            "Origin": "https://www.lectio.dk",
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8"
        ]

        var skipFieldNames: Set<String> = ["__EVENTTARGET", "__EVENTARGUMENT"]
        for key in overrideFields.keys {
            skipFieldNames.insert(key)
        }

        var formParts: [String] = []
        formParts.append("__EVENTTARGET=\(formURLEncode(eventTarget))")
        formParts.append("__EVENTARGUMENT=\(formURLEncode(eventArgument))")

        for field in formFields {
            if skipFieldNames.contains(field.name) { continue }
            formParts.append("\(formURLEncode(field.name))=\(formURLEncode(field.value))")
        }

        for (key, value) in overrideFields {
            formParts.append("\(formURLEncode(key))=\(formURLEncode(value))")
        }

        let bodyString = formParts.joined(separator: "&")
        let (data, _, finalURL) = try await performRequest(
            url: url,
            method: "POST",
            body: bodyString.data(using: .utf8),
            headers: headers,
            credentials: credentials,
            studentId: studentId,
            contextForLogging: "POST message form (\(eventTarget))",
            priority: priority
        )

        // Note: performRequest already handles cookie updates and keychain storage
        // but it doesn't return the final URL yet. I need to get it from performRequest.
        // Wait, I updated performRequest to return (data, updatedCredentials).
        // I should also return the final URL from performRequest.
        
        // Let's modify performRequest to return the final HTTPURLResponse as well.
        // Or just the URL.
        
        // Actually, let's look at performRequest again.
        // Case redirects: it updates currentURL.
        // In the return statement (case 200), it returns data and creds.
        
        // I'll update performRequest to return (data: Data, updatedCredentials: LectioCredentials?, finalURL: URL)
        
        return (decodeHTML(from: data), finalURL)
    }
}

struct OutgoingAttachmentUploadError: LocalizedError {
    let attachmentID: UUID
    let fileName: String
    let reason: String

    var errorDescription: String? { "Kunne ikke vedhæfte \(fileName): \(reason)" }
}
