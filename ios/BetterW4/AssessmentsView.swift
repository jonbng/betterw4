//
//  AssessmentsView.swift
//  BetterW4
//
//  The Assessments screen: W4's `index.php?r=academics/deadlines` month calendar
//  (`ui.md` §4.5, plan Wave 6/7). W4 models homework and assignments as one list of deadlines, so
//  this single screen replaces the two separate homework/assignment screens the app used to carry.
//  It lives under More; Absence took the tab because students open it more often.
//
//  Salvaged from the screen it replaces: the day-grouped scroll list, the
//  circular done affordance with the dim + strikethrough treatment, the subject-tinted icon tile
//  and the expand/collapse detail row. Dropped: the legacy data model, the local done-flag store
//  (W4 owns done-state) and the 200-line custom swipe gesture, whose job is done here by a tap
//  target and a context menu that VoiceOver can actually reach.
//
//  Everything on this screen comes from `AssessmentsViewModel`, which comes from
//  `AssessmentRepository`. No parser, no HTTP client, no store is referenced here.
//
//  Writes are gated: `viewModel.writesAvailable` is false whenever the OQ-3 feature flag is off or
//  W4 published no endpoint for this month, and the status then renders as a read-only chip rather
//  than a button that would silently do nothing.
//

import Combine
import SwiftUI

struct AssessmentsView: View {

    let student: Student

    @StateObject private var viewModel = AssessmentsViewModel()
    @State private var detailItem: Assessment?

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                content
            }
        }
        .navigationTitle("Assessments")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isRefreshing && !viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if !viewModel.isShowingCurrentMonth {
                    Button("Today") {
                        Task { await viewModel.showCurrentMonth(for: student) }
                    }
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
            }
        }
        .task(id: student.studentId) {
            await viewModel.load(for: student)
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterW4CachesDidClear)) { _ in
            Task { await viewModel.load(for: student) }
        }
        .sheet(item: $detailItem) { item in
            AssessmentDetailSheet(item: item, viewModel: viewModel)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                monthButton(systemImage: "chevron.left", label: "Previous month", delta: -1)

                Text(viewModel.monthTitle)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())

                monthButton(systemImage: "chevron.right", label: "Next month", delta: 1)
            }

            Picker("View", selection: $viewModel.displayMode) {
                ForEach(AssessmentDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let notice = viewModel.notice {
                AssessmentNoticeBanner(message: notice) {
                    viewModel.dismissNotice()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func monthButton(systemImage: String, label: String, delta: Int) -> some View {
        Button {
            Task { await viewModel.showMonth(offsetBy: delta, for: student) }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            loadingState
        } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            errorState(error)
        } else {
            scrollingContent
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 42))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.orange)

                Text(message)
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    Task { await viewModel.refresh(for: student) }
                } label: {
                    Text("Try again")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
        }
        .refreshable { await viewModel.refresh(for: student) }
    }

    private var scrollingContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    if viewModel.displayMode == .month {
                        AssessmentsCalendarGrid(
                            days: viewModel.calendarDays,
                            selectedDay: viewModel.selectedDay
                        ) { day in
                            withAnimation(.easeInOut(duration: 0.18)) {
                                viewModel.selectDay(day)
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    }

                    if viewModel.selectedDay != nil {
                        dayFilterChip
                    }

                    if viewModel.visibleItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.dayGroups) { group in
                            AssessmentDayHeader(title: group.title, count: group.items.count)

                            ForEach(group.items) { item in
                                AssessmentRow(
                                    item: item,
                                    viewModel: viewModel,
                                    onOpen: {
                                        detailItem = item
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    },
                                    onToggle: { toggle(item) }
                                )
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                            }
                        }
                    }

                    if let label = viewModel.freshnessLabel {
                        Text(label)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(viewModel.isShowingStaleData ? .orange : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                            .padding(.bottom, 28)
                    } else {
                        Color.clear.frame(height: 24)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await viewModel.refresh(for: student) }
    }

    private var dayFilterChip: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    viewModel.selectDay(nil)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    Text(viewModel.selectedDayTitle ?? "Selected day")
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear day filter")

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 78, height: 78)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 38))
                    .foregroundColor(.green)
            }

            VStack(spacing: 6) {
                Text(viewModel.emptyStateTitle)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)

                Text(viewModel.emptyStateMessage)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
        .padding(.bottom, 40)
    }

    // MARK: - Actions

    private func toggle(_ item: Assessment) {
        guard viewModel.writesAvailable else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        Task { await viewModel.toggleStatus(of: item) }
    }
}

// MARK: - Notice banner

/// A refresh that failed over warm data, or a write W4 refused. Never blocks the list.
private struct AssessmentNoticeBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.orange)
                .padding(.top, 1)

            Text(message)
                .font(.system(.footnote, design: .rounded))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Month grid

private struct AssessmentsCalendarGrid: View {
    let days: [AssessmentCalendarDay]
    let selectedDay: Date?
    let onSelect: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    /// Monday-first, matching `W4Dates.calendar.firstWeekday`.
    private static let weekdayInitials = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(Self.weekdayInitials.enumerated()), id: \.offset) { entry in
                    Text(entry.element)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(days) { day in
                    Button {
                        onSelect(day.date)
                    } label: {
                        cell(day)
                    }
                    .buttonStyle(.plain)
                    .disabled(!day.isInMonth)
                    .accessibilityLabel(dayAccessibilityLabel(day))
                }
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func cell(_ day: AssessmentCalendarDay) -> some View {
        VStack(spacing: 3) {
            Text("\(day.dayNumber)")
                .font(.system(size: 14, weight: day.isToday ? .bold : .regular, design: .rounded))
                .foregroundColor(numberColor(day))

            Circle()
                .fill(dotColor(day))
                .frame(width: 5, height: 5)
                .opacity(day.hasItems ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor(day))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(day.isToday ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .opacity(day.isInMonth ? 1 : 0.28)
    }

    private func isSelected(_ day: AssessmentCalendarDay) -> Bool {
        guard let selectedDay else { return false }
        return W4Dates.isSameDay(selectedDay, day.date)
    }

    private func numberColor(_ day: AssessmentCalendarDay) -> Color {
        if isSelected(day) { return .white }
        return day.isInMonth ? .primary : .secondary
    }

    private func dotColor(_ day: AssessmentCalendarDay) -> Color {
        if isSelected(day) { return .white }
        if day.overdue > 0 { return .red }
        if day.pending > 0 { return .accentColor }
        return .green
    }

    private func backgroundColor(_ day: AssessmentCalendarDay) -> Color {
        isSelected(day) ? Color.accentColor : Color.clear
    }

    private func dayAccessibilityLabel(_ day: AssessmentCalendarDay) -> String {
        let base = W4Dates.format(day.date)
        guard day.hasItems else { return "\(base), nothing due" }
        return day.total == 1
            ? "\(base), 1 assessment"
            : "\(base), \(day.total) assessments"
    }
}

// MARK: - Day header

private struct AssessmentDayHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)

            Text(count == 1 ? "1 item" : "\(count) items")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.top, 16)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }
}

// MARK: - Row

private struct AssessmentRow: View {
    let item: Assessment
    @ObservedObject var viewModel: AssessmentsViewModel
    let onOpen: () -> Void
    let onToggle: () -> Void

    private var isDone: Bool { item.status == .done }
    private var isOverdue: Bool { viewModel.isOverdue(item) }
    private var themeColor: Color { SubjectMapper.color(for: viewModel.iconToken(for: item)) }

    var body: some View {
        // Deliberately NOT an outer `Button`: the status control is itself a button, and a button
        // nested inside a button's label has no dependable hit-testing. A tap gesture on the row
        // with a real button inside it does — the innermost gesture wins.
        HStack(spacing: 12) {
            iconTile

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundColor(isDone ? .secondary : .primary)
                    .strikethrough(isDone, color: .secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let subtitle = viewModel.subtitle(for: item) {
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if let due = viewModel.dueLabel(for: item) {
                        AssessmentPill(
                            text: due,
                            color: isDone ? .secondary : (isOverdue ? .red : .accentColor)
                        )
                    }
                    if let unit = item.unit, !unit.isEmpty {
                        AssessmentPill(text: unit, color: themeColor)
                    }
                    if item.kind == .studentCreated {
                        AssessmentPill(text: "Personal", color: .purple)
                    }
                }
                .padding(.top, 2)
            }

            AssessmentStatusControl(
                status: item.status,
                isBusy: viewModel.isPendingWrite(item),
                isInteractive: viewModel.writesAvailable,
                action: onToggle
            )
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isOverdue ? Color.red.opacity(0.5) : .clear, lineWidth: 1)
        }
        .opacity(isDone ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .contextMenu {
            if viewModel.writesAvailable {
                Button {
                    onToggle()
                } label: {
                    Label(
                        item.offeredTransition == .confirmDone ? "Confirm done" : "Revert to pending",
                        systemImage: item.offeredTransition == .confirmDone
                            ? "checkmark.circle"
                            : "arrow.uturn.backward"
                    )
                }
            }
            Button {
                onOpen()
            } label: {
                Label("Details", systemImage: "info.circle")
            }
        }
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(themeColor.opacity(isDone ? 0.06 : 0.14))
                .frame(width: 38, height: 38)

            Image(systemName: SubjectMapper.iconName(for: viewModel.iconToken(for: item)))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isDone ? .secondary : themeColor)
                .symbolEffectsRemoved()
        }
    }
}

// MARK: - Pills and status

private struct AssessmentPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.13))
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

/// The done affordance. When writes are unavailable — the OQ-3 flag is off, or W4 published no
/// endpoint — this is a plain, non-interactive indicator rather than a button that would do
/// nothing.
private struct AssessmentStatusControl: View {
    let status: AssessmentStatus
    let isBusy: Bool
    let isInteractive: Bool
    let action: () -> Void

    var body: some View {
        Group {
            if isInteractive {
                Button(action: action) { indicator }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .accessibilityLabel(
                        status == .done ? "Revert to pending" : "Confirm done"
                    )
            } else {
                indicator
                    .accessibilityLabel(status == .done ? "Done" : "Pending")
                    .accessibilityHint("Changing this is not available yet")
            }
        }
        .frame(width: 30, height: 30)
    }

    private var indicator: some View {
        ZStack {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .stroke(
                        status == .done ? Color.green : Color.secondary.opacity(0.35),
                        lineWidth: 1.5
                    )
                    .frame(width: 24, height: 24)

                if status == .done {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 18, height: 18)

                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .symbolEffectsRemoved()
                }
            }
        }
        .frame(width: 30, height: 30)
        .contentShape(Rectangle())
        .opacity(isInteractive ? 1 : 0.65)
    }
}

// MARK: - Detail sheet

private struct AssessmentDetailSheet: View {
    let item: Assessment
    @ObservedObject var viewModel: AssessmentsViewModel

    @Environment(\.dismiss) private var dismiss

    /// The live copy, so a status flip made from this sheet is reflected here immediately.
    private var current: Assessment {
        viewModel.items.first(where: { $0.id == item.id }) ?? item
    }

    private var themeColor: Color { SubjectMapper.color(for: viewModel.iconToken(for: current)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Divider()
                    details
                    if viewModel.writesAvailable {
                        transitionButton
                    } else {
                        readOnlyNote
                    }
                }
                .padding(20)
            }
            .navigationTitle("Assessment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: SubjectMapper.iconName(for: viewModel.iconToken(for: current)))
                .font(.title2)
                .foregroundColor(themeColor)
                .frame(width: 46, height: 46)
                .background(themeColor.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(current.title)
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    AssessmentPill(
                        text: current.status == .done ? "Done" : "Pending",
                        color: current.status == .done ? .green : .orange
                    )
                    if viewModel.isOverdue(current) {
                        AssessmentPill(text: "Overdue", color: .red)
                    }
                    if current.kind == .studentCreated {
                        AssessmentPill(text: "Personal", color: .purple)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var details: some View {
        VStack(spacing: 12) {
            if let subject = current.subject, !subject.isEmpty {
                row(icon: "books.vertical", title: "Subject", value: subject)
            }
            if let classCode = current.classCode, !classCode.isEmpty {
                row(icon: "person.3", title: "Class", value: classCode)
            }
            if let teacher = current.teacher, !teacher.isEmpty {
                row(icon: "person", title: "Teacher", value: teacher)
            }
            if let unit = current.unit, !unit.isEmpty {
                row(icon: "tag", title: "Unit", value: unit)
            }
            if let due = current.dueDate {
                row(
                    icon: "calendar",
                    title: "Due",
                    value: [W4Dates.format(due), viewModel.dueLabel(for: current)]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
            } else {
                row(icon: "calendar", title: "Due", value: "No date")
            }
        }
    }

    private func row(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 22)

            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }

    private var transitionButton: some View {
        Button {
            let target = current
            Task { await viewModel.toggleStatus(of: target) }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isPendingWrite(current) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: current.offeredTransition == .confirmDone
                          ? "checkmark.circle.fill"
                          : "arrow.uturn.backward.circle.fill")
                }
                Text(current.offeredTransition == .confirmDone ? "Confirm done" : "Revert to pending")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .tint(current.offeredTransition == .confirmDone ? .green : .secondary)
        .disabled(viewModel.isPendingWrite(current))
    }

    private var readOnlyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.top, 2)

            Text("Marking assessments done is not available in this version. W4 still shows this as \(current.status == .done ? "done" : "pending").")
                .font(.system(.footnote, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AssessmentsView(student: .demo)
    }
}
