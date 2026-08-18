//
//  SubjectGradeDetailView.swift
//  BetterW4
//
//  The context-menu preview behind a row of `GradesView`: one subject across every column W4 sent.
//
//  IB 1–7. The chart's y-axis is 1…7 with a tick per grade — not the Danish 7-point scale's
//  -3/00/02/4/7/10/12 — and cells W4 renders as free text (a predicted "A", an "N/A") are listed
//  but never plotted, because plotting them would require inventing a number for them.
//
//  There is no weight row. W4 has no weights; where Lectio printed "Vægt" W4 prints an *effort
//  grade*, and that is what this shows instead.
//

import SwiftUI
import Charts

struct SubjectGradeDetailView: View {
    let row: W4GradeRow
    let columns: [W4GradeColumn]

    /// One column's cell for this subject, plus the IB number when the cell actually holds one.
    struct DataPoint: Identifiable {
        let column: W4GradeColumn
        /// `1...7`, or `nil` when the cell is free text.
        let grade: Int?
        let rawValue: String
        let effort: W4EffortGrade?

        var id: String { column.id }
    }

    var data: [DataPoint] {
        columns.compactMap { column in
            guard let cell = row.cell(for: column.id) else { return nil }
            return DataPoint(
                column: column,
                grade: cell.ibGrade,
                rawValue: cell.value.isEmpty ? "–" : cell.value,
                effort: cell.effort
            )
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(row.displaySubject)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let teacher = row.teacher, !teacher.isEmpty {
                    Text(teacher)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 20)

            let plotted = data.filter { $0.grade != nil }

            if plotted.isEmpty {
                Text("No IB grades to chart")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Chart {
                    ForEach(plotted) { point in
                        if let grade = point.grade {
                            LineMark(
                                x: .value("Column", point.column.label),
                                y: .value("Grade", grade)
                            )
                            .foregroundStyle(Color.accentColor)

                            PointMark(
                                x: .value("Column", point.column.label),
                                y: .value("Grade", grade)
                            )
                            .foregroundStyle(Color.accentColor)
                            .annotation(position: .top) {
                                Text(point.rawValue)
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0.5...7.5)
                .chartYAxis {
                    AxisMarks(values: [1, 2, 3, 4, 5, 6, 7]) { value in
                        AxisGridLine()
                        if let grade = value.as(Int.self) {
                            AxisValueLabel { Text("\(grade)") }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                    }
                }
                .frame(height: 160)
                .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(data.enumerated()), id: \.element.id) { index, point in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(point.column.label)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if point.column.isAnticipated {
                                Image(systemName: "sparkles")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(point.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .frame(minWidth: 30, alignment: .trailing)
                        }

                        if let effort = point.effort {
                            EffortBadge(effort: effort)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)

                    if index < data.count - 1 {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(width: 320)
        .background(Color(UIColor.systemBackground))
    }
}
