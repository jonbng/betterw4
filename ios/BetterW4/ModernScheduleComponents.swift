//
//  ModernScheduleComponents.swift
//  BetterW4
//
//  The "Professional" calendar style: an hour ruler with flat, tinted blocks, the way W4's own
//  `#timetable` grid reads.
//
//  The ruler is drawn from the week's `tt_start_hour`/`tt_end_hour` (7…22 in every capture) rather
//  than a hardcoded school day, and blocks are placed at one point per minute below the timeline's
//  origin — the same geometry `TimelineListView` uses, so the two styles never disagree about
//  where 10:15 is.
//

import SwiftUI
import UIKit

// MARK: - Timeline

struct ModernTimelineListView: View {
    let displayDate: Date
    let events: [TimetableEvent]
    /// `tt_start_hour` of the week this day belongs to.
    var gridStartHour: Int = W4TimetableGeometry.defaultStartHour
    /// `tt_end_hour` of the week this day belongs to.
    var gridEndHour: Int = W4TimetableGeometry.defaultEndHour
    /// Shared Oslo clock with the header countdown. `nil` hides the now-line.
    var now: Date? = TimeProvider.now
    var onEventTapped: ((TimetableEvent) -> Void)?
    var onAddAt: ((Date) -> Void)?

    /// Width of the hour-label gutter plus its spacing.
    private let gutterWidth: CGFloat = 58

    var body: some View {
        let layouts = calculateEventOverlapLayouts(for: events)
        let origin = ScheduleTimelineGeometry.originMinutes(startHour: gridStartHour, layouts: layouts)
        let contentHeight = ScheduleTimelineGeometry.contentHeight(layouts: layouts, originMinutes: origin)

        VStack(spacing: 0) {
            if layouts.isEmpty {
                ScheduleEmptyDayView(
                    onAdd: onAddAt.map { add in { add(CustomEvents.defaultStart(on: displayDate)) } }
                )
            } else {
                GeometryReader { geo in
                    let laneWidth = max(0, geo.size.width - gutterWidth)
                    ZStack(alignment: .topLeading) {
                        gridBackground(origin: origin, contentHeight: contentHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { (location: CGPoint) in
                                add(at: location, origin: origin)
                            }

                        ForEach(layouts) { layout in
                            block(for: layout, in: layouts, origin: origin, laneWidth: laneWidth)
                        }

                        nowLine(at: now, origin: origin)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: contentHeight)
                .padding(.vertical, 8)

                Color.clear.frame(height: 80)
            }
        }
    }

    private func add(at location: CGPoint, origin: Int) {
        guard let onAddAt else { return }
        let minutes = origin + Int((location.y / ScheduleTimelineGeometry.pointsPerMinute).rounded())
        let snapped = ((max(0, minutes) + 7) / 15) * 15
        let upper = max(gridStartHour * 60, (gridEndHour - 1) * 60)
        let clamped = min(max(snapped, gridStartHour * 60), upper)
        onAddAt(W4Dates.date(onDayOf: displayDate, minutesFromMidnight: clamped))
    }

    // MARK: Grid

    @ViewBuilder
    private func gridBackground(origin: Int, contentHeight: CGFloat) -> some View {
        let firstHour = origin / 60
        // One line per hour from the origin down to whichever comes later: the end of the last
        // block, or W4's own `tt_end_hour`.
        let lastHour = max(gridEndHour, firstHour + Int((contentHeight / ScheduleTimelineGeometry.pointsPerMinute) / 60) + 1)
        let hours = Array(firstHour...max(firstHour, lastHour))

        ZStack(alignment: .top) {
            Color.clear.frame(height: contentHeight)
            ForEach(hours, id: \.self) { hour in
                HourGridLine(hour: hour, originMinutes: origin)
            }
        }
    }

    // MARK: Blocks

    @ViewBuilder
    private func block(
        for layout: EventLayoutInfo,
        in layouts: [EventLayoutInfo],
        origin: Int,
        laneWidth: CGFloat
    ) -> some View {
        let offsetFromTop = CGFloat(layout.startMinutes - origin) * ScheduleTimelineGeometry.pointsPerMinute
        let height = ScheduleTimelineGeometry.visualHeight(of: layout, among: layouts)

        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: gutterWidth)

            ModernScheduleCard(event: layout.event, compact: height < 28)
                .frame(width: max(0, laneWidth * layout.widthFraction - 4), height: height)
                .offset(x: laneWidth * layout.xFraction + 2)
                .contentShape(Rectangle())
                .onTapGesture { onEventTapped?(layout.event) }
                .frame(width: laneWidth, height: height, alignment: .topLeading)
        }
        .frame(height: height)
        .offset(y: offsetFromTop)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Now line

    @ViewBuilder
    private func nowLine(at instant: Date?, origin: Int) -> some View {
        if let instant, W4Dates.isSameDay(displayDate, instant),
           let offsetY = ScheduleTimelineGeometry.offset(
               forMinutesFromMidnight: W4Dates.minutesFromMidnight(instant),
               originMinutes: origin
           ) {
            HStack(alignment: .center, spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .offset(x: 3)
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 1.5)
            }
            .offset(y: offsetY)
            .padding(.leading, 52)
        }
    }
}

// MARK: - Hour ruler

struct HourGridLine: View {
    let hour: Int
    /// Minutes from Oslo midnight at the top of the timeline.
    let originMinutes: Int

    var body: some View {
        if let offset = ScheduleTimelineGeometry.offset(
            forMinutesFromMidnight: hour * 60,
            originMinutes: originMinutes
        ) {
            HStack(alignment: .top, spacing: 10) {
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.8))
                    .monospacedDigit()
                    .frame(width: 48, alignment: .trailing)
                    .offset(y: -7)
                Rectangle()
                    .fill(Color(UIColor.separator).opacity(0.4))
                    .frame(height: 1)
            }
            .offset(y: offset)
        }
    }
}

// MARK: - Card

struct ModernScheduleCard: View {
    let event: TimetableEvent
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settingsStore = SettingsStore.shared

    private var themeColor: Color {
        event.accentColor(useSubjectColors: settingsStore.useSubjectColors)
    }

    private var isCancelled: Bool { event.status == .cancelled }

    private var cardBackgroundColor: Color {
        if isCancelled {
            return Color(colorScheme == .dark ? UIColor.systemGray4 : UIColor.systemGray6)
        }
        let surface = Color(colorScheme == .dark ? UIColor.systemGray6 : UIColor.systemBackground)
        return surface.tinted(with: themeColor, amount: colorScheme == .dark ? 0.24 : 0.18)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: compact ? 8 : 15, style: .continuous)
                .fill(cardBackgroundColor)

            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(isCancelled ? Color.clear : themeColor)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, compact ? 4 : 10)
                    .padding(.leading, 6)

                VStack(alignment: .leading, spacing: compact ? 0 : 4) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(event.displayTitle)
                            .font(.system(size: compact ? 12 : 15, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(compact ? 0.75 : 1)
                            .strikethrough(isCancelled)

                        Spacer(minLength: 4)

                        if !compact {
                            Image(systemName: event.iconName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(themeColor.opacity(0.85))
                        }
                    }

                    if !compact, let detail = event.locationLine {
                        Text(detail)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if !compact {
                        Spacer(minLength: 0)
                    }
                }
                .padding(.top, compact ? 1 : 12)
                .padding(.bottom, compact ? 1 : 4)
                .padding(.leading, 10)
                .padding(.trailing, compact ? 8 : 12)
            }

            if !compact, event.status != .normal {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isCancelled ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(isCancelled ? .red : .orange)
                            .padding(6)
                    }
                    Spacer()
                }
            }
        }
        .opacity(isCancelled ? 0.5 : 1)
    }
}
