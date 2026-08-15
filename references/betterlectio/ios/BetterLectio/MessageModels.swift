//
//  MessageModels.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import Foundation

// MARK: - Message Models

/// Represents a message thread in the inbox
struct MessageThread: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String                // thread ID from __doPostBack argument
    let title: String             // message subject
    let senderName: String        // name of latest sender
    let firstSenderName: String   // name of original sender
    let recipients: String        // recipient group(s)
    let date: String              // formatted date string
    let isRead: Bool              // read status
    let isFlagged: Bool           // flagged/starred status
    let hasAttachment: Bool       // has file attachment
    let senderType: SenderType    // student or teacher

    func with(isRead: Bool? = nil, isFlagged: Bool? = nil) -> MessageThread {
        MessageThread(
            id: id,
            title: title,
            senderName: senderName,
            firstSenderName: firstSenderName,
            recipients: recipients,
            date: date,
            isRead: isRead ?? self.isRead,
            isFlagged: isFlagged ?? self.isFlagged,
            hasAttachment: hasAttachment,
            senderType: senderType
        )
    }

    func markedRead() -> MessageThread { with(isRead: true) }
    func toggledRead() -> MessageThread { with(isRead: !isRead) }
    func toggledFlag() -> MessageThread { with(isFlagged: !isFlagged) }
}

enum SenderType: String, Codable, Sendable {
    case student
    case teacher
    case unknown
}

/// Represents a single message within a thread
struct Message: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let senderName: String
    let date: String              // formatted date with time
    let title: String
    let content: String           // HTML content of the message
    let editedAt: Date?
    let attachments: [MessageAttachment]
    let senderEntityID: String?
    let locator: MessageLocator?
    let reactions: [MessageReactionGroup]
    let ownReaction: MessageReactionEmoji?
    let editPostbackTarget: String

    init(
        id: String,
        senderName: String,
        date: String,
        title: String,
        content: String,
        editedAt: Date? = nil,
        attachments: [MessageAttachment],
        senderEntityID: String? = nil,
        locator: MessageLocator? = nil,
        reactions: [MessageReactionGroup] = [],
        ownReaction: MessageReactionEmoji? = nil,
        editPostbackTarget: String = ""
    ) {
        self.id = id
        self.senderName = senderName
        self.date = date
        self.title = title
        self.content = content
        self.editedAt = editedAt
        self.attachments = attachments
        self.senderEntityID = senderEntityID
        self.locator = locator
        self.reactions = reactions
        self.ownReaction = ownReaction
        self.editPostbackTarget = editPostbackTarget
    }

    private enum CodingKeys: String, CodingKey {
        case id, senderName, date, title, content, editedAt, attachments, senderEntityID, locator, reactions, ownReaction, editPostbackTarget
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        senderName = try container.decode(String.self, forKey: .senderName)
        date = try container.decode(String.self, forKey: .date)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        attachments = try container.decode([MessageAttachment].self, forKey: .attachments)
        senderEntityID = try container.decodeIfPresent(String.self, forKey: .senderEntityID)
        locator = try container.decodeIfPresent(MessageLocator.self, forKey: .locator)
        reactions = try container.decodeIfPresent([MessageReactionGroup].self, forKey: .reactions) ?? []
        ownReaction = try container.decodeIfPresent(MessageReactionEmoji.self, forKey: .ownReaction)
        editPostbackTarget = try container.decodeIfPresent(String.self, forKey: .editPostbackTarget) ?? ""
    }

    func with(
        locator: MessageLocator?,
        reactions: [MessageReactionGroup],
        ownReaction: MessageReactionEmoji?
    ) -> Message {
        Message(
            id: id,
            senderName: senderName,
            date: date,
            title: title,
            content: content,
            editedAt: editedAt,
            attachments: attachments,
            senderEntityID: senderEntityID,
            locator: locator,
            reactions: reactions,
            ownReaction: ownReaction,
            editPostbackTarget: editPostbackTarget
        )
    }
}

struct MessageEditDraft: Equatable, Sendable {
    let locator: MessageLocator
    let title: String
    let body: String
    let signatureSuffix: String
    let editHTML: String
    let formAction: String
    let titleField: String
    let bodyField: String
    let saveTarget: String
}

/// Represents a file attachment on a message
struct MessageAttachment: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let url: String
}

/// Complete message thread with all messages
struct MessageThreadDetail: Codable, Equatable, Sendable {
    let threadId: String
    let title: String
    let recipients: String
    let recipientIDs: [String]
    let messages: [Message]
    let canReply: Bool

    init(
        threadId: String,
        title: String,
        recipients: String,
        recipientIDs: [String] = [],
        messages: [Message],
        canReply: Bool
    ) {
        self.threadId = threadId
        self.title = title
        self.recipients = recipients
        self.recipientIDs = recipientIDs
        self.messages = messages
        self.canReply = canReply
    }

    private enum CodingKeys: String, CodingKey {
        case threadId, title, recipients, recipientIDs, messages, canReply
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decode(String.self, forKey: .threadId)
        title = try container.decode(String.self, forKey: .title)
        recipients = try container.decode(String.self, forKey: .recipients)
        recipientIDs = try container.decodeIfPresent([String].self, forKey: .recipientIDs) ?? []
        messages = try container.decode([Message].self, forKey: .messages)
        canReply = try container.decode(Bool.self, forKey: .canReply)
    }

    func withMessages(_ messages: [Message]) -> MessageThreadDetail {
        MessageThreadDetail(
            threadId: threadId,
            title: title,
            recipients: recipients,
            recipientIDs: recipientIDs,
            messages: messages,
            canReply: canReply
        )
    }
}

/// Form data for sending a reply
struct MessageReplyForm: Codable, Sendable {
    let title: String
    let content: String
    let notifyOption: NotifyOption
    let attachmentDocId: String?
}

enum NotifyOption: String, Codable, Sendable {
    case senderOnly           // notify only the original sender
    case none                 // notify nobody
    case all                  // notify all recipients
}

// MARK: - Message Folder

/// Represents a Lectio message folder. IDs come straight from Lectio's
/// `ListGridSelectionTree$folders` field — either the standard virtual folders
/// (Nyeste `-70`, Ulæst `-40`, Egne beskeder `-10`, Sendte `-80`, Slettede `-60`) or a
/// positive user-created folder ID.
struct MessageFolder: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let displayName: String

    static let newest  = MessageFolder(id: "-70", displayName: "Nyeste")
    static let unread  = MessageFolder(id: "-40", displayName: "Ulæst")
    static let inbox   = MessageFolder(id: "-10", displayName: "Egne beskeder")
    static let sent    = MessageFolder(id: "-80", displayName: "Sendte beskeder")
    static let deleted = MessageFolder(id: "-60", displayName: "Alle slettede")

    /// Seed list shown before the first HTML parse completes and as an offline fallback.
    static let defaults: [MessageFolder] = [.newest, .unread, .inbox, .sent, .deleted]
}

// MARK: - Message Composer Model

struct MessageRecipient: Codable, Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let name: String
    let type: RecipientType
    let info: String?           // class, abbreviation, etc.
    let lectioRecipientID: String
}

enum RecipientType: String, Codable, Sendable {
    case student
    case teacher
    case group
    case hold
}
