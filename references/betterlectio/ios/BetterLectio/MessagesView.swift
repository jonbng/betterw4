//
//  MessagesView.swift
//  BetterLectio
//

import Combine
import SwiftUI

struct MessagesView: View {
    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @Binding var path: NavigationPath
    @StateObject private var viewModel = MessagesViewModel()
    @State private var showComposeSheet = false
    /// Holds the sent thread to navigate to once the compose sheet fully dismisses.
    @State private var pendingSentThread: MessageThread?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.threads.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.threads.isEmpty {
                errorView(error)
            } else {
                threadList
            }
        }
        .navigationTitle("Beskeder")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchQuery, prompt: "Søg i beskeder")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(viewModel.availableFolders) { folder in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectedFolder = folder
                            }
                        } label: {
                            HStack {
                                Text(folder.displayName)
                                if viewModel.selectedFolder.id == folder.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.selectedFolder.displayName)
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showComposeSheet = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .task(id: viewModel.selectedFolder.id) {
            await viewModel.loadMessages(for: student)
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterLectioCachesDidClear)) { _ in
            Task {
                await viewModel.loadMessages(for: student)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .profilePictureDidChange)) { _ in
            viewModel.refreshAvatarProfiles(for: student)
        }
        .refreshable {
            await viewModel.refresh(for: student)
        }
        .navigationDestination(for: MessageThread.self) { thread in
            MessageThreadView(
                thread: thread,
                student: student,
                folder: viewModel.selectedFolder,
                authViewModel: authViewModel
            )
        }
        .sheet(isPresented: $showComposeSheet, onDismiss: {
            if let thread = pendingSentThread {
                pendingSentThread = nil
                path.append(thread)
            }
        }) {
            ComposeMessageView(
                student: student,
                authViewModel: authViewModel,
                onMessageSent: { threadId, title in
                    pendingSentThread = MessageThread(
                        id: threadId,
                        title: title,
                        senderName: student.name ?? "Mig",
                        firstSenderName: student.name ?? "Mig",
                        recipients: "",
                        date: "",
                        isRead: true,
                        isFlagged: false,
                        hasAttachment: false,
                        senderType: .student
                    )
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Indlæser beskeder...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Prøv igen") {
                Task { await viewModel.refresh(for: student) }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Thread List

    private var threadList: some View {
        List {
            ForEach(viewModel.visibleThreads) { thread in
                Button {
                    viewModel.selectThread(thread)
                    path.append(thread)
                    Task {
                        await viewModel.markAsRead(threadId: thread.id, for: student)
                    }
                } label: {
                    ThreadRow(
                        thread: thread,
                        avatarURL: viewModel.avatarURLs[thread.senderName] ?? nil
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color(UIColor.systemBackground))
                .alignmentGuide(.listRowSeparatorLeading) { _ in 76 }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        let id = thread.id
                        print("🗑️ [MessageDelete] swipe delete tapped threadId=\(id)")
                        Task { await viewModel.deleteMessage(threadId: id, for: student) }
                    } label: {
                        Label("Slet", systemImage: "trash")
                    }
                    Button {
                        Task { await viewModel.toggleFlag(threadId: thread.id, for: student) }
                    } label: {
                        Label(thread.isFlagged ? "Fjern flag" : "Flag",
                              systemImage: thread.isFlagged ? "flag.slash" : "flag")
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        Task { await viewModel.toggleReadStatus(threadId: thread.id, for: student) }
                    } label: {
                        Label(thread.isRead ? "Ulæst" : "Læst",
                              systemImage: thread.isRead ? "envelope.badge" : "envelope.open")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .background(Color(UIColor.systemBackground))
        .overlay {
            if viewModel.visibleThreads.isEmpty && !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search(text: viewModel.searchQuery)
            }
        }
    }
}

// MARK: - Thread Row

struct ThreadRow: View {
    let thread: MessageThread
    let avatarURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            avatarView

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(thread.senderName)
                        .font(.system(size: 16, weight: thread.isRead ? .regular : .semibold))
                        .foregroundColor(thread.isRead ? .secondary : .primary)
                        .lineLimit(1)

                    Spacer()

                    Text(thread.date)
                        .font(.system(size: 13))
                        .foregroundColor(thread.isRead ? .secondary : .blue)
                }

                HStack(spacing: 4) {
                    Text(thread.title)
                        .font(.system(size: 15, weight: thread.isRead ? .regular : .semibold))
                        .foregroundColor(thread.isRead ? .secondary : .primary)
                        .lineLimit(1)

                    if thread.hasAttachment {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                Text(thread.recipients)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - Avatar View

    private var avatarView: some View {
        ProfileAvatarView(
            url: avatarURL,
            name: thread.senderName,
            size: 48
        )
        .overlay(alignment: .bottomTrailing) {
            if !thread.isRead {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color(UIColor.systemBackground), lineWidth: 2)
                    )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MessagesView(
            student: Student(studentId: "123", gymId: 94, name: "Test Student"),
            authViewModel: AuthenticationViewModel(),
            path: .constant(NavigationPath())
        )
    }
}
