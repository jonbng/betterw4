//
//  MessageThreadView.swift
//  BetterLectio
//

import Combine
import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct MessageThreadView: View {
    let thread: MessageThread
    let student: Student
    let folder: MessageFolder
    @ObservedObject var authViewModel: AuthenticationViewModel
    @StateObject private var viewModel = MessageThreadViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool
    @State private var showReplyFileImporter = false
    @State private var showReplyPhotoPicker = false
    @State private var selectedReplyPhotos: [PhotosPickerItem] = []
    @State private var sendReplyTask: Task<Void, Never>?

    init(
        thread: MessageThread,
        student: Student,
        folder: MessageFolder = .newest,
        authViewModel: AuthenticationViewModel
    ) {
        self.thread = thread
        self.student = student
        self.folder = folder
        self.authViewModel = authViewModel
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else if let detail = viewModel.threadDetail {
                threadContent(detail)
            } else {
                emptyView
            }
        }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {


            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        // Reply action
                    } label: {
                        Label("Besvar", systemImage: "arrowshape.turn.up.left")
                    }

                    Button {
                        // Flag action
                    } label: {
                        Label("Flag", systemImage: "flag")
                    }

                    Divider()

                    Button(role: .destructive) {
                        // Delete action
                    } label: {
                        Label("Slet", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: thread.id) {
            await viewModel.loadThreadDetail(threadId: thread.id, folder: folder, for: student)
        }
        .onDisappear {
            let replyTask = sendReplyTask
            replyTask?.cancel()
            viewModel.cancelActiveTasks()
            Task {
                await replyTask?.value
                viewModel.discardReplyAttachments()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profilePictureDidChange)) { _ in
            viewModel.refreshAvatarProfiles(gymId: student.gymId, studentId: student.studentId)
        }
        .photosPicker(
            isPresented: $showReplyPhotoPicker,
            selection: $selectedReplyPhotos,
            maxSelectionCount: max(1, OutgoingMessageAttachment.maximumCount - viewModel.replyAttachments.count),
            matching: .images
        )
        .fileImporter(
            isPresented: $showReplyFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await viewModel.addReplyFiles(urls) }
            case .failure(let error): viewModel.replyErrorMessage = error.localizedDescription
            }
        }
        .onChange(of: selectedReplyPhotos) { items in
            guard !items.isEmpty else { return }
            Task {
                await viewModel.addReplyPhotos(items)
                selectedReplyPhotos = []
            }
        }
        .alert("Kunne ikke sende", isPresented: .constant(viewModel.replyErrorMessage != nil)) {
            Button("OK", role: .cancel) { viewModel.replyErrorMessage = nil }
        } message: {
            Text(viewModel.replyErrorMessage ?? "")
        }
        .alert(
            String(localized: "message.reaction_error_title"),
            isPresented: .constant(viewModel.reactionErrorMessage != nil)
        ) {
            Button(String(localized: "common.ok"), role: .cancel) {
                viewModel.reactionErrorMessage = nil
            }
        } message: {
            Text(viewModel.reactionErrorMessage ?? "")
        }
        .alert(
            String(localized: "message.edit_error_title"),
            isPresented: Binding(
                get: { viewModel.editDraft == nil && viewModel.editErrorMessage != nil },
                set: { if !$0 { viewModel.editErrorMessage = nil } }
            )
        ) {
            Button(String(localized: "common.ok"), role: .cancel) {
                viewModel.editErrorMessage = nil
            }
        } message: {
            Text(viewModel.editErrorMessage ?? "")
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.editDraft != nil },
                set: { if !$0 { viewModel.cancelEdit() } }
            )
        ) {
            MessageEditSheet(viewModel: viewModel, student: student)
                .interactiveDismissDisabled(viewModel.isSavingEdit)
        }
        .sensoryFeedback(.success, trigger: viewModel.reactionSuccessToken)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
            
            VStack(spacing: 8) {
                Text("Indlæser")
                    .font(.system(size: 18, weight: .bold))
                Text("Henter dine beskeder...")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange.gradient)
            
            VStack(spacing: 8) {
                Text("Hov, der skete en fejl")
                    .font(.system(size: 18, weight: .bold))
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            
            Button {
                Task { await viewModel.loadThreadDetail(threadId: thread.id, folder: folder, for: student) }
            } label: {
                Text("Prøv igen")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.secondary.gradient)
            
            VStack(spacing: 8) {
                Text("Ingen beskeder")
                    .font(.system(size: 18, weight: .bold))
                Text("Denne samtale er tom.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Thread Content

    private func threadContent(_ detail: MessageThreadDetail) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        // Recipients header
                        recipientsHeader(detail.recipients)
                            .padding(.top, 12)

                        // Messages
                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            LazyVStack(spacing: 16) {
                                ForEach(detail.messages) { message in
                                    MessageBubble(
                                        message: message,
                                        threadTitle: thread.title,
                                        viewModel: viewModel,
                                        isLast: message.id == detail.messages.last?.id,
                                        avatarURL: viewModel.avatarURLs[message.senderName] ?? nil,
                                        isReactionPending: viewModel.reactionPendingTarget == message.locator,
                                        reactionsEnabled: detail.canReply && viewModel.reactionPendingTarget == nil && !viewModel.isSendingReply,
                                        now: timeline.date,
                                        isEditLoading: viewModel.isLoadingEdit,
                                        onReact: { emoji in
                                            Task { await viewModel.react(to: message, with: emoji, for: student) }
                                        },
                                        onEdit: {
                                            Task { await viewModel.beginEdit(message, for: student) }
                                        }
                                    )
                                    .id(message.id)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
                .background(Color(UIColor.systemGroupedBackground))
                .onChange(of: viewModel.sendSuccess) { success in
                    if success {
                        isInputFocused = false
                        let latestMessages = viewModel.threadDetail?.messages ?? detail.messages
                        if let lastId = latestMessages.last?.id {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                        viewModel.sendSuccess = false
                    }
                }
                .onChange(of: isInputFocused) { isFocused in
                    if isFocused {
                        let latestMessages = viewModel.threadDetail?.messages ?? detail.messages
                        if let lastId = latestMessages.last?.id {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    proxy.scrollTo(lastId, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }

            // Inline Input Bar
            if detail.canReply {
                messageInputBar(detail: detail)
            }
        }
    }

    // MARK: - Recipients Header

    private func recipientsHeader(_ recipients: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "person.2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                Text("Til")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .kerning(0.5)
                
                Spacer()
            }
            .padding(.horizontal, 12)

            Text(recipients)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
        }
        .padding(.horizontal, 16)
    }

    private func messageInputBar(detail: MessageThreadDetail) -> some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)

            OutgoingAttachmentList(
                attachments: viewModel.replyAttachments,
                isSending: viewModel.isSendingReply,
                onRemove: viewModel.removeReplyAttachment
            )
            
            HStack(alignment: .bottom, spacing: 12) {
                Menu {
                    Button { showReplyPhotoPicker = true } label: {
                        Label("Billeder", systemImage: "photo.on.rectangle")
                    }
                    Button { showReplyFileImporter = true } label: {
                        Label("Filer", systemImage: "folder")
                    }
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Vedhæft")
                .accessibilityHint("Vælg billeder eller filer")
                .disabled(
                    viewModel.isSendingReply ||
                    viewModel.replyAttachments.count >= OutgoingMessageAttachment.maximumCount
                )

                // Input field
                TextField("Skriv et svar...", text: $viewModel.replyText, axis: .vertical)
                    .focused($isInputFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(UIColor.secondarySystemBackground))
                    )
                    .font(.system(size: 16))
                    .lineLimit(1...5)

                // Send button
                Button {
                    if viewModel.isSendingReply {
                        sendReplyTask?.cancel()
                    } else {
                        sendReplyTask = Task {
                            _ = await viewModel.sendReply(to: detail.threadId, for: student)
                            sendReplyTask = nil
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(viewModel.isSendingReply ? Color.red : (viewModel.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.2) : Color.blue))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: viewModel.isSendingReply ? "xmark" : "arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .disabled(
                    viewModel.reactionPendingTarget != nil ||
                    (viewModel.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSendingReply)
                )
                .accessibilityLabel(viewModel.isSendingReply ? "Stop afsendelse" : "Send svar")
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

}

// Utility extension for conditional modifiers
extension View {
    @ViewBuilder
    func ifIOS18<Content: View>(_ transform: (Self) -> Content) -> some View {
        if #available(iOS 18.0, *) {
            transform(self)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func ifIOS17<Content: View>(_ transform: (Self) -> Content) -> some View {
        if #available(iOS 17.0, *) {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message
    let threadTitle: String
    @ObservedObject var viewModel: MessageThreadViewModel
    let isLast: Bool
    let avatarURL: URL?
    let isReactionPending: Bool
    let reactionsEnabled: Bool
    let now: Date
    let isEditLoading: Bool
    let onReact: (MessageReactionEmoji) -> Void
    let onEdit: () -> Void
    @State private var isExpanded = true
    @State private var isReactionPickerPresented = false
    @State private var selectedReactionGroup: MessageReactionGroup?

    private var isTitleRedundant: Bool {
        !message.title.isEmpty && (
            message.title == threadTitle ||
            message.title == "Re: " + threadTitle ||
            message.title == "Re:" + threadTitle
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sender header
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        // Avatar
                        ProfileAvatarView(
                            url: avatarURL,
                            name: message.senderName,
                            size: 36
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.senderName)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.primary)

                            Text(message.date)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)

                            if let editedAt = message.editedAt {
                                Text(editedLabel(for: editedAt))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if !message.editPostbackTarget.isEmpty {
                    Menu {
                        Button(action: onEdit) {
                            Label(String(localized: "message.edit_action"), systemImage: "pencil")
                        }
                        .disabled(isEditLoading)
                    } label: {
                        if isEditLoading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 32, height: 32)
                        } else {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.primary.opacity(0.055)))
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isEditLoading || viewModel.isSavingEdit)
                    .accessibilityLabel(String(localized: "message.actions"))
                }

                if message.locator != nil {
                    Button {
                        isReactionPickerPresented = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.primary.opacity(0.055))
                                .frame(width: 32, height: 32)
                            if isReactionPending {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "face.smiling.inverse")
                                    .font(.system(size: 15, weight: .semibold))
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .background(Circle().fill(Color(UIColor.secondarySystemGroupedBackground)))
                                    .offset(x: 10, y: 10)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!reactionsEnabled)
                    .accessibilityLabel(String(localized: "message.add_reaction"))
                    .popover(
                        isPresented: $isReactionPickerPresented,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .bottom
                    ) {
                        reactionPicker
                            .presentationCompactAdaptation(.popover)
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    if !message.title.isEmpty && !isTitleRedundant {
                        Text(message.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                            .padding(.top, -4)
                    }

                    Text(viewModel.formattedMessages[message.id] ?? AttributedString("..."))
                        .font(.system(size: 16, weight: .regular))
                        .lineSpacing(4)
                        .foregroundColor(.primary.opacity(0.9))
                        .tint(.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .onLongPressGesture(minimumDuration: 0.45) {
                            guard reactionsEnabled, message.locator != nil else { return }
                            isReactionPickerPresented = true
                        }

                    // Attachments
                    if !message.attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(message.attachments) { attachment in
                                if attachment.isImage {
                                    AuthenticatedImageView(
                                        relativePath: attachment.url,
                                        viewModel: viewModel
                                    )
                                } else {
                                    AttachmentRow(attachment: attachment)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }

                    if !message.reactions.isEmpty {
                        ReactionFlowLayout(spacing: 8) {
                            ForEach(message.reactions) { group in
                                reactionChip(group)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
        )
        .sheet(item: $selectedReactionGroup) { group in
            ReactionParticipantsSheet(group: group)
                .presentationDetents([.medium])
        }
    }

    private func editedLabel(for editedAt: Date) -> String {
        switch MessageEditedTimeFormatter.label(for: editedAt, now: now) {
        case .justNow:
            return String(localized: "message.edited_just_now")
        case .value(let value):
            return String(format: String(localized: "message.edited_at"), value)
        }
    }

    private var reactionPicker: some View {
        HStack(spacing: 5) {
            ForEach(MessageReactionEmoji.allCases, id: \.self) { emoji in
                Button {
                    isReactionPickerPresented = false
                    onReact(emoji)
                } label: {
                    Text(emoji.rawValue)
                        .font(.system(size: 27))
                        .frame(width: 40, height: 42)
                        .background(
                            Circle().fill(
                                message.ownReaction == emoji
                                    ? Color.accentColor.opacity(0.16)
                                    : Color.clear
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    String(format: String(localized: "message.react_with"), emoji.rawValue)
                )
            }
        }
        .padding(10)
    }

    private func reactionChip(_ group: MessageReactionGroup) -> some View {
        HStack(spacing: 5) {
            Text(group.emoji.rawValue)
            Text("\(group.reactors.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(group.emoji == message.ownReaction ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.055))
        )
        .overlay(
            Capsule()
                .stroke(group.emoji == message.ownReaction ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .contentShape(Capsule())
        .opacity(reactionsEnabled ? 1 : 0.65)
        .onTapGesture {
            guard reactionsEnabled else { return }
            onReact(group.emoji)
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            selectedReactionGroup = group
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            String(format: String(localized: "message.reacted_with"), group.emoji.rawValue, group.reactors.count)
        )
        .accessibilityAction {
            guard reactionsEnabled else { return }
            onReact(group.emoji)
        }
    }
}

private struct MessageEditSheet: View {
    @ObservedObject var viewModel: MessageThreadViewModel
    let student: Student
    @Environment(\.dismiss) private var dismiss

    private let titleLimit = 100
    private let bodyLimit = 100_000

    private var bodyLength: Int {
        viewModel.editBody.count + (viewModel.editDraft?.signatureSuffix.count ?? 0)
    }

    private var isChanged: Bool {
        guard let draft = viewModel.editDraft else { return false }
        return viewModel.editTitle != draft.title || viewModel.editBody != draft.body
    }

    private var canSave: Bool {
        isChanged && !viewModel.isSavingEdit && viewModel.editTitle.count <= titleLimit && bodyLength <= bodyLimit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "message.edit_subject")) {
                    TextField(String(localized: "message.edit_subject_placeholder"), text: $viewModel.editTitle)
                        .disabled(viewModel.isSavingEdit)
                    Text("\(viewModel.editTitle.count)/\(titleLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(viewModel.editTitle.count > titleLimit ? Color.red : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Section(String(localized: "message.edit_body")) {
                    BBCodeRichEditor(text: $viewModel.editBody, isEnabled: !viewModel.isSavingEdit)
                    Text("\(bodyLength)/\(bodyLimit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(bodyLength > bodyLimit ? Color.red : Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let draft = viewModel.editDraft, !draft.signatureSuffix.isEmpty {
                    Section {
                        Label(String(localized: "message.edit_signature_preserved"), systemImage: "checkmark.seal")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = viewModel.editErrorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(String(localized: "message.edit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        viewModel.cancelEdit()
                        dismiss()
                    }
                    .disabled(viewModel.isSavingEdit)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await viewModel.saveEdit(for: student) }
                    } label: {
                        if viewModel.isSavingEdit {
                            ProgressView()
                        } else {
                            Text(String(localized: "common.save"))
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

private struct ReactionParticipantsSheet: View {
    let group: MessageReactionGroup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(group.reactors, id: \.key) { reactor in
                HStack(spacing: 12) {
                    Text(group.emoji.rawValue)
                    Text(reactor.isOwn ? String(localized: "message.reaction_you") : reactor.name)
                }
            }
            .navigationTitle(group.emoji.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.close")) { dismiss() }
                }
            }
        }
    }
}

private struct ReactionFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let availableWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (CGSize(width: min(usedWidth, availableWidth), height: y + rowHeight), points)
    }
}

// MARK: - Attachment Row

struct AttachmentRow: View {
    let attachment: MessageAttachment

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: "doc.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - MessageAttachment helpers

extension MessageAttachment {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp"]

    var isImage: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return Self.imageExtensions.contains(ext)
    }
}

// MARK: - Authenticated Image View

@MainActor
private class ImageLoader: ObservableObject {
    enum State { case idle, loading, loaded(UIImage), failed }

    @Published var state: State = .idle
    private var loadTask: Task<Void, Never>?

    func load(relativePath: String, viewModel: MessageThreadViewModel) {
        guard case .idle = state else { return }
        state = .loading
        loadTask = Task { [weak self] in
            guard let self else { return }
            if let image = await viewModel.fetchImage(relativePath: relativePath) {
                guard !Task.isCancelled else { return }
                state = .loaded(image)
            } else {
                guard !Task.isCancelled else { return }
                state = .failed
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        if case .loading = state { state = .idle }
    }
}

// MARK: - QuickLook presenter

private struct QuickLookPreview: UIViewControllerRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator { Coordinator(fileURL: fileURL) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let vc = QLPreviewController()
        vc.dataSource = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let fileURL: URL

        init(fileURL: URL) { self.fileURL = fileURL }

        deinit { try? FileManager.default.removeItem(at: fileURL) }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            fileURL as NSURL
        }
    }
}

private struct MessageImagePreviewFile: Identifiable {
    let id = UUID()
    let url: URL

    static func create(from image: UIImage) async -> MessageImagePreviewFile? {
        await Task.detached(priority: .userInitiated) {
            guard let data = image.jpegData(compressionQuality: 0.95) else { return nil }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".jpg")
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                return MessageImagePreviewFile(url: url)
            } catch {
                return nil
            }
        }.value
    }
}

// MARK: - Authenticated Image View

struct AuthenticatedImageView: View {
    let relativePath: String
    let viewModel: MessageThreadViewModel
    @StateObject private var loader = ImageLoader()
    @State private var previewFile: MessageImagePreviewFile?

    var body: some View {
        Group {
            switch loader.state {
            case .idle, .loading:
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(height: 180)
                    .overlay(ProgressView())
            case .loaded(let image):
                Button {
                    Task { previewFile = await MessageImagePreviewFile.create(from: image) }
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .fullScreenCover(item: $previewFile) { file in
                    QuickLookPreview(fileURL: file.url)
                        .ignoresSafeArea()
                }
            case .failed:
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(height: 80)
                    .overlay(
                        Label("Kunne ikke indlæse billede", systemImage: "photo.badge.exclamationmark")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            loader.load(relativePath: relativePath, viewModel: viewModel)
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

// MARK: - Helper Structures

struct ScrollBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

struct FloatingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85, blendDuration: 0), value: configuration.isPressed)
    }
}

// MARK: - Previews

private enum MessageThreadPreviewData {
    static let thread = MessageThread(
        id: "123",
        title: "Test besked",
        senderName: "John Doe",
        firstSenderName: "John Doe",
        recipients: "Alle elever",
        date: "12:30",
        isRead: false,
        isFlagged: false,
        hasAttachment: true,
        senderType: .student
    )
    static let student = Student(studentId: "123", gymId: 94, name: "Test")
}

#Preview("MessageThreadView") {
    NavigationStack {
        MessageThreadView(
            thread: MessageThreadPreviewData.thread,
            student: MessageThreadPreviewData.student,
            authViewModel: AuthenticationViewModel()
        )
    }
}

#Preview("MessageThreadView (dark)") {
    NavigationStack {
        MessageThreadView(
            thread: MessageThreadPreviewData.thread,
            student: MessageThreadPreviewData.student,
            authViewModel: AuthenticationViewModel()
        )
    }
    .preferredColorScheme(.dark)
}
