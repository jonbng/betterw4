//
//  AbsenceView.swift
//  BetterLectio
//
//  Created by Kilo Code on 04/03/2026.
//

import SwiftUI

struct AbsenceView: View {
    let student: Student
    @StateObject private var viewModel = AbsenceViewModel()
    @State private var selectedEntry: AbsenceEntry?

    private let subjectColors: [Color] = [
        .blue, .purple, .orange, .teal, .pink, .indigo, .mint, .cyan, .brown, .red
    ]

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.report == nil {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.report == nil {
                errorView(error)
            } else {
                absenceList
            }
        }
        .navigationTitle("Fravær")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.loadAbsence(for: student)
        }
        .task(id: student.studentId) {
            await viewModel.loadAbsence(for: student)
        }
        .sheet(item: $selectedEntry) { entry in
            EditAbsenceView(entry: entry, student: student, viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Henter fraværsdata...")
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

            Button("Prøv igen") {
                Task {
                    await viewModel.loadAbsence(for: student)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var absenceList: some View {
        List {
            summarySection

            if let notice = viewModel.noticeMessage {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(notice)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 4)
                        Button {
                            viewModel.noticeMessage = nil
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Skjul besked")
                    }
                }
            }

            if let warning = viewModel.absenceWarning {
                warningSection(warning)
            }

            if !viewModel.subjectBreakdown.isEmpty {
                subjectDistributionSection
            }

            if viewModel.hasMissingReasons {
                missingReasonsSection
            }

            if viewModel.hasRegistrations {
                registrationsSection
            }

            if !viewModel.hasMissingReasons && !viewModel.hasRegistrations {
                Section {
                    Text("Ingen fraværsregistreringer fundet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        Section("Samlet fravær") {
            VStack(spacing: 16) {
                HStack(spacing: 24) {
                    absenceStatCard(
                        title: "Almindeligt",
                        percentage: viewModel.regularAbsencePercent,
                        color: viewModel.absenceColor(for: viewModel.regularAbsencePercent)
                    )

                    absenceStatCard(
                        title: "Skriftligt",
                        percentage: viewModel.writtenAbsencePercent,
                        color: viewModel.absenceColor(for: viewModel.writtenAbsencePercent)
                    )
                }

                // Total entries count
                let total = viewModel.allEntries.count
                if total > 0 {
                    Text("\(total) fraværsregistrering\(total == 1 ? "" : "er") i alt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func absenceStatCard(title: String, percentage: Double, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)
                    .frame(width: 70, height: 70)

                Circle()
                    .trim(from: 0, to: min(percentage / 100, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: percentage)

                Text("\(percentage, specifier: "%.1f")%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Warning Section

    private func warningSection(_ warning: String) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Text(warning)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Subject Distribution Section

    private var subjectDistributionSection: some View {
        Section("Fravær pr. fag") {
            VStack(spacing: 16) {
                // Donut chart
                donutChart
                    .frame(height: 160)
                    .padding(.top, 4)

                // Legend
                let columns = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(viewModel.subjectBreakdown.enumerated()), id: \.element.id) { index, subject in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(colorForIndex(index))
                                .frame(width: 10, height: 10)
                            Text(subject.subject.uppercased())
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("\(subject.totalEntries)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var donutChart: some View {
        let breakdown = viewModel.subjectBreakdown
        let totalEntries = breakdown.reduce(0) { $0 + $1.totalEntries }

        return GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                if totalEntries > 0 {
                    ForEach(Array(breakdown.enumerated()), id: \.element.id) { index, subject in
                        let startAngle = arcStartAngle(for: index, in: breakdown, total: totalEntries)
                        let endAngle = startAngle + (Double(subject.totalEntries) / Double(totalEntries)) * 360

                        DonutSlice(
                            startAngle: .degrees(startAngle - 90),
                            endAngle: .degrees(endAngle - 90),
                            lineWidth: size * 0.18
                        )
                        .fill(colorForIndex(index))
                    }
                }

                VStack(spacing: 2) {
                    Text("\(totalEntries)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("moduler")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity)
        }
    }

    private func arcStartAngle(for index: Int, in breakdown: [SubjectAbsence], total: Int) -> Double {
        var angle: Double = 0
        for i in 0..<index {
            angle += (Double(breakdown[i].totalEntries) / Double(total)) * 360
        }
        return angle
    }

    // MARK: - Missing Reasons Section

    private var missingReasonsSection: some View {
        Section {
            DisclosureGroup(
                isExpanded: .constant(true)
            ) {
                if let entries = viewModel.report?.missingReasons {
                    ForEach(entries) { entry in
                        absenceEntryRow(entry, showReason: false)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Manglende fraværsårsager")
                        .font(.headline)
                    Spacer()
                    if let count = viewModel.report?.missingReasons.count, count > 0 {
                        Text("\(count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Registrations Section

    private var registrationsSection: some View {
        Section {
            DisclosureGroup(
                isExpanded: .constant(true)
            ) {
                if let entries = viewModel.report?.registrations {
                    ForEach(entries) { entry in
                        absenceEntryRow(entry, showReason: true)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "list.bullet.clipboard.fill")
                        .foregroundColor(.blue)
                    Text("Fraværsregistreringer")
                        .font(.headline)
                    Spacer()
                    if let count = viewModel.report?.registrations.count, count > 0 {
                        Text("\(count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }

    // MARK: - Unified Entry Row

    @ViewBuilder
    private func absenceEntryRow(_ entry: AbsenceEntry, showReason: Bool) -> some View {
        if entry.registrationId != nil {
            Button {
                selectedEntry = entry
            } label: {
                absenceEntryRowContent(entry, showReason: showReason, showsEditIcon: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Åbner redigering af fraværsårsag og note")
        } else {
            absenceEntryRowContent(entry, showReason: showReason, showsEditIcon: false)
        }
    }

    private func absenceEntryRowContent(
        _ entry: AbsenceEntry,
        showReason: Bool,
        showsEditIcon: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
                // Left: percentage circle
                absencePercentIndicator(entry)

                // Right: details
                VStack(alignment: .leading, spacing: 4) {
                // Subject tag + date
                HStack(spacing: 6) {
                    if let hold = entry.activityDetails?.hold, !hold.isEmpty {
                        let subject = hold.split(separator: " ").last.map(String.init) ?? hold
                        Text(subject.uppercased())
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(subjectColor(for: hold))
                            .clipShape(Capsule())
                    }

                    if let dateTime = entry.activityDetails?.dateTime, !dateTime.isEmpty {
                        Text(dateTime)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if !entry.registeredAt.isEmpty {
                        Text(entry.registeredAt)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Title or hold name
                if let title = entry.activityDetails?.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } else if let hold = entry.activityDetails?.hold, !hold.isEmpty {
                    Text(hold)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                // Teacher + room + week
                HStack(spacing: 12) {
                    if let teacher = entry.activityDetails?.teacher, !teacher.isEmpty {
                        Label(teacher, systemImage: "person")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if let room = entry.activityDetails?.room, !room.isEmpty {
                        Label(room, systemImage: "door.left.hand.closed")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if !entry.week.isEmpty {
                        Label("Uge \(entry.week)", systemImage: "calendar")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Reason + note (registrations only)
                if showReason {
                    if let reason = entry.reason, !reason.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: entry.isApproved ? "checkmark.seal.fill" : "doc.text")
                                .font(.caption2)
                                .foregroundColor(entry.isApproved ? .green : .blue)
                            Text(reason)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }

                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }

                    if let remark = entry.remark, !remark.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "text.quote")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(remark)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                } else {
                    Label("Mangler årsag", systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                }

                Spacer(minLength: 0)
                if showsEditIcon {
                    Image(systemName: "pencil")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Rediger fravær")
                }
        }
        .padding(.vertical, 6)
    }

    private func absencePercentIndicator(_ entry: AbsenceEntry) -> some View {
        let color = entry.isApproved ? Color.green : absencePercentColor(entry.absencePercent)
        let cleanPercent = entry.absencePercent
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
        let percent = Double(cleanPercent) ?? 0

        return ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: 4)
                .frame(width: 44, height: 44)

            Circle()
                .trim(from: 0, to: percent / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))

            if entry.isApproved {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.green)
            } else {
                Text(entry.absencePercent)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
        }
    }

    // MARK: - Helper Functions

    private func absencePercentColor(_ percentString: String) -> Color {
        let cleanString = percentString
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let percent = Double(cleanString) else { return .gray }

        if percent == 0 {
            return .green
        } else if percent < 50 {
            return .orange
        } else {
            return .red
        }
    }

    private func colorForIndex(_ index: Int) -> Color {
        subjectColors[index % subjectColors.count]
    }

    private func subjectColor(for hold: String) -> Color {
        let breakdown = viewModel.subjectBreakdown
        if let idx = breakdown.firstIndex(where: { $0.fullHold == hold }) {
            return colorForIndex(idx)
        }
        return .gray
    }
}

// MARK: - Edit Absence

private struct EditAbsenceView: View {
    let entry: AbsenceEntry
    let student: Student
    @ObservedObject var viewModel: AbsenceViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var reasons: [AbsenceReasonOption] = []
    @State private var selectedReasonValue: String?
    @State private var initialReasonValue: String?
    @State private var note: String
    @State private var initialNote: String
    @State private var isLoadingReasons = true
    @State private var loadError: String?
    @State private var editorError: String?
    @State private var showDiscardConfirmation = false

    init(entry: AbsenceEntry, student: Student, viewModel: AbsenceViewModel) {
        self.entry = entry
        self.student = student
        self.viewModel = viewModel
        _note = State(initialValue: entry.note ?? "")
        _initialNote = State(initialValue: entry.note ?? "")
    }

    private var selectedReason: AbsenceReasonOption? {
        reasons.first { $0.value == selectedReasonValue }
    }

    private var hasChanges: Bool {
        selectedReasonValue != nil && (
            selectedReasonValue != initialReasonValue ||
            normalizedNote(note) != normalizedNote(initialNote)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Registrering") {
                    LabeledContent("Aktivitet", value: entry.activityDetails?.hold ?? entry.activity)
                    if let title = entry.activityDetails?.title, !title.isEmpty {
                        LabeledContent("Modul", value: title)
                    }
                    LabeledContent("Tid", value: entry.activityDetails?.dateTime ?? entry.registeredAt)
                    LabeledContent("Fravær", value: entry.absencePercent)
                }

                Section("Årsag") {
                    if isLoadingReasons {
                        HStack {
                            ProgressView()
                            Text("Henter årsager…")
                                .foregroundColor(.secondary)
                        }
                    } else if let loadError {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(loadError, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Button("Prøv igen") {
                                Task { await loadDetails() }
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(reasons) { reason in
                            Button {
                                selectedReasonValue = reason.value
                            } label: {
                                HStack {
                                    Text(reason.label)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedReasonValue == reason.value {
                                        Image(systemName: "checkmark")
                                            .fontWeight(.semibold)
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .accessibilityAddTraits(
                                selectedReasonValue == reason.value ? .isSelected : []
                            )
                        }
                    }
                }

                Section("Note") {
                    TextField("Valgfri kommentar…", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .submitLabel(.done)
                        .disabled(isLoadingReasons || loadError != nil)
                }
            }
            .navigationTitle("Rediger fravær")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(viewModel.isSaving || hasChanges)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuller") { requestDismiss() }
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("Gem")
                        }
                    }
                    .disabled(!hasChanges || isLoadingReasons || viewModel.isSaving)
                }
            }
            .task { await loadDetails() }
            .alert("Fraværsårsagen kunne ikke gemmes", isPresented: Binding(
                get: { editorError != nil },
                set: { if !$0 { editorError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(editorError ?? "Ukendt fejl")
            }
            .confirmationDialog(
                "Kassér ændringer?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Kassér ændringer", role: .destructive) { dismiss() }
                Button("Fortsæt redigering", role: .cancel) {}
            } message: {
                Text("Din valgte årsag og note bliver ikke gemt.")
            }
        }
    }

    private func loadDetails() async {
        isLoadingReasons = true
        loadError = nil
        do {
            let details = try await viewModel.editDetails(for: entry, student: student)
            reasons = details.reasons
            let existing = details.selectedReasonValue ?? details.reasons.first {
                $0.label.compare(entry.reason ?? "", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }?.value
            selectedReasonValue = existing
            initialReasonValue = existing
            note = details.note
            initialNote = details.note
        } catch {
            if !(error is CancellationError) {
                loadError = error.localizedDescription
            }
        }
        isLoadingReasons = false
    }

    private func requestDismiss() {
        if hasChanges {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func normalizedNote(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard let selectedReason else { return }
        Task {
            do {
                try await viewModel.updateAbsence(
                    entry: entry,
                    reason: selectedReason,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                    student: student
                )
                dismiss()
            } catch {
                editorError = error.localizedDescription
            }
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
                studentId: "123456",
                gymId: 94,
                name: "Test Student"
            )
        )
    }
}
