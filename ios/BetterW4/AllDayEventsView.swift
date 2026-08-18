//
//  AllDayEventsView.swift
//  BetterW4
//
//  The strip above the timed timeline.
//
//  It holds two kinds of block: genuine all-day entries, and blocks W4 rendered without a usable
//  time. The second kind matters — no real `.period` element has ever been captured, so a block
//  whose pixel offset we cannot read must still appear somewhere rather than vanish.
//

import SwiftUI

struct AllDayEventsView: View {
    let events: [TimetableEvent]
    var onEventTapped: ((TimetableEvent) -> Void)?

    var body: some View {
        if events.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("All day")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(events) { event in
                            AllDayEventChip(event: event)
                                .onTapGesture { onEventTapped?(event) }
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

private struct AllDayEventChip: View {
    let event: TimetableEvent

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settingsStore = SettingsStore.shared

    private var themeColor: Color {
        event.accentColor(useSubjectColors: settingsStore.useSubjectColors)
    }

    private var isCancelled: Bool { event.status == .cancelled }

    private var backgroundColor: Color {
        if isCancelled {
            return Color(colorScheme == .dark ? UIColor.systemGray4 : UIColor.systemGray6)
        }
        return themeColor.opacity(colorScheme == .dark ? 0.32 : 0.18)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: event.iconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.55))

            Text(event.displayTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))
                .strikethrough(isCancelled)
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

            if event.status == .changed || event.status == .moved {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }

            if event.source == .extraAcademics {
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundColor(.primary.opacity(0.45))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        )
        .opacity(isCancelled ? 0.6 : 1)
    }
}
