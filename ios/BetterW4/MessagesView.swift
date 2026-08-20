//
//  MessagesView.swift
//  BetterW4
//
//  The W4 mailer, reached from More (plan Wave 6 item 6.2, `docs/spec/ui.md` §4.2).
//
//  Two W4 grids — Inbox (`mailer/inbox`) and Sent (`mailer/archive`) — behind a leading folder
//  menu, `.searchable`, pull-to-refresh, and a row per message showing Received / From / Subject.
//  Tapping a row pushes `MailMessageView`.
//
//  Everything here reads `MessagesViewModel`; this file performs no I/O and knows no routes.
//

import SwiftUI

struct MessagesView: View {

    let student: Student

    @StateObject private var viewModel = MessagesViewModel()
    @State private var showCompose = false

    /// The whole surface this screen needs. The pre-Wave-6 version also took an
    /// `AuthenticationViewModel` and a `NavigationPath` binding; neither is needed any more —
    /// session expiry is broadcast by the transport as `.w4SessionExpired`, and rows push through
    /// `NavigationLink(value:)` on whichever `NavigationStack` encloses this screen.
    init(student: Student) {
        self.student = student
    }

    var body: some View {
        content
            .navigationTitle("Mail")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.searchQuery, prompt: "Search mail")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { folderMenu }
                if MailFeatureFlags.visible {
                    ToolbarItem(placement: .topBarTrailing) { composeButton }
                }
            }
            .navigationDestination(for: MailMessage.self) { message in
                MailMessageView(message: message, student: student)
                    // Opening a message is what marks it read, so the row stops shouting the
                    // moment the body is on screen. W4's own value arrives with the next inbox
                    // refresh, which `MailMessageViewModel` schedules.
                    .onAppear { viewModel.markReadLocally(id: message.id) }
            }
            .task(id: viewModel.selectedFolder.id) {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .betterW4CachesDidClear)) { _ in
                Task { await viewModel.refresh() }
            }
            .sheet(isPresented: $showCompose) {
                ComposeMessageView(student: student)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.messages.isEmpty {
            loadingView
        } else if let error = viewModel.errorMessage, viewModel.messages.isEmpty {
            errorView(error)
        } else if viewModel.isUnreadableState {
            unreadableView
        } else if viewModel.messages.isEmpty && !viewModel.isSearching {
            emptyView
        } else {
            messageList
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Loading mail…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Could not reach W4")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No mail",
            systemImage: "tray",
            description: Text("Messages from staff and classmates show up here.")
        )
    }

    /// W4 answered, but with markup this app could not read. Saying "no mail" here would be a
    /// lie: it is the difference between an empty mailbox and a broken parser.
    private var unreadableView: some View {
        ContentUnavailableView {
            Label("Could not read this page", systemImage: "questionmark.square.dashed")
        } description: {
            Text("W4 answered, but its mail page did not look the way this app expects.")
        } actions: {
            Button("Try again") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
        }
    }

    private var messageList: some View {
        List {
            if viewModel.markupWarning {
                noticeRow(
                    "Showing saved mail",
                    detail: "W4's mail page did not look the way this app expects, so these are the last messages we could read.",
                    systemImage: "exclamationmark.triangle"
                )
            } else if viewModel.isShowingCachedCopy, let cachedAt = viewModel.cachedAt {
                noticeRow(
                    "Showing saved mail",
                    detail: "Last updated \(MailRowFormat.updated(cachedAt)).",
                    systemImage: "arrow.down.circle"
                )
            }

            ForEach(viewModel.visibleMessages) { message in
                NavigationLink(value: message) {
                    MailRow(message: message, showsSender: viewModel.selectedFolder.expectsSenderColumn)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if viewModel.hasMorePages {
                morePagesRow
            }
        }
        .listStyle(.plain)
        .overlay {
            if viewModel.visibleMessages.isEmpty && viewModel.isSearching {
                ContentUnavailableView.search(text: viewModel.searchQuery)
            }
        }
    }

    private func noticeRow(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .listRowBackground(Color(uiColor: .secondarySystemBackground))
    }

    /// W4's mailer is paginated and the pager markup has never been captured, so the app renders
    /// page one and says so instead of implying that is the whole mailbox.
    private var morePagesRow: some View {
        Link(destination: W4Routes.url(viewModel.selectedFolder.route)) {
            HStack(spacing: 8) {
                Image(systemName: "safari")
                Text("Older mail is on w4.uwcrcn.no")
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
            }
            .font(.footnote)
        }
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    }

    // MARK: - Toolbar

    private var folderMenu: some View {
        Menu {
            ForEach(viewModel.folders) { folder in
                Button {
                    viewModel.selectedFolder = folder
                } label: {
                    if viewModel.selectedFolder.id == folder.id {
                        Label(folder.displayName, systemImage: "checkmark")
                    } else {
                        Text(folder.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(viewModel.selectedFolder.displayName)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
        }
        .accessibilityLabel("Mailbox")
        .accessibilityValue(viewModel.selectedFolder.displayName)
    }

    private var composeButton: some View {
        Button {
            showCompose = true
        } label: {
            Image(systemName: "square.and.pencil")
        }
        .accessibilityLabel("New message")
    }
}

// MARK: - Row

struct MailRow: View {

    let message: MailMessage
    /// The Sent grid has no From column at all, so the row draws the subject on its own rather
    /// than leaving a blank line where a sender would be.
    var showsSender: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(senderName ?? "Sent")
                        .font(.subheadline.weight(message.isUnread ? .semibold : .regular))
                        .foregroundStyle(senderName == nil ? Color.secondary : Color.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let received = message.receivedAt {
                        Text(MailRowFormat.listStamp(received))
                            .font(.caption)
                            .foregroundStyle(message.isUnread ? Color.accentColor : Color.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Text(message.subject.isEmpty ? "(No subject)" : message.subject)
                        .font(.subheadline.weight(message.isUnread ? .semibold : .regular))
                        .foregroundStyle(message.isUnread ? Color.primary : Color.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if message.hasAttachment {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// `nil` on the Sent grid, which W4 renders with no From column at all. Never a positional
    /// guess, and never the signed-in student's own name invented client-side.
    private var senderName: String? {
        guard showsSender, let from = message.from, !from.isEmpty else { return nil }
        return from
    }

    @ViewBuilder
    private var avatar: some View {
        Group {
            if let senderName {
                W4AvatarView.initialsPlaceholder(name: senderName, size: 38)
            } else {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            }
        }
        .overlay(alignment: .topLeading) {
            if message.isUnread {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 2))
                    .offset(x: -3, y: -3)
            }
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if message.isUnread { parts.append("Unread") }
        if let senderName { parts.append("From \(senderName)") }
        parts.append(message.subject.isEmpty ? "No subject" : message.subject)
        if let received = message.receivedAt { parts.append(MailRowFormat.spoken(received)) }
        if message.hasAttachment { parts.append("Has an attachment") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Formatting

/// Row and header timestamps. W4 is one school in one place, so every stamp is rendered in
/// `Europe/Oslo` (plan D-11) rather than in whatever zone the device is roaming through.
enum MailRowFormat {

    /// "12:04" today, "Yesterday", "14 Aug" this year, "14 Aug 2025" before that.
    static func listStamp(_ date: Date) -> String {
        let calendar = W4Dates.calendar
        let now = TimeProvider.now
        if calendar.isDate(date, inSameDayAs: now) { return time.string(from: date) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return sameYear ? dayMonth.string(from: date) : dayMonthYear.string(from: date)
    }

    /// "14 Aug 2026 at 12:04" — the detail header, where the exact moment matters.
    static func full(_ date: Date) -> String {
        fullStamp.string(from: date)
    }

    /// "12:04" / "14 Aug at 12:04" for the "last updated" notice.
    static func updated(_ date: Date) -> String {
        W4Dates.calendar.isDate(date, inSameDayAs: TimeProvider.now)
            ? time.string(from: date)
            : fullStamp.string(from: date)
    }

    /// Spelled out for VoiceOver, which should not have to read "14 Aug" as an abbreviation.
    static func spoken(_ date: Date) -> String {
        spokenStamp.string(from: date)
    }

    private static let time = formatter("HH:mm")
    private static let dayMonth = formatter("d MMM")
    private static let dayMonthYear = formatter("d MMM yyyy")
    private static let fullStamp = formatter("d MMM yyyy 'at' HH:mm")
    private static let spokenStamp = formatter("d MMMM yyyy 'at' HH:mm")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = W4Dates.zone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = format
        return formatter
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MessagesView(student: .demo)
    }
}
