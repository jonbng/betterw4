//
//  GradesView.swift
//  BetterLectio
//
//  Created by GitHub Copilot on 02/03/2026.
//

import SwiftUI

struct GradesView: View {
    private struct ColumnAverage: Identifiable {
        let column: GradeColumn
        let value: String
        var id: String { column.key }
    }

    let student: Student
    @StateObject private var viewModel = GradesViewModel()
    /// `nil` represents “Alle”; otherwise this is a key parsed from Lectio's live header.
    @State private var selectedColumnKey: String?

    private var gradeColumns: [GradeColumn] {
        viewModel.report?.columns ?? []
    }

    private var selectedColumn: GradeColumn? {
        guard let selectedColumnKey else { return nil }
        return gradeColumns.first { $0.key == selectedColumnKey }
    }

    private var selectionLabel: String {
        selectedColumn?.shortLabel ?? "Alle"
    }

    /// Entries that have a grade for the selected type (or any grade when "Alle")
    private var visibleEntries: [GradeEntry] {
        guard let selectedColumnKey else { return viewModel.visibleGrades }
        return viewModel.visibleGrades.filter { $0.cell(for: selectedColumnKey) != nil }
    }

    private func cell(for entry: GradeEntry, columnKey: String? = nil) -> GradeCellValue? {
        guard let key = columnKey ?? selectedColumnKey else { return nil }
        return entry.cell(for: key)
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.visibleGrades.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.visibleGrades.isEmpty {
                errorView(error)
            } else {
                gradesOverview
            }
        }
        .navigationTitle("Karakteroversigt")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.loadGrades(for: student)
        }
        .task(id: student.studentId) {
            await viewModel.loadGrades(for: student)
        }
        .onChange(of: gradeColumns) { _, columns in
            if let selectedColumnKey,
               !columns.contains(where: { $0.key == selectedColumnKey }) {
                self.selectedColumnKey = nil
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Henter karakterer...")
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
                    await viewModel.loadGrades(for: student)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var gradesOverview: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Grade type picker
                gradeTypePicker

                // GPA card
                gpaCard

                // Subject section
                subjectSection

                // Notes section
                if let notes = viewModel.report?.notes, !notes.isEmpty {
                    notesSection(notes)
                }

                // Warning banners
                if let report = viewModel.report {
                    if let written = report.blockedWrittenProtocolTerm {
                        warningBanner("Skriftlig protokolvisning er midlertidigt lukket for terminen \"\(written)\".")
                    }
                    if let oral = report.blockedOralProtocolTerm {
                        warningBanner("Mundtlig protokolvisning er midlertidigt lukket for terminen \"\(oral)\".")
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var gradeTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                gradeFilterButton(title: "Alle", key: nil)
                ForEach(gradeColumns) { column in
                    gradeFilterButton(title: column.shortLabel, key: column.key)
                        .accessibilityLabel(column.label)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func gradeFilterButton(title: String, key: String?) -> some View {
        let isSelected = selectedColumnKey == key
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedColumnKey = key
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var gpaCard: some View {
        if let selectedColumn {
            singleAverageCard(column: selectedColumn)
        } else {
            allAveragesCard
        }
    }

    private func singleAverageCard(column: GradeColumn) -> some View {
        let average = average(for: column.key)
        return VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gennemsnit \(column.shortLabel)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(average ?? "-")
                            .font(.system(size: 34, weight: .bold))
                            .tracking(-0.5)

                        if average != nil {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(column.shortLabel)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                Text(column.shortLabel)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding(20)
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private var allAveragesCard: some View {
        let averages = gradeColumns.compactMap { column in
            average(for: column.key).map { ColumnAverage(column: column, value: $0) }
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Gennemsnit")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            if averages.isEmpty {
                Text("-")
                    .font(.system(size: 34, weight: .bold))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(averages) { average in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(average.value)
                                    .font(.title2.bold())
                                Text(average.column.shortLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(average.column.label), gennemsnit \(average.value)")
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private func average(for columnKey: String) -> String? {
        var weightedSum: Double = 0
        var totalWeight: Double = 0

        for entry in viewModel.visibleGrades {
            guard let cell = entry.cell(for: columnKey),
                  let numericValue = sevenStepValue(cell.value) else { continue }
            let weight = max(0, cell.weight ?? 1)
            guard weight > 0 else { continue }
            weightedSum += numericValue * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return nil }
        let average = weightedSum / totalWeight
        return String(format: "%.2f", average).replacingOccurrences(of: ".", with: ",")
    }

    private func sevenStepValue(_ raw: String) -> Double? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), [-3, 0, 2, 4, 7, 10, 12].contains(value) else {
            return nil
        }
        return value
    }

    private var subjectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectionLabel)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.horizontal, 16)

            if visibleEntries.isEmpty {
                Text("Ingen karakterer fundet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                if selectedColumnKey == nil {
                    allGradesTable
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                            subjectRow(entry: entry)
                            if index < visibleEntries.count - 1 {
                                Divider()
                                    .background(Color(UIColor.separator).opacity(0.5))
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var allGradesTable: some View {
        let tableWidth = max(300, 160 + CGFloat(gradeColumns.count) * 60)
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                allGradesHeaderRow
                Divider().padding(.leading, 16)
                ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                    subjectRowAll(entry: entry)
                    if index < visibleEntries.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .frame(width: tableWidth)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var allGradesHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Fag")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(gradeColumns) { column in
                Text(column.shortLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemGroupedBackground))
    }

    private func subjectRowAll(entry: GradeEntry) -> some View {
        HStack(spacing: 0) {
            Text(displaySubject(entry.subject))
                .font(.system(size: 15, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(gradeColumns) { column in
                let value = entry.cell(for: column.key)?.value
                Text(value ?? "-")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(gradeSpectrumColor(for: value))
                    .frame(width: 60, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.subject
            } label: {
                Label("Kopier fag", systemImage: "doc.on.doc")
            }
        } preview: {
            SubjectGradeDetailView(entry: entry, columns: gradeColumns)
        }
    }

    private func subjectRow(entry: GradeEntry) -> some View {
        let cell = cell(for: entry)
        let gradeValue = cell?.value ?? "-"
        let progress = progressForGrade(cell?.value)

        return HStack(spacing: 16) {
            Text(displaySubject(entry.subject))
                .font(.system(size: 15, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 120, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)

            Text(gradeValue)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = entry.subject
            } label: {
                Label("Kopier fag", systemImage: "doc.on.doc")
            }
        } preview: {
            SubjectGradeDetailView(entry: entry, columns: gradeColumns)
        }
    }

    /// Shortens grade type suffixes for display: ", Mundtlig" → " (M)", ", Skriftlig" → " (S)"
    private func displaySubject(_ subject: String) -> String {
        let lower = subject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.hasSuffix(", mundtlig") {
            let base = String(subject.dropLast(", Mundtlig".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return base + " (M)"
        }
        if lower.hasSuffix(", skriftlig") {
            let base = String(subject.dropLast(", Skriftlig".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return base + " (S)"
        }
        return subject
    }

    /// Normalized position 0...1 on the Danish scale (-3 worst … 12 best). Nil if not a number.
    private func clampedGrade01(from value: String?) -> CGFloat? {
        guard let value else { return nil }
        let normalized = value
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let numeric = Double(normalized) else { return nil }
        let clamped = max(-3.0, min(12.0, numeric))
        return CGFloat((clamped + 3) / 15)
    }

    /// Ease-in-out on 0…1: derivative peaks at center so equal grade steps cover more hue change in the orange–yellow band.
    private func gradeSpectrumEaseInOut(_ t: Double) -> Double {
        if t < 0.5 {
            return 2 * t * t
        }
        let inv = 1 - t
        return 1 - 2 * inv * inv
    }

    /// -3 → red, 12 → green. Hue is eased so mid grades linger in orange/yellow; sin(πt) bumps S/B where yellow is usually weak.
    private func gradeSpectrumColor(for value: String?) -> Color {
        guard let t = clampedGrade01(from: value) else { return .secondary }
        let td = Double(t)
        let hue = gradeSpectrumEaseInOut(td) * 0.34
        let midPop = sin(Double.pi * td)
        let saturation = min(1.0, 0.86 - 0.06 * td + 0.28 * midPop)
        let brightness = min(1.0, 0.92 - 0.09 * td + 0.10 * midPop)
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    /// Returns progress 0...1 for the grade. Danish 7-point scale: -3, 0, 2, 4, 7, 10, 12. Map to 0...1.
    private func progressForGrade(_ value: String?) -> CGFloat {
        clampedGrade01(from: value) ?? 0
    }

    private func warningBanner(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.footnote)
                .foregroundColor(.orange)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.1))
    }

    private func notesSection(_ notes: [GradeNoteEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Karakternoter")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.horizontal, 16)
                .padding(.top, 24)

            VStack(spacing: 0) {
                ForEach(notes) { note in
                    noteRow(note)
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 16)
    }

    private func noteRow(_ note: GradeNoteEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.hold)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(note.grade)
                    .font(.headline)
            }

            Text(note.gradeType)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(note.insertedAt)
                .font(.caption2)
                .foregroundColor(.secondary)

            if let noteText = note.note, !noteText.isEmpty {
                Text(noteText)
                    .font(.subheadline)
                    .padding(.top, 2)
            }
        }
        .padding(16)
    }
}

#Preview {
    NavigationStack {
        GradesView(student: Student(studentId: "0", gymId: 94, name: "Preview"))
    }
}
