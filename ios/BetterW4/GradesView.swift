//
//  GradesView.swift
//  BetterW4
//
//  The Grades screen (`ui.md` §4.x, `features.md` §1.6).
//
//  The grades page at `academics/grades/grades` has never been captured, so this screen is built to
//  render **whatever columns W4 sends**: the parser slugs W4's own header row into
//  `W4GradeColumn`s, and everything here — the filter chips, the table header, the averages — is
//  driven off that array. A school that renames "Final" to "Awarded", adds a term, or drops the
//  predicted column gets a different table, not a broken one.
//
//  Scale is IB 1–7. There is no Danish 7-point colour ramp, no weight column, and no per-subject
//  "(M)" / "(S)" suffix, because W4 has none of those. A cell W4 left as an en dash is *absent*,
//  and absent renders as an en dash rather than as a zero.
//

import SwiftUI

struct GradesView: View {
    let student: Student

    @StateObject private var viewModel = GradesViewModel()

    /// Width of one grade column in the all-columns table.
    private let gradeColumnWidth: CGFloat = 74

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.hasContent {
                loadingView
            } else if let error = viewModel.errorMessage, !viewModel.hasContent {
                errorView(error)
            } else {
                gradesOverview
            }
        }
        .navigationTitle("Grades")
        .navigationBarTitleDisplayMode(.large)
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
            Text("Loading grades…")
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

    private var gradesOverview: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.isRefreshing {
                    ProgressView()
                        .padding(.top, 12)
                }

                if !viewModel.columns.isEmpty {
                    columnPicker
                }

                averageCard

                subjectSection

                ForEach(Array(viewModel.alerts.enumerated()), id: \.offset) { _, alert in
                    alertBanner(alert)
                }

                if let label = viewModel.freshnessLabel {
                    Text(label)
                        .font(.caption2)
                        .foregroundColor(viewModel.isShowingCachedCopy ? .orange : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    // MARK: - Column picker

    private var columnPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", columnID: nil, isAnticipated: false)
                ForEach(viewModel.columns) { column in
                    filterChip(
                        title: column.label,
                        columnID: column.id,
                        isAnticipated: column.isAnticipated
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func filterChip(title: String, columnID: String?, isAnticipated: Bool) -> some View {
        let isSelected = viewModel.selectedColumnID == columnID
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.selectedColumnID = columnID
            }
        } label: {
            HStack(spacing: 4) {
                if isAnticipated {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(isAnticipated ? "\(title), anticipated" : title)
    }

    // MARK: - Averages

    /// One number when a column is selected, a strip of them otherwise.
    ///
    /// The average is the plain mean of that column's IB 1–7 cells. Columns are never mixed and
    /// there is no weighting, because W4 publishes no weights.
    @ViewBuilder
    private var averageCard: some View {
        if let column = viewModel.selectedColumn {
            singleAverageCard(column: column)
        } else if !viewModel.columnAverages.isEmpty {
            allAveragesCard
        }
    }

    private func singleAverageCard(column: W4GradeColumn) -> some View {
        let average = viewModel.average(forColumnID: column.id)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Average · \(column.label)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(average ?? "–")
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                Text(average == nil ? "no IB grades in this column" : "IB 1–7")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .accessibilityElement(children: .combine)
    }

    private var allAveragesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Average · IB 1–7")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(viewModel.columnAverages) { average in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(average.value)
                                .font(.title2.bold())
                                .monospacedDigit()
                            Text(average.column.label)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(average.column.label), average \(average.value)")
                    }
                }
            }
        }
        .padding(20)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Subjects

    private var subjectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.selectionLabel)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.horizontal, 16)

            if viewModel.visibleRows.isEmpty {
                Text(viewModel.emptyMessage ?? "No grades found.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if viewModel.selectedColumnID == nil {
                allColumnsTable
            } else {
                singleColumnList
            }
        }
        .padding(.horizontal, 16)
    }

    /// Subject + every column W4 sent, scrolling sideways when there are more columns than fit.
    private var allColumnsTable: some View {
        let width = max(320, 160 + CGFloat(viewModel.columns.count) * gradeColumnWidth)
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                tableHeaderRow
                Divider().padding(.leading, 16)
                ForEach(Array(viewModel.visibleRows.enumerated()), id: \.element.id) { index, row in
                    tableRow(row)
                    if index < viewModel.visibleRows.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .frame(width: width)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            Text("Subject")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(viewModel.columns) { column in
                VStack(spacing: 2) {
                    Text(column.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if column.isAnticipated {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: gradeColumnWidth, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func tableRow(_ row: W4GradeRow) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displaySubject)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let teacher = row.teacher, !teacher.isEmpty {
                    Text(teacher)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(viewModel.columns) { column in
                GradeCellText(cell: row.cell(for: column.id))
                    .frame(width: gradeColumnWidth, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = row.displaySubject
            } label: {
                Label("Copy subject", systemImage: "doc.on.doc")
            }
        } preview: {
            SubjectGradeDetailView(row: row, columns: viewModel.columns)
        }
    }

    /// One column selected: subject, an IB progress bar, the grade, and the effort grade if W4
    /// attached one.
    private var singleColumnList: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.visibleRows.enumerated()), id: \.element.id) { index, row in
                singleColumnRow(row)
                if index < viewModel.visibleRows.count - 1 {
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func singleColumnRow(_ row: W4GradeRow) -> some View {
        let cell = viewModel.selectedColumnID.flatMap { row.cell(for: $0) }
        // (n − 1) / 6 on the IB branch. Free text draws no bar rather than a made-up one.
        let progress = cell?.ibProgress

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Text(row.displaySubject)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 130, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(height: 6)
                        if let progress {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * CGFloat(progress), height: 6)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 12)

                Text(displayValue(of: cell))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }

            if let effort = cell?.effort {
                EffortBadge(effort: effort)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = row.displaySubject
            } label: {
                Label("Copy subject", systemImage: "doc.on.doc")
            }
        } preview: {
            SubjectGradeDetailView(row: row, columns: viewModel.columns)
        }
    }

    /// A cell W4 left blank or absent reads as an en dash — never as a zero.
    private func displayValue(of cell: W4GradeCell?) -> String {
        guard let cell, !cell.value.isEmpty else { return "–" }
        return cell.value
    }

    // MARK: - Alerts

    private func alertBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(.orange)
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
}

// MARK: - Cell

/// One grade cell. An absent cell is an en dash, never a zero and never an empty gap.
struct GradeCellText: View {
    let cell: W4GradeCell?

    var body: some View {
        VStack(spacing: 3) {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(cell == nil ? .secondary : .primary)
                .lineLimit(1)

            if let effort = cell?.effort {
                Circle()
                    .fill(EffortBadge.tint(for: effort))
                    .frame(width: 6, height: 6)
                    .accessibilityLabel(effort.displayName)
            }
        }
    }

    private var text: String {
        guard let cell, !cell.value.isEmpty else { return "–" }
        return cell.value
    }
}

// MARK: - Effort grade

/// W4's three-level effort vocabulary, the thing that sits where Lectio put a weight.
struct EffortBadge: View {
    let effort: W4EffortGrade

    var body: some View {
        Label(effort.displayName, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundColor(Self.tint(for: effort))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Self.tint(for: effort).opacity(0.14))
            .clipShape(Capsule())
    }

    private var symbol: String {
        switch effort {
        case .meets: return "checkmark.circle.fill"
        case .almostMeets: return "circle.lefthalf.filled"
        case .doesNotMeet: return "exclamationmark.circle.fill"
        }
    }

    static func tint(for effort: W4EffortGrade) -> Color {
        switch effort {
        case .meets: return .green
        case .almostMeets: return .orange
        case .doesNotMeet: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GradesView(
            student: Student(
                studentId: "nc26abcd",
                name: "Preview Student"
            )
        )
    }
}
