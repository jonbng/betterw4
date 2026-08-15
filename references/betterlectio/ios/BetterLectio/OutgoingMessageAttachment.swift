import Foundation
import Photos
import SwiftUI
import UniformTypeIdentifiers

enum OutgoingAttachmentUploadState: Equatable, Sendable {
    case pending
    case uploading
    case attached
    case failed(String)
}

struct OutgoingMessageAttachment: Identifiable, Equatable, Sendable {
    static let maximumCount = 10
    static let maximumByteCount: Int64 = 25 * 1_024 * 1_024

    let id: UUID
    let displayName: String
    let mimeType: String
    let size: Int64
    let localURL: URL
    let selectionKey: String
    var uploadState: OutgoingAttachmentUploadState

    init(
        id: UUID = UUID(),
        displayName: String,
        mimeType: String,
        size: Int64,
        localURL: URL,
        selectionKey: String? = nil,
        uploadState: OutgoingAttachmentUploadState = .pending
    ) {
        self.id = id
        self.displayName = displayName
        self.mimeType = mimeType
        self.size = size
        self.localURL = localURL
        self.selectionKey = selectionKey ?? localURL.standardizedFileURL.path
        self.uploadState = uploadState
    }

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

    nonisolated static func originalPhotoFileName(assetIdentifier: String?, fallback: String) -> String {
        guard let assetIdentifier else { return fallback }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
        guard let asset = assets.firstObject,
              let resource = PHAssetResource.assetResources(for: asset).first,
              !resource.originalFilename.isEmpty else { return fallback }
        return resource.originalFilename
    }

    nonisolated static func purgeStaleTemporaryFiles(olderThan age: TimeInterval = 24 * 60 * 60) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterLectioMessageAttachments", isDirectory: true)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-age)
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

    private nonisolated static func validate(size: Int64) throws {
        guard size > 0 else { throw OutgoingAttachmentSelectionError.emptyFile }
        guard size <= maximumByteCount else { throw OutgoingAttachmentSelectionError.fileTooLarge }
    }

    private nonisolated static func temporaryURL(fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterLectioMessageAttachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let invalid = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        let pieces = fileName.components(separatedBy: invalid).filter { !$0.isEmpty }
        var safeName = pieces.joined(separator: "-")
        if safeName == "." || safeName == ".." || safeName.isEmpty { safeName = "fil" }
        return directory.appendingPathComponent(String(safeName.prefix(240)))
    }
}

enum OutgoingAttachmentSelectionError: LocalizedError, Sendable {
    case emptyFile
    case fileTooLarge
    case maximumCount
    case unsupportedFileType
    case unreadablePhoto

    var errorDescription: String? {
        switch self {
        case .emptyFile: "Filen er tom"
        case .fileTooLarge: "Filen er for stor (maks. 25 MB)"
        case .maximumCount: "Du kan højst vedhæfte 10 filer"
        case .unsupportedFileType: "Kun almindelige filer kan vedhæftes"
        case .unreadablePhoto: "Billedet kunne ikke læses"
        }
    }
}

struct OutgoingAttachmentList: View {
    let attachments: [OutgoingMessageAttachment]
    let isSending: Bool
    let onRemove: (UUID) -> Void

    var body: some View {
        if !attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { attachment in
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: attachment))
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(attachment.displayName)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(status(for: attachment))
                                    .font(.caption2)
                                    .foregroundStyle(statusColor(for: attachment))
                            }
                            Button {
                                onRemove(attachment.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .disabled(isSending)
                            .accessibilityLabel("Fjern \(attachment.displayName)")
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

    private func icon(for attachment: OutgoingMessageAttachment) -> String {
        if case .uploading = attachment.uploadState { return "arrow.up.circle" }
        if case .failed = attachment.uploadState { return "exclamationmark.circle" }
        return attachment.mimeType.hasPrefix("image/") ? "photo" : "doc"
    }

    private func status(for attachment: OutgoingMessageAttachment) -> String {
        switch attachment.uploadState {
        case .pending: attachment.formattedSize
        case .uploading: "Uploader…"
        case .attached: "Vedhæftet"
        case .failed(let message): message
        }
    }

    private func statusColor(for attachment: OutgoingMessageAttachment) -> Color {
        if case .failed = attachment.uploadState { return .red }
        return .secondary
    }
}
