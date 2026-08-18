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

// MARK: - Colour blending

private extension Color {
    /// Blends toward `other`. `fraction` = how much of `other` to mix in (0 = self, 1 = other).
    func blended(with fraction: CGFloat, of other: Color) -> Color {
        let base = UIColor(self)
        let target = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        base.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        target.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            red: Double(r1 + (r2 - r1) * fraction),
            green: Double(g1 + (g2 - g1) * fraction),
            blue: Double(b1 + (b2 - b1) * fraction),
            opacity: 1
        )
    }
}

// MARK: - Timeline

struct ModernTimelineListView: View {
    let displayDate: Date
    let events: [TimetableEvent]
    /// `tt_start_hour` of the week this day belongs to.
    var gridStartHour: Int = W4TimetableGeometry.defaultStartHour
    /// `tt_end_hour` of the week this day belongs to.
    var gridEndHour: Int = W4TimetableGeometry.defaultEndHour
    var onEventTapped: ((TimetableEvent) -> Void)?

    /// Width of the hour-label gutter plus its spacing.
    private let gutterWidth: CGFloat = 58

    var body: some View {
        let layouts = calculateEventOverlapLayouts(for: events)
        let origin = ScheduleTimelineGeometry.originMinutes(startHour: gridStartHour, layouts: layouts)
        let contentHeight = ScheduleTimelineGeometry.contentHeight(layouts: layouts, originMinutes: origin)

        VStack(spacing: 0) {
            if layouts.isEmpty {
                ScheduleEmptyDayView()
            } else {
                ZStack(alignment: .top) {
                    gridBackground(origin: origin, contentHeight: contentHeight)

                    ForEach(layouts) { layout in
                        block(for: layout, origin: origin)
                    }

                    TimelineView(.periodic(from: TimeProvider.now, by: 60)) { context in
                        nowLine(at: context.date, origin: origin)
                    }
                    .allowsHitTesting(false)
                }
                .padding(.vertical, 8)

                Color.clear.frame(height: 80)
            }
        }
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
    private func block(for layout: EventLayoutInfo, origin: Int) -> some View {
        let offsetFromTop = CGFloat(layout.startMinutes - origin) * ScheduleTimelineGeometry.pointsPerMinute
        let height = max(
            ScheduleTimelineGeometry.minimumBlockHeight,
            CGFloat(layout.endMinutes - layout.startMinutes) * ScheduleTimelineGeometry.pointsPerMinute
        )
        let widthFraction = 1.0 / CGFloat(layout.totalColumns)
        let horizontalOffset = CGFloat(layout.column) / CGFloat(layout.totalColumns)

        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: gutterWidth)

            GeometryReader { geometry in
                let contentWidth = geometry.size.width * widthFraction
                let offsetX = geometry.size.width * horizontalOffset

                ModernScheduleCard(event: layout.event)
                    .frame(width: max(0, contentWidth - 4), height: height)
                    .offset(x: offsetX + 2)
                    .contentShape(Rectangle())
                    .onTapGesture { onEventTapped?(layout.event) }
            }
        }
        .frame(height: height)
        .offset(y: offsetFromTop)
    }

    // MARK: Now line

    @ViewBuilder
    private func nowLine(at instant: Date, origin: Int) -> some View {
        if W4Dates.isSameDay(displayDate, instant),
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

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settingsStore = SettingsStore.shared

    private var themeColor: Color {
        event.accentColor(useSubjectColors: settingsStore.useSubjectColors)
    }

    private var isCancelled: Bool { event.status == .cancelled }

    /// Light mode tints toward white; dark mode tints toward near-black so blocks stay saturated.
    private var cardBackgroundColor: Color {
        if isCancelled {
            return Color(colorScheme == .dark ? UIColor.systemGray4 : UIColor.systemGray6)
        }
        let neutral: Color = colorScheme == .dark ? Color(UIColor.systemGray6) : .white
        return themeColor.blended(with: colorScheme == .dark ? 0.6 : 0.85, of: neutral)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(cardBackgroundColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    Text(event.displayTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary.opacity(0.6))
                        .lineLimit(1)
                        .strikethrough(isCancelled)

                    Spacer(minLength: 4)

                    Image(systemName: event.iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary.opacity(0.4))
                }

                if let detail = event.locationLine {
                    Text(detail)
                        .font(.system(size: 13, weight: .light))
                        .foregroundColor(.primary.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .padding(.bottom, 4)
            .padding(.leading, 14)
            .padding(.trailing, 12)

            if event.status != .normal {
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
