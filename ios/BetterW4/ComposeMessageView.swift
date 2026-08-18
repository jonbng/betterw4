//
//  ComposeMessageView.swift
//  BetterW4
//
//  Compose a new W4 mail (plan Wave 6 item 6.2, `docs/spec/ui.md` §4.4).
//
//  Read `ComposeMessageViewModel`'s header first: W4's `mailer/send&type=freeform` POST has never
//  been captured, so `MailFeatureFlags.composeEnabled` is off, `MailRepository` exposes no send,
//  and this screen is deliberately honest about that. It shows the draft it would send, enforces
//  W4's real attachment limits (5 × 2 MB), and offers the one thing that does work today: opening
//  the W4 mailer in Safari, where the session cookie already lives.
//
//  What is NOT here, and must not come back: the recipient picker that sourced Lectio's
//  `MessageRecipient` tokens. W4's picker is `mailer/extra&type=freeform`, whose token format is
//  unknown; inventing recipient ids is exactly how a message gets silently delivered to nobody.
//  Chips render whatever tokens a caller passes in (a profile screen can seed one), and there is
//  no in-app way to invent more.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ComposeMessageView: View {

    let student: Student
    /// Recipient tokens W4 itself produced, e.g. seeded from a profile screen. Never invented.
    var initialRecipients: [MailRecipient] = []

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ComposeMessageViewModel()

    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showDiscardConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    unavailableBanner

                    recipientsField
                    Divider()
                    subjectField
                    Divider()
                    bodyField

                    OutgoingAttachmentList(
                        attachments: viewModel.attachments,
                        isEditable: true,
                        onRemove: viewModel.removeAttachment
                    )

                    HStack {
                        attachmentMenu
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    Divider()

                    Toggle("Send me a copy", isOn: $viewModel.sendCopyToMe)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                    if let failure = viewModel.sendFailure {
                        Label(failure, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                }
            }
            .navigationTitle("New message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if viewModel.hasDraft {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        Task { await viewModel.send(for: student) }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canSend)
                }
            }
            .onAppear {
                viewModel.setInitialRecipients(initialRecipients)
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotos,
                maxSelectionCount: max(
                    1,
                    OutgoingMessageAttachment.maximumCount - viewModel.attachments.count
                ),
                matching: .images
            )
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await viewModel.addFiles(urls) }
                case .failure(let error):
                    viewModel.errorMessage = error.localizedDescription
                }
            }
            .onChange(of: selectedPhotos) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await viewModel.addPhotos(items)
                    selectedPhotos = []
                }
            }
            .alert(
                "Could not attach that",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .confirmationDialog(
                "Discard draft?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard draft", role: .destructive) {
                    viewModel.discardDraft()
                    dismiss()
                }
                Button("Keep draft", role: .cancel) { }
            } message: {
                Text("The message and any attachments you picked will be deleted.")
            }
            .interactiveDismissDisabled(viewModel.hasDraft)
        }
    }

    // MARK: - Unavailable banner

    /// The honest state. Shown whenever compose is behind the flag, which is always, today.
    @ViewBuilder
    private var unavailableBanner: some View {
        if !viewModel.isComposeEnabled {
            VStack(alignment: .leading, spacing: 10) {
                Label("Sending is not enabled yet", systemImage: "exclamationmark.bubble")
                    .font(.subheadline.weight(.semibold))

                Text("W4's send form has not been verified against the server, so BetterW4 will not pretend a message went out. You can still write the draft here, then send it on W4.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Link(destination: W4Routes.url(W4Routes.R.mailerInbox)) {
                    Label("Open W4 mailer in Safari", systemImage: "safari")
                        .font(.footnote.weight(.medium))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    // MARK: - Fields

    private var recipientsField: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("To:")
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
                .padding(.top, 8)

            if viewModel.recipients.isEmpty {
                Text("Choose recipients on W4")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.recipients) { recipient in
                        RecipientChip(recipient: recipient) {
                            viewModel.removeRecipient(id: recipient.id)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var subjectField: some View {
        HStack {
            Text("Subject:")
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            TextField("Subject", text: $viewModel.subject)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var bodyField: some View {
        TextField("Message", text: $viewModel.messageBody, axis: .vertical)
            .lineLimit(8...)
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    private var attachmentMenu: some View {
        Menu {
            Button { showPhotoPicker = true } label: {
                Label("Photo", systemImage: "photo.on.rectangle")
            }
            Button { showFileImporter = true } label: {
                Label("File", systemImage: "folder")
            }
        } label: {
            Label("Attach", systemImage: "paperclip")
                .font(.subheadline.weight(.medium))
        }
        .disabled(!viewModel.canAttachMore)
        .accessibilityHint("Up to \(OutgoingMessageAttachment.maximumCount) files, 2 MB each")
    }
}

// MARK: - Recipient chip

struct RecipientChip: View {

    let recipient: MailRecipient
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(recipient.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Remove \(recipient.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.15), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }
}

// MARK: - Flow layout

/// Wraps recipient chips onto as many rows as they need.
struct FlowLayout: Layout {

    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ),
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Preview

#Preview {
    ComposeMessageView(student: .demo)
}
