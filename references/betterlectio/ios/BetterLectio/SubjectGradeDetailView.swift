//
//  SubjectGradeDetailView.swift
//  BetterLectio
//
//  Created by Antigravity on \(Date().timeIntervalSince1970)
//

import SwiftUI
import Charts

struct SubjectGradeDetailView: View {
    let entry: GradeEntry
    let columns: [GradeColumn]
    
    struct DataPoint: Identifiable {
        let column: GradeColumn
        let value: Double?
        let rawValue: String
        let weight: Double?
        
        var id: String { column.key }
    }
    
    var data: [DataPoint] {
        columns.compactMap { column in
            guard let cell = entry.cell(for: column.key) else { return nil }
            let normalized = cell.value
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return DataPoint(
                column: column,
                value: Double(normalized),
                rawValue: cell.value,
                weight: cell.weight
            )
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(entry.subject)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text(entry.hold)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)
            
            let chartData = data.filter { $0.value != nil }
            
            if chartData.isEmpty {
                Text("Ingen numeriske karakterer at vise i grafen")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Chart {
                    ForEach(chartData) { point in
                        if let value = point.value {
                            LineMark(
                                x: .value("Type", point.column.shortLabel),
                                y: .value("Karakter", value)
                            )
                            .foregroundStyle(Color.accentColor)
                            
                            PointMark(
                                x: .value("Type", point.column.shortLabel),
                                y: .value("Karakter", value)
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
                .chartYScale(domain: -4...13)
                .chartYAxis {
                    AxisMarks(values: [-3, 0, 2, 4, 7, 10, 12]) { value in
                        AxisGridLine()
                        if let intValue = value.as(Int.self) {
                            AxisValueLabel {
                                Text(intValue == 0 ? "00" : (intValue == 2 ? "02" : "\(intValue)"))
                            }
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
                    HStack {
                        Text(point.column.label)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let weight = point.weight, weight != 1.0 {
                            Text("Vægt: \(String(format: "%.2f", weight).replacingOccurrences(of: ".", with: ","))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(point.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 30, alignment: .trailing)
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
