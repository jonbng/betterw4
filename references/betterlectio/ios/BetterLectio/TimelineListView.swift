import SwiftUI

struct TimelineListView: View {
    let displayDate: Date
    let events: [ScheduleEvent]
    var onEventTapped: ((ScheduleEvent) -> Void)?
    let scale: CGFloat = 1 // Points per minute (increased for better visibility)
    var gymId: Int? = nil

    @ObservedObject private var settingsStore = SettingsStore.shared

    private let calendar = Calendar.current

    // Reference time for absolute positioning (always 8:10 AM)
    private var referenceTime: Int {
        return 8 * 60 + 10 // 8:10 AM - standard school start time
    }

    private var eventLayouts: [EventLayoutInfo] {
        calculateEventOverlapLayouts(for: events, timeToMinutes: timeToMinutes)
    }

    var body: some View {
        VStack(spacing: 0) {
            if events.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Ingen lektioner i dag")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                // Use absolute positioning
                ZStack(alignment: .top) {
                    // Container to establish coordinate space
                    Color.clear
                        .frame(height: calculateTotalHeight())

                    // Position each event absolutely with overlap handling
                    ForEach(eventLayouts, id: \.event.id) { layout in
                        let event = layout.event
                        let offsetFromTop = calculateOffset(for: event)
                        let duration = calculateDuration(start: event.startTime, end: event.endTime)
                        let height = max(40, CGFloat(duration) * scale)

                        // Calculate width fraction and horizontal offset for overlapping events
                        let widthFraction = 1.0 / CGFloat(layout.totalColumns)
                        let horizontalOffset = CGFloat(layout.column) / CGFloat(layout.totalColumns)

                        TimelineRow(
                            startTime: formatTime(event.startTime),
                            endTime: formatTime(event.endTime),
                            height: height,
                            widthFraction: widthFraction,
                            horizontalOffset: horizontalOffset,
                            content: {
                                ScheduleCard(
                                    title: SubjectMapper.displayName(for: event.title),
                                    subtitle: standardScheduleCardSubtitle(for: event),
                                    iconName: SubjectMapper.iconName(for: event.title),
                                    themeColor: settingsStore.accentColor(for: event),
                                    layoutStyle: height < 80 ? .compact : .iconTopLeft,
                                    status: event.status,
                                    teacherImageURL: teacherImageURL(for: event),
                                    teacherInitials: teacherInitials(from: event.teacher)
                                )
                                .onTapGesture {
                                    onEventTapped?(event)
                                }
                            }
                        )
                        .offset(y: offsetFromTop)
                    }

                    // "Now" line – shows current time when viewing today
                    if calendar.isDateInToday(displayDate) {
                        TimelineView(.periodic(from: TimeProvider.now, by: 60)) { context in
                            nowLine(at: context.date)
                        }
                        .allowsHitTesting(false)
                    }
                }

                Color.clear.frame(height: 80)
            }
        }
    }

    // Calculate offset from top for absolute positioning
    private func calculateOffset(for event: ScheduleEvent) -> CGFloat {
        let eventStartMinutes = timeToMinutes(event.startTime)
        let minutesFromReference = eventStartMinutes - referenceTime
        return CGFloat(minutesFromReference) * scale
    }

    // Calculate total height needed for all events
    private func calculateTotalHeight() -> CGFloat {
        guard let lastLayout = eventLayouts.last else { return 0 }
        let lastEvent = lastLayout.event

        // Calculate offset to last event
        let lastEventOffset = calculateOffset(for: lastEvent)

        // Calculate actual rendered height of last event (including min height)
        let duration = calculateDuration(start: lastEvent.startTime, end: lastEvent.endTime)
        let lastEventHeight = max(40, CGFloat(duration) * scale)

        // Total height = offset to last event + height of last event
        return lastEventOffset + lastEventHeight + 20 // Add 20pt padding
    }

    // Convert time string to minutes since midnight
    private func timeToMinutes(_ time: String) -> Int {
        let separator = time.contains(":") ? ":" : "."
        let parts = time.split(separator: Character(separator)).compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
    }

    private func calculateDuration(start: String, end: String) -> Int {
        timeToMinutes(end) - timeToMinutes(start)
    }

    // Convert "08:10" to "08.10" for display
    private func formatTime(_ time: String) -> String {
        time.replacingOccurrences(of: ":", with: ".")
    }

    // Format time range for display
    private func formatTimeRange(_ start: String, _ end: String) -> String {
        "\(formatTime(start)) - \(formatTime(end))"
    }

    private func standardScheduleCardSubtitle(for event: ScheduleEvent) -> String {
        if let room = event.room?.trimmingCharacters(in: .whitespacesAndNewlines), !room.isEmpty {
            return room
        }
        return formatTimeRange(event.startTime, event.endTime)
    }

    // Build teacher image URL from teacherId and gymId
    private func teacherImageURL(for event: ScheduleEvent) -> URL? {
        guard let teacherId = event.teacherId,
              let gymId = gymId else { return nil }
        return URL(string: "https://www.lectio.dk/lectio/\(gymId)/GetImage.aspx?pictureid=\(teacherId)&fullsize=1")
    }

    // Extract initials from teacher name
    private func teacherInitials(from teacherName: String?) -> String? {
        guard let name = teacherName, !name.isEmpty else { return nil }
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// "Now" indicator line – horizontal line at current time
    @ViewBuilder
    private func nowLine(at date: Date) -> some View {
        let currentMinutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let offsetY = CGFloat(currentMinutes - referenceTime) * scale

        if offsetY >= 0 {
            HStack(alignment: .center, spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)

                Rectangle()
                    .fill(Color.red)
                    .frame(height: 2)
            }
            .offset(y: offsetY)
            .padding(.leading, 48) // Align with content (time column width)
        }
    }
}

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
            // Time Column
            VStack(alignment: .trailing, spacing: 4) {
                Text(startTime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                // Visual separator line
                Rectangle()
                    .fill(Color(UIColor.separator).opacity(0.5))
                    .frame(width: 1)
                    .padding(.trailing, 7)

                Text(endTime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .frame(width: 48)
            .frame(height: height)

            // Content Column with width and offset support
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

enum CardLayoutStyle {
    case standard
    case iconTopLeft
    case compact // Horizontal layout for short lessons
}

struct ScheduleCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let themeColor: Color
    var layoutStyle: CardLayoutStyle = .standard
    var status: EventStatus = .normal
    var teacherImageURL: URL? = nil
    var teacherInitials: String? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if layoutStyle == .compact {
                // Compact horizontal layout for short lessons
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 18))
                        .foregroundColor(status == .cancelled ? .gray : themeColor.opacity(themeIconOpacity))
                        .frame(width: 22)

                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(status == .cancelled ? .secondary : themeColor.opacity(themeTitleOpacity))
                        .strikethrough(status == .cancelled)
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)

                    Spacer()

                    // Teacher avatar for compact layout
                    if let url = teacherImageURL {
                        RateLimitedAvatarImage(url: url, size: 20) {
                            teacherPlaceholder(size: 20)
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(status == .cancelled ? .secondary : themeColor.opacity(themeSubtitleOpacity))
                        .minimumScaleFactor(0.85)

                    if status != .normal {
                        statusBadge
                    }
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
            } else {
                // Vertical layout for normal/tall lessons - allows icon and text to overlap
                ZStack(alignment: .topLeading) {
                    // Icon and status badge at top
                    HStack(alignment: .top) {
                        Image(systemName: iconName)
                            .font(.title3)
                            .foregroundColor(status == .cancelled ? .gray : themeColor.opacity(themeIconOpacity))

                        Spacer()

                        // Teacher avatar in top right
                        if let url = teacherImageURL {
                            RateLimitedAvatarImage(url: url, size: 24) {
                                teacherPlaceholder(size: 24)
                            }
                        }

                        // Status badge
                        if status != .normal {
                            statusBadge
                        }
                    }

                    // Title and subtitle - positioned at bottom, can overlap with icon when card is short
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(status == .cancelled ? .secondary : themeColor.opacity(themeTitleOpacity))
                            .strikethrough(status == .cancelled)
                            .minimumScaleFactor(0.9)
                            .lineLimit(2)

                        Text(subtitle)
                           .font(.subheadline)
                           .foregroundColor(status == .cancelled ? .secondary : themeColor.opacity(themeSubtitleOpacity))
                           .minimumScaleFactor(0.9)
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
        }
    }

    private var statusBadge: some View {
        Group {
            if status == .cancelled {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            } else if status == .changed {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private func teacherPlaceholder(size: CGFloat) -> some View {
        Group {
            if let initials = teacherInitials, !initials.isEmpty {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: size, height: size)
                    .background(themeColor.opacity(teacherAvatarFillOpacity))
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundColor(.white)
                    .frame(width: size, height: size)
                    .background(themeColor.opacity(teacherAvatarFillOpacity))
                    .clipShape(Circle())
            }
        }
    }

    private var themeIconOpacity: Double { colorScheme == .dark ? 0.78 : 0.6 }
    private var themeTitleOpacity: Double { colorScheme == .dark ? 0.95 : 0.9 }
    private var themeSubtitleOpacity: Double { colorScheme == .dark ? 0.82 : 0.7 }
    private var teacherAvatarFillOpacity: Double { colorScheme == .dark ? 0.72 : 0.6 }

    private var backgroundColorForStatus: Color {
        switch status {
        case .cancelled:
            return Color(UIColor.secondarySystemBackground).opacity(0.4)
        case .changed:
            return themeColor.opacity(colorScheme == .dark ? 0.28 : 0.15)
        default:
            return themeColor.opacity(colorScheme == .dark ? 0.22 : 0.1)
        }
    }

    private var borderColorForStatus: Color {
        switch status {
        case .cancelled:
            return Color.secondary.opacity(0.3)
        case .changed:
            return themeColor.opacity(colorScheme == .dark ? 0.55 : 0.4)
        default:
            return themeColor.opacity(colorScheme == .dark ? 0.38 : 0.2)
        }
    }
}
