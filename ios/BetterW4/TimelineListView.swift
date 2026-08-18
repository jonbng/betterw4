//
//  TimelineListView.swift
//  BetterW4
//
//  The "Standard" calendar style: colourful subject cards on a time gutter.
//
//  Blocks are positioned absolutely at one point per minute below the timeline's origin
//  (`ScheduleTimelineGeometry`), which is derived from the week's own `tt_start_hour`. The now-line
//  is drawn from `TimeProvider.now` read in Europe/Oslo — never from W4's `#current_time`, which
//  was written by JavaScript in the browser before the page was captured and would pin the line to
//  13:34 forever (plan D-10).
//

import SwiftUI

struct TimelineListView: View {
    let displayDate: Date
    let events: [TimetableEvent]
    /// `tt_start_hour` of the week this day belongs to.
    var gridStartHour: Int = W4TimetableGeometry.defaultStartHour
    var onEventTapped: ((TimetableEvent) -> Void)?

    @ObservedObject private var settingsStore = SettingsStore.shared

    var body: some View {
        let layouts = calculateEventOverlapLayouts(for: events)
        let origin = ScheduleTimelineGeometry.originMinutes(startHour: gridStartHour, layouts: layouts)

        VStack(spacing: 0) {
            if layouts.isEmpty {
                ScheduleEmptyDayView()
            } else {
                ZStack(alignment: .top) {
                    Color.clear
                        .frame(height: ScheduleTimelineGeometry.contentHeight(
                            layouts: layouts,
                            originMinutes: origin
                        ))

                    ForEach(layouts) { layout in
                        row(for: layout, origin: origin)
                    }

                    // "Now" line — only on the day it is actually now.
                    TimelineView(.periodic(from: TimeProvider.now, by: 60)) { context in
                        nowLine(at: context.date, origin: origin)
                    }
                    .allowsHitTesting(false)
                }

                Color.clear.frame(height: 80)
            }
        }
    }

    @ViewBuilder
    private func row(for layout: EventLayoutInfo, origin: Int) -> some View {
        let event = layout.event
        let offsetFromTop = CGFloat(layout.startMinutes - origin) * ScheduleTimelineGeometry.pointsPerMinute
        let height = max(
            ScheduleTimelineGeometry.minimumBlockHeight,
            CGFloat(layout.endMinutes - layout.startMinutes) * ScheduleTimelineGeometry.pointsPerMinute
        )
        let widthFraction = 1.0 / CGFloat(layout.totalColumns)
        let horizontalOffset = CGFloat(layout.column) / CGFloat(layout.totalColumns)

        TimelineRow(
            startTime: event.start.map(W4Dates.formatTime) ?? "",
            endTime: event.end.map(W4Dates.formatTime) ?? "",
            height: height,
            widthFraction: widthFraction,
            horizontalOffset: horizontalOffset
        ) {
            ScheduleCard(
                title: event.displayTitle,
                subtitle: event.subtitleLine ?? "",
                iconName: event.iconName,
                themeColor: event.accentColor(useSubjectColors: settingsStore.useSubjectColors),
                layoutStyle: height < 80 ? .compact : .iconTopLeft,
                status: event.status,
                teacherInitials: Self.initials(from: event.teacher)
            )
            .contentShape(Rectangle())
            .onTapGesture { onEventTapped?(event) }
        }
        .offset(y: offsetFromTop)
    }

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
                    .frame(width: 8, height: 8)

                Rectangle()
                    .fill(Color.red)
                    .frame(height: 2)
            }
            .offset(y: offsetY)
            .padding(.leading, 48)
        }
    }

    /// Initials for the small teacher chip. W4 serves no lesson-block portrait, so a monogram is
    /// the whole affordance.
    static func initials(from name: String?) -> String? {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Empty day

/// Shown when W4 rendered no blocks for the day at all.
struct ScheduleEmptyDayView: View {
    var message: String = "No lessons"

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)
            Text(message)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Row chrome

struct TimelineRow<Content: View>: View {
    let startTime: String
    let endTime: String
    let height: CGFloat
    let widthFraction: CGFloat
    let horizontalOffset: CGFloat
    let content: Content

    init(
        startTime: String,
        endTime: String,
        height: CGFloat,
        widthFraction: CGFloat = 1.0,
        horizontalOffset: CGFloat = 0.0,
        @ViewBuilder content: () -> Content
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.height = height
        self.widthFraction = widthFraction
        self.horizontalOffset = horizontalOffset
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .trailing, spacing: 4) {
                Text(startTime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Rectangle()
                    .fill(Color(UIColor.separator).opacity(0.5))
                    .frame(width: 1)
                    .padding(.trailing, 7)

                Text(endTime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 48)
            .frame(height: height)

            GeometryReader { geometry in
                let contentWidth = geometry.size.width * widthFraction
                let offsetX = geometry.size.width * horizontalOffset

                content
                    .frame(width: contentWidth, height: height, alignment: .top)
                    .offset(x: offsetX)
            }
            .frame(height: height)
        }
    }
}

// MARK: - Card

enum CardLayoutStyle {
    case standard
    case iconTopLeft
    /// Horizontal layout for short lessons.
    case compact
}

struct ScheduleCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let themeColor: Color
    var layoutStyle: CardLayoutStyle = .standard
    var status: EventStatus = .normal
    var teacherInitials: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var isCancelled: Bool { status == .cancelled }

    var body: some View {
        Group {
            if layoutStyle == .compact {
                compactBody
            } else {
                tallBody
            }
        }
    }

    private var compactBody: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundColor(isCancelled ? .gray : themeColor.opacity(themeIconOpacity))
                .frame(width: 22)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isCancelled ? .secondary : themeColor.opacity(themeTitleOpacity))
                .strikethrough(isCancelled)
                .minimumScaleFactor(0.85)
                .lineLimit(1)

            Spacer(minLength: 4)

            if let teacherInitials, !teacherInitials.isEmpty {
                teacherBadge(initials: teacherInitials, size: 20)
            }

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isCancelled ? .secondary : themeColor.opacity(themeSubtitleOpacity))
                    .minimumScaleFactor(0.85)
                    .lineLimit(1)
            }

            statusBadge
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColorForStatus)
        .cornerRadius(12, antialiased: true)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColorForStatus, lineWidth: status == .changed ? 2 : 1)
        )
    }

    private var tallBody: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundColor(isCancelled ? .gray : themeColor.opacity(themeIconOpacity))

                Spacer()

                if let teacherInitials, !teacherInitials.isEmpty {
                    teacherBadge(initials: teacherInitials, size: 24)
                }

                statusBadge
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(isCancelled ? .secondary : themeColor.opacity(themeTitleOpacity))
                    .strikethrough(isCancelled)
                    .minimumScaleFactor(0.9)
                    .lineLimit(2)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(isCancelled ? .secondary : themeColor.opacity(themeSubtitleOpacity))
                        .minimumScaleFactor(0.9)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(12)
        .background(backgroundColorForStatus)
        .cornerRadius(16, antialiased: true)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColorForStatus, lineWidth: status == .changed ? 2 : 1)
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
        case .changed, .moved:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundColor(.orange)
        case .normal:
            EmptyView()
        }
    }

    private func teacherBadge(initials: String, size: CGFloat) -> some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(themeColor.opacity(colorScheme == .dark ? 0.72 : 0.6))
            .clipShape(Circle())
    }

    private var themeIconOpacity: Double { colorScheme == .dark ? 0.78 : 0.6 }
    private var themeTitleOpacity: Double { colorScheme == .dark ? 0.95 : 0.9 }
    private var themeSubtitleOpacity: Double { colorScheme == .dark ? 0.82 : 0.7 }

    private var backgroundColorForStatus: Color {
        switch status {
        case .cancelled:
            return Color(UIColor.secondarySystemBackground).opacity(0.4)
        case .changed, .moved:
            return themeColor.opacity(colorScheme == .dark ? 0.28 : 0.15)
        case .normal:
            return themeColor.opacity(colorScheme == .dark ? 0.22 : 0.1)
        }
    }

    private var borderColorForStatus: Color {
        switch status {
        case .cancelled:
            return Color.secondary.opacity(0.3)
        case .changed, .moved:
            return themeColor.opacity(colorScheme == .dark ? 0.55 : 0.4)
        case .normal:
            return themeColor.opacity(colorScheme == .dark ? 0.38 : 0.2)
        }
    }
}
