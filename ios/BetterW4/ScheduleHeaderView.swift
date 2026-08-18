//
//  ScheduleHeaderView.swift
//  BetterW4
//
//  The one line above the timetable: what is running right now, or what starts within the hour.
//  It renders nothing at all when neither is true, so an empty afternoon does not carry a header
//  saying so.
//

import SwiftUI

struct ScheduleHeaderView: View {
    /// Subject name, already resolved through `SubjectMapper`.
    let subjectName: String?
    /// Room, when W4 gave the block one.
    let room: String?
    /// Minutes left of the running lesson, or minutes until the upcoming one starts.
    let minutesValue: Int?
    /// 0…1 through the running lesson. `nil` hides the bar.
    let progress: Double?
    /// True when `minutesValue` counts down to a start rather than to an end.
    var isUpcoming: Bool = false
    /// Subject colour of the lesson being described.
    var accent: Color = .blue

    var body: some View {
        if let subjectName, let minutesValue {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(subjectName)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(accent)
                            .lineLimit(1)

                        if let room, !room.isEmpty {
                            Text("•")
                                .font(.title3)
                                .fontWeight(.light)
                                .foregroundColor(.secondary)

                            Text(room)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                    }
                    .layoutPriority(0)

                    Spacer(minLength: 8)

                    Text(minutesText(minutesValue))
                        .layoutPriority(1)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .monospacedDigit()
                }

                // Progress bar only for a lesson that is actually running.
                if !isUpcoming, let progress {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(accent.opacity(0.15))
                                .frame(height: 6)

                            Capsule()
                                .fill(accent)
                                .frame(width: geometry.size.width * progress, height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .background(Color(UIColor.systemBackground))
        } else {
            Color.clear.frame(height: 0)
        }
    }

    private func minutesText(_ minutes: Int) -> String {
        let unit = minutes == 1 ? "minute" : "minutes"
        return isUpcoming ? "in \(minutes) \(unit)" : "\(minutes) \(unit) left"
    }
}
