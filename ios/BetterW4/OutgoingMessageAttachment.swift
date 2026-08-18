//
//  OutgoingMessageAttachment.swift
//  BetterW4
//
//  A file the student has picked for an outgoing W4 mail, staged in the app's temporary
//  directory until it is either sent or discarded.
//
//  The limits here are W4's, from README §5.2 and plan decision D-26: **5 files, 2 MB each**,
//  posted as repeated `MailerForm[attachment][]` multipart parts. They are deliberately much
//  tighter than the 10 × 25 MB this file carried in its Lectio life — W4 is one small Apache box
//  and it rejects anything larger, so failing here with a clear message beats failing on the
//  server with a Yii stack trace. The numbers live in `MailAttachmentLimits` (MailModels.swift)
//  and are only re-exported below so a picker does not have to know two type names.
//
//  There is no upload state: W4's `mailer/send` POST shape has never been verified against the
//  real server, so `MailFeatureFlags.composeEnabled` is off and nothing in the app uploads
//  anything yet (see `ComposeMessageViewModel`). Per-file progress comes back with the transport
//  when a capture lands, not before.
//

import Foundation
import Photos
import SwiftUI
import UniformTypeIdentifiers

struct OutgoingMessageAttachment: Identifiable, Equatable, Sendable {

    /// W4's server-side limits, re-exported so callers need one type, not two.
    static let maximumCount = MailAttachmentLimits.maximumCount
    static let maximumByteCount = MailAttachmentLimits.maximumByteCount

    let id: UUID
    let displayName: String
    let mimeType: String
    let size: Int64
    let localURL: URL
    /// Identity for de-duplication: picking the same file twice must not stage it twice.
    let selectionKey: String

    init(
        id: UUID = UUID(),
        displayName: String,
        mimeType: String,
        size: Int64,
        localURL: URL,
        selectionKey: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.mimeType = mimeType
        self.size = size
        self.localURL = localURL
        self.selectionKey = selectionKey ?? localURL.standardizedFileURL.path
    }

    // MARK: - Staging

    nonisolated static func copyFromFileImporter(_ sourceURL: URL) throws -> OutgoingMessageAttachment {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        let values = try sourceURL.resourceValues(forKeys: [.contentTypeKey, .nameKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw OutgoingAttachmentSelectionError.unsupportedFileType
        }
        let name = values.name ?? sourceURL.lastPathComponent
        let type = values.contentType ?? UTType(filenameExtension: sourceURL.pathExtension)
        let destination = try temporaryURL(fileName: name)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            let size = Int64(try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            try validate(size: size)
            return OutgoingMessageAttachment(
                displayName: name,
                mimeType: type?.preferredMIMEType ?? "application/octet-stream",
                size: size,
                localURL: destination,
                selectionKey: "file|\(sourceURL.standardizedFileURL.path)|\(size)"
            )
        } catch {
            try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
            throw error
        }
    }

    nonisolated static func createFromPhotoData(
        _ data: Data,
        fileName: String,
        type: UTType?,
        assetIdentifier: String? = nil
    ) throws -> OutgoingMessageAttachment {
        let size = Int64(data.count)
        try validate(size: size)
        let destination = try temporaryURL(fileName: fileName)
        do {
            try data.write(to: destination, options: .atomic)
            return OutgoingMessageAttachment(
                displayName: fileName,
                mimeType: type?.preferredMIMEType ?? "image/jpeg",
                size: size,
                localURL: destination,
                selectionKey: assetIdentifier.map { "photo|\($0)" }
                    ?? "photo-data|\(data.count)|\(data.prefix(64).base64EncodedString())"
            )
        } catch {
            try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
            throw error
        }
    }

    /// The name the photo has in the library, so a sent file is not called `IMG_0001` when the
    /// student named it something else.
    nonisolated static func originalPhotoFileName(assetIdentifier: String?, fallback: String) -> String {
        guard let assetIdentifier else { return fallback }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = assets.firstObject,
              let resource = PHAssetResource.assetResources(for: asset).first,
              !resource.originalFilename.isEmpty else { return fallback }
        return resource.originalFilename
    }

    // MARK: - Housekeeping

    /// Drops staged files older than `age`. Called at launch (`BetterW4App`) so a crash mid-compose
    /// cannot leave someone's documents sitting in `tmp/` forever.
    nonisolated static func purgeStaleTemporaryFiles(olderThan age: TimeInterval = 24 * 60 * 60) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterW4MailAttachments", isDirectory: true)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = TimeProvider.now.addingTimeInterval(-age)
        for child in children {
            let modified = try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modified.map({ $0 < cutoff }) ?? true {
                try? FileManager.default.removeItem(at: child)
            }
        }
    }

    func removeTemporaryFile() {
        try? FileManager.default.removeItem(at: localURL.deletingLastPathComponent())
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    // MARK: - Private

    private nonisolated static func validate(size: Int64) throws {
        guard size > 0 else { throw OutgoingAttachmentSelectionError.emptyFile }
        guard size <= maximumByteCount else { throw OutgoingAttachmentSelectionError.fileTooLarge }
    }

    /// A per-attachment directory, so `removeTemporaryFile` can delete the folder and never a
    /// sibling. The file name is sanitised: a picked file is user data and must never become a
    /// path traversal.
    private nonisolated static func temporaryURL(fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterW4MailAttachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let invalid = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        let pieces = fileName.components(separatedBy: invalid).filter { !$0.isEmpty }
        var safeName = pieces.joined(separator: "-")
        if safeName == "." || safeName == ".." || safeName.isEmpty { safeName = "file" }
        return directory.appendingPathComponent(String(safeName.prefix(240)))
    }
}

// MARK: - Selection errors

enum OutgoingAttachmentSelectionError: LocalizedError, Sendable {
    case emptyFile
    case fileTooLarge
    case maximumCount
    case unsupportedFileType
    case unreadablePhoto

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "That file is empty"
        case .fileTooLarge:
            let limit = ByteCountFormatter.string(
                fromByteCount: MailAttachmentLimits.maximumByteCount,
                countStyle: .file
            )
            return "That file is too large. W4 accepts up to \(limit) per attachment."
        case .maximumCount:
            return "You can attach up to \(MailAttachmentLimits.maximumCount) files"
        case .unsupportedFileType:
            return "Only ordinary files can be attached"
        case .unreadablePhoto:
            return "That photo could not be read"
        }
    }
}

// MARK: - Chips

/// The horizontal strip of staged attachments under the compose body.
struct OutgoingAttachmentList: View {

    let attachments: [OutgoingMessageAttachment]
    let isEditable: Bool
    let onRemove: (UUID) -> Void

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        HStack(spacing: 8) {
                            Image(systemName: attachment.mimeType.hasPrefix("image/") ? "photo" : "doc")
                                .foregroundStyle(Color.accentColor)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(attachment.displayName)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(attachment.formattedSize)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                onRemove(attachment.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .disabled(!isEditable)
                            .accessibilityLabel("Remove attachment \(attachment.displayName)")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }
}
