//
//  AbsenceView.swift
//  BetterW4
//
//  The Attendance screen (`ui.md` §4.7).
//
//  W4 keeps two attendance ledgers — Academics and Extra Academics — and each has its own meter on
//  the Home page reading "You have N absences and M latenesses so far". Both meters sit at the top
//  of this screen because they are the number a student actually wants, and because they cost
//  nothing: `AttendanceRepository` parses them out of the Home page that is already in the page
//  cache, without issuing a request. A segmented control below them picks which ledger's
//  registrations the list shows.
//
//  There is no percentage anywhere on this screen and no cause editor, because W4 has neither.
//  W4 counts events, and its registration rows are read-only. Self-registration uses W4's
//  captured Yii form natively, with the authenticated web page retained as a fallback.
//

import SwiftUI

struct AbsenceView: View {
    let student: Student

    @StateObject private var viewModel = AttendanceViewModel()
    /// Incremented when the Absence tab is tapped while already selected (scroll to top).
    @State private var scrollToTopTick = 0
    @State private var showRegister = false
    @State private var selectedLesson: TimetableEvent?

    private let subjectColors: [Color] = [
        .blue, .purple, .orange, .teal, .pink, .indigo, .mint, .cyan, .brown, .red
    ]

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.hasContent {
                loadingView
            } else if let error = viewModel.errorMessage, !viewModel.hasContent {
                errorView(error)
            } else {
                attendanceList
            }
        }
        .navigationTitle("Absence")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !student.isDemo {
                    Button {
                        showRegister = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Register absences")
                }
            }
        }
        .sheet(isPresented: $showRegister) {
            NavigationStack {
                RegisterAbsenceView(student: student) {
                    await viewModel.refresh(for: student)
                }
            }
        }
        .sheet(item: $selectedLesson) { lesson in
            AttendanceLessonDetailView(lesson: lesson)
        }
        .refreshable {
            await viewModel.refresh(for: student)
        }
        .task(id: student.studentId) {
            await viewModel.load(for: student)
        }
    }

    // MARK: - Whole-screen states

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Loading attendance…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Try again") {
                Task { await viewModel.load(for: student) }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Content

    private var attendanceList: some View {
        ScrollViewReader { proxy in
            List {
                metersSection
                    .id("absenceTop")

                if let notice = viewModel.noticeMessage {
                    noticeSection(notice)
                }

                ledgerPickerSection

                viewModePickerSection

                if viewModel.viewMode == .week {
                    weekSection
                } else if !viewModel.breakdown.isEmpty {
                    breakdownSection
                }

                if viewModel.viewMode == .list {
                    if viewModel.sections.isEmpty {
                        emptySection
                    } else {
                        daySections
                    }
                }

                if viewModel.hasMorePages {
                    Section {
                        Label(
                            "W4 has more registrations than this page shows.",
                            systemImage: "ellipsis.circle"
                        )
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }
                }

                registerSection
            }
            .listStyle(.insetGrouped)
            .overlay(alignment: .top) {
                if viewModel.isRefreshing {
                    ProgressView()
                        .padding(.top, 6)
                }
            }
            .onChange(of: scrollToTopTick) { _, _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo("absenceTop", anchor: .top)
                }
            }
            .background {
                TabBarSameTabReselectDetector(tabIndex: AuthenticatedTabIndex.absences) {
                    scrollToTopTick += 1
                }
            }
        }
    }

    // MARK: - Meters

    private var metersSection: some View {
        Section {
            ForEach(viewModel.meters) { meter in
                AttendanceMeterCard(display: meter)
            }
        } header: {
            HStack {
                Text("Attendance meters")
                Spacer()
                if let label = viewModel.freshnessLabel {
                    Text(label)
                        .font(.caption2)
                        .textCase(nil)
                        .foregroundColor(viewModel.isShowingCachedCopy ? .orange : .secondary)
                }
            }
        }
    }

    private func noticeSection(_ notice: String) -> some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundColor(.orange)
                Text(notice)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Ledger picker

    private var ledgerPickerSection: some View {
        Section {
            Picker("Ledger", selection: $viewModel.selectedSource) {
                ForEach(AttendanceSource.allCases, id: \.self) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
    }

    private var viewModePickerSection: some View {
        Section {
            Picker("View", selection: $viewModel.viewMode) {
                ForEach(AttendanceViewModel.ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var weekSection: some View {
        Section {
            HStack {
                Button {
                    viewModel.shiftWeek(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text("Week \(W4Dates.isoWeek(of: viewModel.selectedDate).week)")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.shiftWeek(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            if let days = viewModel.week?.days, !days.isEmpty {
                HStack {
                    ForEach(days) { day in
                        let selected = Calendar.current.isDate(day.date, inSameDayAs: viewModel.selectedDate)
                        Button {
                            viewModel.selectDay(day.date)
                        } label: {
                            Text(day.date, format: .dateTime.weekday(.narrow))
                                .fontWeight(selected ? .bold : .regular)
                                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            let lessons = viewModel.lessonsOnSelectedDay
            if lessons.isEmpty {
                Text("No classes with attendance on this day.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(lessons) { event in
                    Button { selectedLesson = event } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title).font(.headline).foregroundStyle(.primary)
                                if let start = event.start, let end = event.end {
                                    Text("\(Self.timeFormatter.string(from: start)) – \(Self.timeFormatter.string(from: end))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let room = event.room, !room.isEmpty {
                                    Text(room).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            AttendanceStatusChip(
                                attendance: event.attendance,
                                rawLabel: event.attendanceLabel
                            )
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    // MARK: - Breakdown

    private var breakdownSection: some View {
        Section("Registrations by class") {
            VStack(spacing: 16) {
                donutChart
                    .frame(height: 160)
                    .padding(.top, 4)

                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(viewModel.breakdown.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(colorForIndex(index))
                                .frame(width: 10, height: 10)
                            Text(SubjectMapper.displayName(for: row.label))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Text("\(row.total)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(
                            "\(row.label), \(row.total) registration\(row.total == 1 ? "" : "s")"
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    /// One `Section` per day of registrations.
    ///
    /// The section body lives in its own `View` type rather than inline here. Xcode batches this
    /// file with `SubjectGradeDetailView.swift`, which imports Charts, and in a shared batch the
    /// `ChartContentBuilder` overloads become visible to this file too — a nested
    /// `ForEach { Section { ForEach { … } } }` then resolves against chart content and fails with
    /// an availability error naming a framework this screen never uses. Inside a `View`'s `body`
    /// the builder is pinned to `ViewBuilder` by the protocol, so the ambiguity cannot arise.
    private var daySections: some View {
        ForEach(viewModel.sections) { section in
            AttendanceDaySectionView(section: section, accent: accentColor(for:))
        }
    }

    private var donutChart: some View {
        let breakdown = viewModel.breakdown
        let total = breakdown.reduce(0) { $0 + $1.total }

        return GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                if total > 0 {
                    ForEach(Array(breakdown.enumerated()), id: \.element.id) { index, row in
                        let startAngle = arcStartAngle(for: index, in: breakdown, total: total)
                        let endAngle = startAngle + (Double(row.total) / Double(total)) * 360

                        DonutSlice(
                            startAngle: .degrees(startAngle - 90),
                            endAngle: .degrees(endAngle - 90),
                            lineWidth: size * 0.18
                        )
                        .fill(colorForIndex(index))
                    }
                }

                VStack(spacing: 2) {
                    Text("\(total)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(total == 1 ? "registration" : "registrations")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity)
        }
        .accessibilityHidden(true)
    }

    private func arcStartAngle(for index: Int, in breakdown: [SubjectAttendance], total: Int) -> Double {
        var angle: Double = 0
        for i in 0..<index {
            angle += (Double(breakdown[i].total) / Double(total)) * 360
        }
        return angle
    }

    // MARK: - Rows

    private func recordRow(_ record: AttendanceRecord) -> some View {
        AttendanceRecordRow(
            record: record,
            accent: accentColor(for: record)
        )
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundColor(.green)
                Text("No absences recorded.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Register absences

    private var registerSection: some View {
        Section {
            if student.isDemo {
                Label("Register absences", systemImage: "square.and.pencil")
                    .foregroundColor(.secondary)
            } else {
                Button {
                    showRegister = true
                } label: {
                    Label("Register absences", systemImage: "square.and.pencil")
                }
            }
        } footer: {
            Text(
                student.isDemo
                    ? "Not available in demo mode."
                    : "Select a date, choose classes, and provide a reason."
            )
        }
    }

    // MARK: - Colour helpers

    private func colorForIndex(_ index: Int) -> Color {
        subjectColors[index % subjectColors.count]
    }

    /// Ties a row to its slice in the donut so the list and the chart agree.
    private func accentColor(for record: AttendanceRecord) -> Color {
        let label = record.subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = label.isEmpty ? "Unspecified" : label
        if let index = viewModel.breakdown.firstIndex(where: { $0.label == key }) {
            return colorForIndex(index)
        }
        return .gray
    }
}

private struct AttendanceStatusChip: View {
    let attendance: LessonAttendance?
    var rawLabel: String? = nil

    var body: some View {
        Text(rawLabel?.isEmpty == false ? rawLabel! : (attendance?.displayName ?? "Unknown"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.14))
            .clipShape(Capsule())
    }
}

private struct AttendanceLessonDetailView: View {
    let lesson: TimetableEvent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                LabeledContent(
                    "Status",
                    value: lesson.attendanceLabel?.isEmpty == false
                        ? lesson.attendanceLabel!
                        : (lesson.attendance?.displayName ?? "Unknown")
                )
                if let phrase = lesson.attendanceTooltip {
                    LabeledContent("W4 status", value: phrase)
                }
                if let start = lesson.start, let end = lesson.end {
                    LabeledContent("Time", value: "\(Self.time.string(from: start)) – \(Self.time.string(from: end))")
                }
                if let teacher = lesson.teacher, !teacher.isEmpty {
                    LabeledContent("Teacher", value: teacher)
                }
                if let room = lesson.room, !room.isEmpty {
                    LabeledContent("Room", value: room)
                }
            }
            .navigationTitle(lesson.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private static let time: DateFormatter = {
        let value = DateFormatter()
        value.dateFormat = "HH:mm"
        return value
    }()
}

// MARK: - Meter card

/// One ledger's meter: the two counts W4 prints, and its sentence underneath.
///
/// No percentage and no threshold colouring — W4 publishes neither, and inventing a "your absence
/// is high" line would be this app making up school policy.
private struct AttendanceMeterCard: View {
    let display: AttendanceMeterDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(display.title)
                .font(.headline)

            HStack(spacing: 12) {
                counter(
                    value: display.absences,
                    label: "Absences",
                    systemImage: "xmark.circle.fill",
                    tint: .orange
                )
                counter(
                    value: display.latenesses,
                    label: "Latenesses",
                    systemImage: "clock.badge.exclamationmark.fill",
                    tint: .yellow
                )
            }

            Text(display.sentence)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(display.title). \(display.sentence)")
    }

    private func counter(value: Int?, label: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: (value ?? 0) > 0 ? systemImage : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor((value ?? 0) > 0 ? tint : .green)
                Text(value.map(String.init) ?? "–")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(UIColor.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Registration row

/// One row of `people/students/absences` or `.../eaabsences`.
///
/// `status` is printed verbatim: it is W4's word for what happened, and paraphrasing it would be
/// this app guessing at a vocabulary it has never captured in full.
/// One day's registrations. A real `View` type so its `body` is unambiguously built by
/// `ViewBuilder` — see the note on `daySections`.
private struct AttendanceDaySectionView: View {
    let section: AttendanceDaySection
    let accent: (AttendanceRecord) -> Color

    var body: some View {
        Section(section.title) {
            ForEach(section.records) { record in
                AttendanceRecordRow(record: record, accent: accent(record))
            }
        }
    }
}

private struct AttendanceRecordRow: View {
    let record: AttendanceRecord
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(tint)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let subject = record.subject, !subject.isEmpty {
                        Text(SubjectMapper.displayName(for: subject))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent)
                            .clipShape(Capsule())
                    }
                    if let period = record.period, !period.isEmpty {
                        Text(period)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if let studentWas = record.studentWas, !studentWas.isEmpty {
                    LabeledContent("Student was", value: studentWas).font(.caption)
                }
                if !record.status.isEmpty {
                    LabeledContent("Type", value: record.status).font(.caption)
                }

                HStack(spacing: 12) {
                    if let addedBy = record.addedBy, !addedBy.isEmpty {
                        Label("Added by \(addedBy)", systemImage: "person")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if !record.displayDate.isEmpty {
                        Label(record.displayDate, systemImage: "calendar")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let note = record.note, !note.isEmpty {
                    Text("Reason: \(note)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var icon: String {
        switch record.kind {
        case .absence: return "xmark.circle.fill"
        case .lateness: return "clock.badge.exclamationmark.fill"
        case .prearranged: return "calendar.badge.checkmark"
        case .medical: return "cross.case.fill"
        case .present: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch record.kind {
        case .absence: return .orange
        case .lateness: return .yellow
        case .prearranged: return .blue
        case .medical: return .teal
        case .present: return .green
        case .unknown: return .secondary
        }
    }
}

// MARK: - Donut Slice Shape

struct DonutSlice: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - lineWidth / 2

        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path.strokedPath(.init(lineWidth: lineWidth, lineCap: .butt))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AbsenceView(
            student: Student(
                studentId: "nc26abcd",
                name: "Preview Student"
            )
        )
    }
}
