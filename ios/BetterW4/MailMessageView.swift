//
//  MailMessageView.swift
//  BetterW4
//
//  One read email (plan Wave 6 item 6.2, `docs/spec/ui.md` §4.3). Replaces Lectio's 1000-line
//  `MessageThreadView`: W4's `mailer/view&id={n}` is a single message with no thread, no reply
//  chain, no reactions and no edit history (plan §1.4 kill list).
//
//  Layout, top to bottom: subject, sender + timestamp, recipients when the page named any, the
//  TinyMCE HTML body through the shared renderer, then attachment rows that open in QuickLook.
//
//  The header is drawn from the list row that was tapped, so the screen has content the instant
//  it pushes and the body fills in underneath — there is no full-screen spinner over a message
//  whose subject we already know.
//

import QuickLook
import SwiftUI

struct MailMessageView: View {

    let message: MailMessage
    let student: Student

    @StateObject private var viewModel = MailMessageViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                bodySection
                if !viewModel.attachments.isEmpty {
                    attachmentsSection
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(displaySubject)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Link(destination: W4Routes.url(W4Routes.R.mailerView, ["id": message.id])) {
                    Image(systemName: "safari")
                }
                .accessibilityLabel("Open on w4.uwcrcn.no")
            }
        }
        .task(id: message.id) {
            await viewModel.load(message: message, student: student)
        }
        .refreshable {
            await viewModel.refresh(message: message, student: student)
        }
        .sheet(item: $viewModel.preview) { preview in
            MailAttachmentPreviewSheet(preview: preview)
                .ignoresSafeArea()
        }
    }

    private var displaySubject: String {
        let fromDetail = viewModel.detail?.subject.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromDetail.isEmpty { return fromDetail }
        return message.subject.isEmpty ? "Message" : message.subject
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(displaySubject)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 12) {
                W4AvatarView.initialsPlaceholder(name: senderName, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(senderName)
                        .font(.subheadline.weight(.medium))
                    if let sent = sentAt {
                        Text(MailRowFormat.full(sent))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            if let recipients = recipientLine {
                Text("To: \(recipients)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var senderName: String {
        if let from = viewModel.detail?.from, !from.isEmpty { return from }
        if let from = message.from, !from.isEmpty { return from }
        return "Unknown sender"
    }

    private var sentAt: Date? {
        viewModel.detail?.sentAt ?? message.receivedAt
    }

    private var recipientLine: String? {
        let recipients = viewModel.detail?.recipients ?? []
        guard !recipients.isEmpty else { return nil }
        return recipients.joined(separator: ", ")
    }

    // MARK: - Body

    @ViewBuilder
    private var bodySection: some View {
        if viewModel.isLoading && viewModel.detail == nil {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading message…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let error = viewModel.errorMessage, viewModel.detail == nil {
            VStack(alignment: .leading, spacing: 10) {
                Label("Could not open this message", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    Task { await viewModel.refresh(message: message, student: student) }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if viewModel.blocks.isEmpty {
            Text("This message has no content.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(viewModel.blocks.enumerated()), id: \.offset) { _, block in
                    MailBodyBlockView(block: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Attachments

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.attachments.count == 1 ? "Attachment" : "Attachments")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(viewModel.attachments) { attachment in
                MailAttachmentRow(
                    attachment: attachment,
                    state: viewModel.state(for: attachment)
                ) {
                    Task { await viewModel.openAttachment(attachment) }
                }
            }
        }
    }
}

// MARK: - Body blocks

/// Draws one `ContentBlock` from the shared HTML renderer.
private struct MailBodyBlockView: View {

    let block: ContentBlock

    var body: some View {
        switch block {
        case .heading(let level, let inlines):
            Text(MessageContentRenderer.attributedString(from: inlines))
                .font(level <= 1 ? .headline : (level == 2 ? .subheadline.weight(.semibold) : .footnote.weight(.semibold)))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let inlines):
            Text(MessageContentRenderer.attributedString(from: inlines))
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .image(let url, let alt):
            MailBodyImage(source: url, alt: alt)

        case .divider:
            Divider()
        }
    }
}

/// An image embedded in a mail body.
///
/// W4 images need the session cookie, so they go through `W4ImageLoader`, which attaches
/// credentials only for `w4.uwcrcn.no` and refuses every other host. An image that cannot be
/// loaded falls back to its alt text rather than to a broken frame.
private struct MailBodyImage: View {

    let source: String
    let alt: String

    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel(alt.isEmpty ? "Image" : alt)
            } else if didFail {
                Label(alt.isEmpty ? "Image could not be loaded" : alt, systemImage: "photo")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(height: 120)
                    .overlay(ProgressView())
            }
        }
        .task(id: source) {
            guard image == nil, let url = MessageContentRenderer.absoluteURL(source) else {
                didFail = image == nil
                return
            }
            let loaded = await W4ImageLoader.shared.loadImage(from: url)
            if let loaded {
                image = loaded
            } else {
                didFail = true
            }
        }
    }
}

// MARK: - Attachment row

struct MailAttachmentRow: View {

    let attachment: MailAttachment
    let state: MailAttachmentDownloadState
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if case .failed(let reason) = state {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if case .downloading = state {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(state == .downloading)
        .accessibilityLabel("Attachment \(attachment.name)")
        .accessibilityHint("Opens a preview")
    }

    private var iconName: String {
        let ext = (attachment.name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "bmp": return "photo"
        case "doc", "docx", "rtf", "odt", "pages": return "doc.text"
        case "xls", "xlsx", "csv", "ods", "numbers": return "tablecells"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle"
        case "zip", "rar", "7z": return "archivebox"
        default: return "doc"
        }
    }
}

// MARK: - QuickLook

/// Presents one already-downloaded file.
///
/// The file lives in the shared `AttachmentCache`, which owns its lifetime — this sheet must
/// never delete it on dismiss, or the next tap re-downloads a file the app already has.
private struct MailAttachmentPreviewSheet: UIViewControllerRepresentable {

    let preview: MailAttachmentPreview

    func makeCoordinator() -> Coordinator { Coordinator(url: preview.url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = preview.url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MailMessageView(
            message: MailMessage(
                id: "demo-mail-1",
                folderID: MailFolder.inbox.id,
                subject: "Welcome to term 1",
                from: "House Leader",
                receivedAt: TimeProvider.now,
                isUnread: true,
                hasAttachment: true
            ),
            student: .demo
        )
    }
}
