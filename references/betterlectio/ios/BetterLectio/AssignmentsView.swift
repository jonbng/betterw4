//
//  AssignmentsView.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 23/02/2026.
//

import Combine
import SwiftUI

struct AssignmentsView: View {
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d. MMM"
        formatter.locale = Locale(identifier: "da_DK")
        return formatter
    }()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    private static let oneDecimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }()
    private static let wholeNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @StateObject private var viewModel = AssignmentsViewModel()
    @State private var selectedAssignment: Assignment?
    @State private var hasScrolledToCurrentWeek = false
    @State private var listRevealed = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.assignments.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.assignments.isEmpty {
                errorView(error)
            } else {
                mainContent
            }
        }
        .navigationTitle("Opgaver")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(AssignmentFilter.allCases, id: \.self) { filter in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectedFilter = filter
                            }
                        } label: {
                            HStack {
                                Text(filter.rawValue)
                                if viewModel.selectedFilter == filter {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
        .task(id: student.studentId) {
            await viewModel.loadAssignments(for: student)
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterLectioCachesDidClear)) { _ in
            Task {
                await viewModel.loadAssignments(for: student)
            }
        }
        .sheet(item: $selectedAssignment) { assignment in
            AssignmentDetailSheet(assignment: assignment, student: student, viewModel: viewModel)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Henter opgaver…")
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
                Task { await viewModel.loadAssignments(for: student) }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollViewReader { proxy in
            List {
                // Filter chips
                Section {
                    filterBar
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // Content grouped by week
                groupedContent
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.loadAssignments(for: student)
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                } else if !listRevealed {
                    Color(UIColor.systemGroupedBackground)
                        .ignoresSafeArea()
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    scrollToCurrentWeekIfNeeded(proxy: proxy)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        listRevealed = true
                    }
                }
            }
        }
    }

    private func scrollToCurrentWeekIfNeeded(proxy: ScrollViewProxy) {
        guard !hasScrolledToCurrentWeek, !viewModel.assignmentsGroupedByWeek.isEmpty else { return }
        if scrollToCurrentWeekSection(proxy: proxy) {
            hasScrolledToCurrentWeek = true
        }
    }

    @discardableResult
    private func scrollToCurrentWeekSection(proxy: ScrollViewProxy) -> Bool {
        let targetId = viewModel.currentWeekId
        let hasCurrentWeek = viewModel.assignmentsGroupedByWeek.contains { $0.id == targetId }
        guard hasCurrentWeek else { return false }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(targetId, anchor: .top)
        }
        return true
    }

    @ViewBuilder
    private func weekSectionHeader(for group: AssignmentsViewModel.WeekGroup) -> some View {
        let isCurrentWeek = group.id == viewModel.currentWeekId
        let hoursText = formattedElevTimerSum(group.totalElevTimerHours)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(group.title)
                .fontWeight(.semibold)
                .foregroundStyle(isCurrentWeek ? Color.accentColor : Color.secondary)
            if let hoursText {
                Text(hoursText)
                    .fontWeight(.regular)
                    .foregroundStyle(Color.secondary)
            }
        }
        .font(.subheadline)
        .textCase(nil)
    }

    @ViewBuilder
    private var groupedContent: some View {
        let groups = viewModel.assignmentsGroupedByWeek
        if groups.isEmpty {
            Section {
                Text("Ingen opgaver")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        } else {
            ForEach(groups) { group in
                Section {
                    ForEach(group.assignments) { assignment in
                        assignmentRow(assignment)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedAssignment = assignment }
                    }
                } header: {
                    weekSectionHeader(for: group)
                }
                .id(group.id)
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AssignmentFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func filterChip(_ filter: AssignmentFilter) -> some View {
        let isSelected = viewModel.selectedFilter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedFilter = filter
            }
        } label: {
            Text(filter.rawValue)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color(UIColor.tertiarySystemFill))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Assignment Row

    private func assignmentRow(_ assignment: Assignment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: title + hold + status
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.title)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(alignment: .center, spacing: 8) {
                    Text(assignment.hold)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    assignment.status.badge
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                deadlineOneLine(for: assignment)

                if let elevText = formattedElevTimerForRow(assignment) {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .accessibilityHidden(true)
                        Text(elevText)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Elev \(elevText)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Date label + clock on one line (day inherits deadline emphasis; clock matches Lectio HH:mm styling).
    private func deadlineOneLine(for assignment: Assignment) -> Text {
        let raw = assignment.deadline
        let dayLabel = relativeDay(for: assignment.deadlineDate, raw: raw)
        let clock = timeString(for: assignment.deadlineDate, raw: raw)

        guard assignment.deadlineDate != nil else {
            return Text(raw)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
        }

        let dayColor = deadlineColor(for: assignment.deadlineDate)
        return (Text(dayLabel).fontWeight(.semibold).foregroundStyle(dayColor)
            + Text(" \(clock)")
            .foregroundStyle(.secondary))
            .font(.subheadline)
    }

    // MARK: - Deadline Formatting

    private func relativeDay(for date: Date?, raw: String) -> String {
        guard let date else { return raw }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTarget = calendar.startOfDay(for: date)

        let dayDiff = calendar.dateComponents([.day], from: startOfToday, to: startOfTarget).day ?? 0

        if dayDiff < 0 {
            return Self.shortDateFormatter.string(from: date)
        } else if dayDiff == 0 {
            return "I dag"
        } else if dayDiff == 1 {
            return "I morgen"
        } else if dayDiff <= 3 {
            return "Om \(dayDiff) dage"
        } else {
            return Self.shortDateFormatter.string(from: date)
        }
    }

    /// Per-week totals use one decimal like `toStringAsFixed(1)` in lectio_plus_plus `OpgaveList`.
    private func formattedElevTimerSum(_ hours: Double) -> String? {
        guard hours > 0 else { return nil }
        guard let num = Self.oneDecimalFormatter.string(from: NSNumber(value: hours)) else { return " – \(String(format: "%.1f", hours)) timer" }
        return " – \(num) timer"
    }

    /// Compact elev-timer label for rows, e.g. "2 timer" or "2,5 timer" (no "Elev:", no Lectio comma padding).
    private func formattedElevTimerForRow(_ assignment: Assignment) -> String? {
        let raw = assignment.studentTime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != "-" else { return nil }
        let hours = assignment.elevTimerHours
        guard hours > 0 else { return nil }
        let isWhole = abs(hours.truncatingRemainder(dividingBy: 1)) < 0.001
        let formatter = isWhole ? Self.wholeNumberFormatter : Self.oneDecimalFormatter
        guard let num = formatter.string(from: NSNumber(value: hours)) else {
            if isWhole { return "\(Int(hours.rounded())) timer" }
            let frac = String(format: "%.1f", hours).replacingOccurrences(of: ".", with: ",")
            return "\(frac) timer"
        }
        return "\(num) timer"
    }

    private func timeString(for date: Date?, raw: String) -> String {
        guard let date else {
            if let spaceIdx = raw.lastIndex(of: " ") {
                return String(raw[raw.index(after: spaceIdx)...])
            }
            return raw
        }

        return Self.timeFormatter.string(from: date)
    }

    private func deadlineColor(for date: Date?) -> Color {
        guard let date else { return .secondary }

        let now = Date()
        if date < now {
            return .secondary
        }

        let hoursUntil = date.timeIntervalSince(now) / 3600
        if hoursUntil < 24 {
            return .red
        } else if hoursUntil < 72 {
            return .orange
        } else {
            return .primary
        }
    }

}

// MARK: - Assignment Status Presentation

extension AssignmentStatus {
    var color: Color {
        switch self {
        case .submitted: return .green
        case .waiting: return .orange
        case .notSubmitted: return .red
        case .missing: return .red
        }
    }

    var badge: some View {
        Text(displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - Assignment Detail Sheet

struct AssignmentDetailSheet: View {
    let assignment: Assignment
    let student: Student
    @ObservedObject var viewModel: AssignmentsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection

                    Divider()

                    // Detail content
                    if viewModel.isLoadingDetail {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 32)
                            Spacer()
                        }
                    } else if let detail = viewModel.assignmentDetail {
                        detailContent(detail)
                    } else if let error = viewModel.detailError {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 15, weight: .heavy))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.loadAssignmentDetail(for: assignment, student: student)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(assignment.title)
                .font(.title3)
                .fontWeight(.bold)

            HStack(spacing: 8) {
                Text(assignment.hold)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                assignment.status.badge
            }
        }
    }

    // MARK: - Detail Content

    private func detailContent(_ detail: AssignmentDetail) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Info rows
            infoSection(detail)

            // Grade (if available)
            if let grade = detail.grade, !grade.isEmpty {
                gradeSection(grade: grade, gradeNote: detail.gradeNote)
            }

            // Assignment note
            if let note = detail.assignmentNote, !note.isEmpty {
                noteSection(title: "Opgavenote", text: note)
            }

            // Student note
            if let note = detail.studentNote, !note.isEmpty {
                noteSection(title: "Elevnote", text: note)
            }

            // Description files
            if !detail.descriptionFiles.isEmpty {
                filesSection(title: "Opgavebeskrivelse", files: detail.descriptionFiles)
            }

            // Submissions
            if !detail.submissions.isEmpty {
                submissionsSection(detail.submissions)
            }
        }
    }

    // MARK: - Info Section

    private func infoSection(_ detail: AssignmentDetail) -> some View {
        VStack(spacing: 10) {
            infoRow(icon: "person", text: detail.teacher)
            infoRow(icon: "calendar", text: detail.deadline)
            infoRow(icon: "clock", text: detail.studentTime)
            if let scale = detail.gradeScale {
                infoRow(icon: "graduationcap", text: scale)
            }
            if let status = detail.status {
                infoRow(icon: "checkmark.circle", text: status)
            }
            if let awaiting = detail.awaiting {
                infoRow(icon: "hourglass", text: "Afventer: \(awaiting)")
            }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)

            Spacer()
        }
    }

    // MARK: - Grade Section

    private func gradeSection(grade: String, gradeNote: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Karakter", systemImage: "star.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text(grade)
                    .font(.title2)
                    .fontWeight(.bold)

                if let note = gradeNote {
                    Text(note)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Note Section

    private func noteSection(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "note.text")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(text)
                .font(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Files Section

    private func filesSection(title: String, files: [AssignmentFile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "doc")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(files) { file in
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .frame(width: 16)

                    Text(file.name)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .lineLimit(2)

                    Spacer()
                }
                .padding(10)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onTapGesture {
                    openURL(file.url)
                }
            }
        }
    }

    // MARK: - Submissions Section

    private func submissionsSection(_ submissions: [AssignmentSubmission]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Opgaveindlæg", systemImage: "bubble.left.and.text.bubble.right")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(submissions) { submission in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(submission.user)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(submission.timestamp)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let comment = submission.comment {
                        Text(comment)
                            .font(.subheadline)
                            .foregroundColor(.primary.opacity(0.85))
                    }

                    if let doc = submission.document {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text(doc.name)
                                .font(.caption)
                                .foregroundColor(.blue)
                                .lineLimit(1)
                        }
                        .onTapGesture {
                            openURL(doc.url)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: - Helpers

    private func openURL(_ path: String) {
        let urlString: String
        if path.hasPrefix("http") {
            urlString = path
        } else {
            urlString = "https://www.lectio.dk\(path)"
        }
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}
