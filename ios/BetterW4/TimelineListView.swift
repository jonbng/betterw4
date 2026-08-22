//
//  TimelineListView.swift
//  BetterW4
//
//  The "Standard" calendar style: colourful subject cards on a time gutter.
//
//  Blocks are positioned absolutely at one point per minute below the timeline's origin
//  (`ScheduleTimelineGeometry`), which is derived from the week's own `tt_start_hour`. The now-line
//  is drawn from the same Oslo clock as the header countdown (`TimeProvider.now`, ticked on the
//  minute) — never from W4's `#current_time`, which was written by JavaScript in the browser
//  before the page was captured and would pin the line to 13:34 forever (plan D-10).
//

import SwiftUI

struct TimelineListView: View {
    let displayDate: Date
    let events: [TimetableEvent]
    /// `tt_start_hour` of the week this day belongs to.
    var gridStartHour: Int = W4TimetableGeometry.defaultStartHour
    /// Shared Oslo clock with the header countdown. Must not be `TimelineView`'s
    /// `context.date`, which ignores `SIMULATED_DATE` and can disagree by a minute.
    /// `nil` hides the now-line (off-today pages).
    var now: Date? = TimeProvider.now
    var onEventTapped: ((TimetableEvent) -> Void)?
    var onAddAt: ((Date) -> Void)?

    @ObservedObject private var settingsStore = SettingsStore.shared

    /// Time-label gutter plus the HStack spacing in `TimelineRow`.
    private let gutterAndSpacing: CGFloat = 48 + 16

    var body: some View {
        let layouts = calculateEventOverlapLayouts(for: events)
        let origin = ScheduleTimelineGeometry.originMinutes(startHour: gridStartHour, layouts: layouts)
        let contentHeight = ScheduleTimelineGeometry.contentHeight(
            layouts: layouts,
            originMinutes: origin
        )

        VStack(spacing: 0) {
            if layouts.isEmpty {
                ScheduleEmptyDayView(
                    onAdd: onAddAt.map { add in { add(CustomEvents.defaultStart(on: displayDate)) } }
                )
            } else {
                GeometryReader { geo in
                    let laneWidth = max(0, geo.size.width - gutterAndSpacing)
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { (location: CGPoint) in
                                guard let onAddAt else { return }
                                let minutes = origin + Int((location.y / ScheduleTimelineGeometry.pointsPerMinute).rounded())
                                let snapped = ((max(0, minutes) + 7) / 15) * 15
                                onAddAt(W4Dates.date(onDayOf: displayDate, minutesFromMidnight: snapped))
                            }
                        ForEach(layouts) { layout in
                            row(for: layout, in: layouts, origin: origin, laneWidth: laneWidth)
                        }

                        // "Now" line — only on the day it is actually now.
                        nowLine(at: now, origin: origin)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: contentHeight)

                Color.clear.frame(height: 80)
            }
        }
    }

    @ViewBuilder
    private func row(
        for layout: EventLayoutInfo,
        in layouts: [EventLayoutInfo],
        origin: Int,
        laneWidth: CGFloat
    ) -> some View {
        let event = layout.event
        let offsetFromTop = CGFloat(layout.startMinutes - origin) * ScheduleTimelineGeometry.pointsPerMinute
        let height = ScheduleTimelineGeometry.visualHeight(of: layout, among: layouts)
        let cardStyle: CardLayoutStyle = {
            if height < 22 { return .micro }
            if height < 80 { return .compact }
            return .iconTopLeft
        }()

        TimelineRow(
            startTime: event.start.map(W4Dates.formatTime) ?? "",
            endTime: event.end.map(W4Dates.formatTime) ?? "",
            height: height,
            laneWidth: laneWidth,
            widthFraction: layout.widthFraction,
            horizontalOffset: layout.xFraction
        ) {
            ScheduleCard(
                title: event.displayTitle,
                subtitle: event.subtitleLine ?? "",
                iconName: event.iconName,
                themeColor: event.accentColor(useSubjectColors: settingsStore.useSubjectColors),
                layoutStyle: cardStyle,
                status: event.status,
                teacherInitials: Self.initials(from: event.teacher)
            )
            .contentShape(Rectangle())
            .onTapGesture { onEventTapped?(event) }
        }
        .offset(y: offsetFromTop)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
    var onAdd: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)
            Text(message)
                .font(.headline)
                .foregroundColor(.secondary)
            if let onAdd {
                Button("Add an event", action: onAdd)
                    .font(.subheadline.weight(.semibold))
            }
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
    let laneWidth: CGFloat
    let widthFraction: CGFloat
    let horizontalOffset: CGFloat
    let content: Content

    init(
        startTime: String,
        endTime: String,
        height: CGFloat,
        laneWidth: CGFloat,
        widthFraction: CGFloat = 1.0,
        horizontalOffset: CGFloat = 0.0,
        @ViewBuilder content: () -> Content
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.height = height
        self.laneWidth = laneWidth
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

            content
                .frame(width: max(0, laneWidth * widthFraction), height: height, alignment: .top)
                .offset(x: laneWidth * horizontalOffset)
                .frame(width: laneWidth, height: height, alignment: .topLeading)
        }
    }
}

// MARK: - Card

enum CardLayoutStyle {
    case standard
    case iconTopLeft
    /// Horizontal layout for short lessons.
    case compact
    /// Title-only strip for 15-minute breaks that must keep their real height.
    case micro
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
            switch layoutStyle {
            case .micro:
                microBody
            case .compact:
                compactBody
            case .standard, .iconTopLeft:
                tallBody
            }
        }
    }

    @ViewBuilder
    private var accentBar: some View {
        if !isCancelled {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(themeColor)
                .frame(width: 3)
                .padding(.vertical, layoutStyle == .micro ? 3 : 8)
                .padding(.leading, 5)
        }
    }

    private var microBody: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isCancelled ? .secondary : .primary)
                .strikethrough(isCancelled)
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            Spacer(minLength: 2)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 1)
        .background(backgroundColorForStatus)
        .overlay(alignment: .leading) { accentBar }
        .cornerRadius(8, antialiased: true)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColorForStatus, lineWidth: status == .changed ? 1.5 : 0.5)
        )
    }

    private var compactBody: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundColor(isCancelled ? .gray : themeColor.opacity(0.85))
                .frame(width: 22)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isCancelled ? .secondary : .primary)
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
                    .foregroundColor(.secondary)
                    .minimumScaleFactor(0.85)
                    .lineLimit(1)
            }

            statusBadge
        }
        .frame(maxHeight: .infinity)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(backgroundColorForStatus)
        .overlay(alignment: .leading) { accentBar }
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
                    .foregroundColor(isCancelled ? .gray : themeColor.opacity(0.85))

                Spacer()

                if let teacherInitials, !teacherInitials.isEmpty {
                    teacherBadge(initials: teacherInitials, size: 24)
                }

                statusBadge
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(isCancelled ? .secondary : .primary)
                    .strikethrough(isCancelled)
                    .minimumScaleFactor(0.9)
                    .lineLimit(2)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .minimumScaleFactor(0.9)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .background(backgroundColorForStatus)
        .overlay(alignment: .leading) { accentBar }
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
            .foregroundColor(.secondary)
            .frame(width: size, height: size)
            .background(Color(UIColor.tertiarySystemFill))
            .clipShape(Circle())
    }

    private var backgroundColorForStatus: Color {
        switch status {
        case .cancelled:
            return Color(UIColor.secondarySystemBackground).opacity(0.4)
        case .changed, .moved, .normal:
            let surface = Color(colorScheme == .dark ? UIColor.systemGray6 : UIColor.systemBackground)
            return surface.tinted(with: themeColor, amount: colorScheme == .dark ? 0.24 : 0.18)
        }
    }

    private var borderColorForStatus: Color {
        switch status {
        case .cancelled:
            return Color.secondary.opacity(0.3)
        case .changed, .moved:
            return themeColor.opacity(colorScheme == .dark ? 0.55 : 0.35)
        case .normal:
            return Color(UIColor.separator).opacity(colorScheme == .dark ? 0.5 : 0.35)
        }
    }
}
