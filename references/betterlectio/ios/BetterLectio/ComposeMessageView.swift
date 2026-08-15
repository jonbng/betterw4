//
//  ComposeMessageView.swift
//  BetterLectio
//

import Combine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ComposeMessageView: View {
    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    var initialRecipients: [MessageRecipient] = []
    /// Called with the new thread ID when the message is successfully sent.
    var onMessageSent: ((_ threadId: String, _ title: String) -> Void)?
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = ComposeMessageViewModel()
    @State private var showRecipientPicker = false
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var sendTask: Task<Void, Never>?
    @State private var showDiscardConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Recipients field
                recipientsField

                Divider()

                // Subject field
                HStack {
                    Text("Emne:")
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)

                    TextField("Emne", text: $viewModel.subject)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Message body
                TextEditor(text: $viewModel.messageBody)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                OutgoingAttachmentList(
                    attachments: viewModel.attachments,
                    isSending: viewModel.isSending,
                    onRemove: viewModel.removeAttachment
                )

                HStack {
                    attachmentMenu
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity)
            .navigationTitle("Ny besked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(viewModel.isSending ? "Stop" : "Annuller") {
                        if viewModel.isSending {
                            sendTask?.cancel()
                        } else if viewModel.hasDraft {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        sendTask = Task {
                            await sendMessage()
                            sendTask = nil
                        }
                    }
                    .disabled(!viewModel.canSend || viewModel.isSending)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showRecipientPicker) {
                RecipientPickerView(
                    student: student,
                    authViewModel: authViewModel,
                    selectedRecipients: $viewModel.recipients
                )
            }
            .onAppear {
                if viewModel.recipients.isEmpty && !initialRecipients.isEmpty {
                    viewModel.recipients = initialRecipients
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotos,
                maxSelectionCount: max(1, OutgoingMessageAttachment.maximumCount - viewModel.attachments.count),
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
                case .failure(let error): viewModel.errorMessage = error.localizedDescription
                }
            }
            .onChange(of: selectedPhotos) { items in
                guard !items.isEmpty else { return }
                Task {
                    await viewModel.addPhotos(items)
                    selectedPhotos = []
                }
            }
            .alert("Fejl", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .confirmationDialog(
                "Kassér kladde?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Kassér kladde", role: .destructive) {
                    viewModel.discardAttachments()
                    dismiss()
                }
                Button("Behold kladde", role: .cancel) { }
            } message: {
                Text("Beskeden og valgte vedhæftninger bliver slettet.")
            }
            .overlay {
                if viewModel.isSending {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Sender besked…")
                            .font(.subheadline.weight(.medium))
                    }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Sender besked")
                }
            }
            .interactiveDismissDisabled(viewModel.hasDraft || viewModel.isSending)
        }
    }

    // MARK: - Recipients Field

    private var recipientsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text("Til:")
                    .foregroundColor(.secondary)
                    .frame(width: 70, alignment: .leading)
                    .padding(.top, 8)

                if viewModel.recipients.isEmpty {
                    Button {
                        showRecipientPicker = true
                    } label: {
                        Text("Vælg modtagere...")
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 8)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(viewModel.recipients) { recipient in
                            RecipientChip(recipient: recipient) {
                                viewModel.recipients.removeAll { $0.id == recipient.id }
                            }
                        }

                        Button {
                            showRecipientPicker = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Send Message

    private var attachmentMenu: some View {
        Menu {
            Button { showPhotoPicker = true } label: {
                Label("Billeder", systemImage: "photo.on.rectangle")
            }
            Button { showFileImporter = true } label: {
                Label("Filer", systemImage: "folder")
            }
        } label: {
            Label("Vedhæft", systemImage: "paperclip")
                .font(.subheadline.weight(.medium))
        }
        .disabled(viewModel.isSending || viewModel.attachments.count >= OutgoingMessageAttachment.maximumCount)
        .accessibilityHint("Vælg billeder eller filer")
    }

    private func sendMessage() async {
        let sentTitle = viewModel.subject
        if let threadId = await viewModel.send(for: student) {
            dismiss()
            onMessageSent?(threadId, sentTitle)
        }
    }
}

// MARK: - Recipient Chip

struct RecipientChip: View {
    let recipient: MessageRecipient
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(recipient.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.15))
        .foregroundColor(.blue)
        .cornerRadius(16)
    }
}

// MARK: - Recipient Picker View

struct RecipientPickerView: View {
    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @Binding var selectedRecipients: [MessageRecipient]
    @Environment(\.dismiss) private var dismiss

    @StateObject private var searchViewModel = DirectoryViewModel()

    var displayedEntries: [DirectoryEntity] {
        if searchViewModel.isSearching {
            return searchViewModel
                .searchSections()
                .flatMap(\.entities)
                .filter { $0.canMessage }
        }
        return searchViewModel.classmates(for: student)
    }

    var body: some View {
        NavigationStack {
            Group {
                if searchViewModel.isLoading && searchViewModel.entities.isEmpty {
                    ProgressView("Henter kontakter...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if !searchViewModel.isSearching {
                            Section("Klassekammerater") {
                                recipientRows(for: displayedEntries)
                            }

                            let mine = searchViewModel.myTeachers(for: student)
                            let teachers = mine.isEmpty ? Array(searchViewModel.teachers.prefix(20)) : mine
                            if !teachers.isEmpty {
                                Section(mine.isEmpty ? "Lærere" : "Mine lærere") {
                                    recipientRows(for: teachers)
                                }
                            }

                            let groups = Array(searchViewModel.messageRecipients.filter { $0.kind == .group }.prefix(20))
                            if !groups.isEmpty {
                                Section("Grupper") {
                                    recipientRows(for: groups)
                                }
                            }
                        } else {
                            Section {
                                recipientRows(for: displayedEntries)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .overlay {
                        if searchViewModel.isSearching && displayedEntries.isEmpty {
                            ContentUnavailableView.search(text: searchViewModel.searchQuery)
                        }
                    }
                }
            }
            .navigationTitle("Vælg modtagere")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchViewModel.searchQuery, prompt: "Søg efter elever og lærere...")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuller") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Færdig") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task(id: student.studentId) {
                await searchViewModel.loadDirectory(for: student)
            }
            .onReceive(NotificationCenter.default.publisher(for: .betterLectioCachesDidClear)) { _ in
                Task {
                    await searchViewModel.refreshDirectory(for: student)
                }
            }
        }
    }

    @ViewBuilder
    private func recipientRows(for entries: [DirectoryEntity]) -> some View {
        ForEach(entries) { entry in
            if let recipient = entry.asMessageRecipient() {
                RecipientRow(
                    recipient: recipient,
                    isSelected: selectedRecipients.contains(where: { $0.id == recipient.id })
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleRecipient(recipient)
                }
            }
        }
    }

    private func toggleRecipient(_ recipient: MessageRecipient) {
        if let index = selectedRecipients.firstIndex(where: { $0.id == recipient.id }) {
            selectedRecipients.remove(at: index)
        } else {
            selectedRecipients.append(recipient)
        }
    }
}

// MARK: - Recipient Row

struct RecipientRow: View {
    let recipient: MessageRecipient
    let isSelected: Bool

    var iconName: String {
        switch recipient.type {
        case .student:
            return "person.fill"
        case .teacher:
            return "person.text.rectangle.fill"
        case .group:
            return "person.3.fill"
        case .hold:
            return "person.2.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(recipient.name)
                    .font(.body)
                    .foregroundColor(.primary)

                if let info = recipient.info {
                    Text(info)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
            } else {
                Circle()
                    .stroke(Color.secondary, lineWidth: 1)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: ProposedViewSize(width: bounds.width, height: nil))
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

            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

// MARK: - Preview

#Preview {
    ComposeMessageView(
        student: Student(studentId: "123", gymId: 94, name: "Test Student"),
        authViewModel: AuthenticationViewModel()
    )
}
