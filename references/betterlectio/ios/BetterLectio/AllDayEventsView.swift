//
//  AllDayEventsView.swift
//  BetterLectio
//

import SwiftUI

/// Strip of all-day ("Hele dagen") event chips rendered above the timed timeline,
/// matching the affordance Apple/Google Calendar use for events without a clock range.
struct AllDayEventsView: View {
    let events: [ScheduleEvent]
    var onEventTapped: ((ScheduleEvent) -> Void)?

    var body: some View {
        if events.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hele dagen")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                HStack(spacing: 8) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        AllDayEventChip(event: event, stretch: index == events.count - 1)
                            .onTapGesture { onEventTapped?(event) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
    }
}

private struct AllDayEventChip: View {
    let event: ScheduleEvent
    var stretch: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settingsStore = SettingsStore.shared

    private var themeColor: Color { settingsStore.accentColor(for: event) }
    private var displayTitle: String { SubjectMapper.displayName(for: event.title) }
    private var cancelled: Bool { event.status == .cancelled }

    private var backgroundColor: Color {
        if cancelled {
            return Color(colorScheme == .dark ? UIColor.systemGray4 : UIColor.systemGray6)
        }
        return themeColor.opacity(colorScheme == .dark ? 0.32 : 0.18)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: SubjectMapper.iconName(for: event.title))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.55))

            Text(displayTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))
                .strikethrough(cancelled)
                .lineLimit(1)

            if let room = event.room, !room.isEmpty {
                Text("•")
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.4))
                Text(room)
                    .font(.system(size: 12))
                    .foregroundColor(.primary.opacity(0.55))
                    .lineLimit(1)
            }

            if event.status == .changed {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: stretch ? .infinity : nil, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        )
        .opacity(cancelled ? 0.6 : 1)
    }
}
