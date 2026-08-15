import SwiftUI
import UIKit

// MARK: - Color Blending

private extension Color {
    /// Blends this color with another at full opacity. fraction = how much of `other` to mix in (0 = 100% self, 1 = 100% other).
    func blended(with fraction: CGFloat, of other: Color) -> Color {
        let u1 = UIColor(self)
        let u2 = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        u1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        u2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            red: Double(r1 + (r2 - r1) * fraction),
            green: Double(g1 + (g2 - g1) * fraction),
            blue: Double(b1 + (b2 - b1) * fraction),
            opacity: 1
        )
    }
}

// MARK: - Modern Apple Calendar Style Layout

struct ModernTimelineListView: View {
    let displayDate: Date
    let events: [ScheduleEvent]
    var onEventTapped: ((ScheduleEvent) -> Void)?
    let scale: CGFloat = 1 // Points per minute
    var gymId: Int? = nil
    
    // We get hour metrics passed in or compute locally
    
    private let calendar = Calendar.current
    private var referenceTime: Int { return 8 * 60 } // 8:00 AM (professional mode)
    
    // Core calendar hours
    private let startHour = 8
    private let endHour = 16 // Shows until 16:00
    
    private var eventLayouts: [EventLayoutInfo] {
        calculateEventOverlapLayouts(for: events, timeToMinutes: timeToMinutes)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if events.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.secondary)
                    Text("Ingen lektioner i dag")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ZStack(alignment: .top) {
                    // Background grid
                    modernGridBackground
                    
                    // Events
                    ForEach(eventLayouts, id: \.event.id) { layout in
                        let event = layout.event
                        let offsetFromTop = calculateOffset(for: event)
                        let duration = calculateDuration(start: event.startTime, end: event.endTime)
                        let height = max(30, CGFloat(duration) * scale)
                        
                        let widthFraction = 1.0 / CGFloat(layout.totalColumns)
                        let horizontalOffset = CGFloat(layout.column) / CGFloat(layout.totalColumns)
                        
                        // Absolute positioning container
                        HStack(alignment: .top, spacing: 0) {
                            // Empty space for time column (48 width + 16 spacing = 64)
                            Color.clear.frame(width: 58)
                            
                            GeometryReader { geo in
                                let contentWidth = geo.size.width * widthFraction
                                let offsetX = geo.size.width * horizontalOffset
                                
                                ModernScheduleCard(event: event)
                                    .frame(width: contentWidth - 4, height: height) // slight padding between columns
                                    .offset(x: offsetX + 2)
                                    .onTapGesture {
                                        onEventTapped?(event)
                                    }
                            }
                        }
                        .frame(height: height)
                        .offset(y: offsetFromTop)
                    }
                    
                    if calendar.isDateInToday(displayDate) {
                        TimelineView(.periodic(from: TimeProvider.now, by: 60)) { context in
                            modernNowLine(at: context.date)
                        }
                        .allowsHitTesting(false)
                    }
                }
                .padding(.vertical, 8)
                Color.clear.frame(height: 80)
            }
        }
    }
    
    @ViewBuilder
    private var modernGridBackground: some View {
        let totalMinutes = calculateTotalHeight() / scale
        let maxHourVal = max(endHour, (Int(totalMinutes) + referenceTime)/60 + 1)
        let displayHours = Array(startHour...maxHourVal)
        
        ZStack(alignment: .top) {
            Color.clear.frame(height: max(calculateTotalHeight(), CGFloat((endHour - startHour) * 60) * scale))
            ForEach(displayHours, id: \.self) { hour in
                HourGridLine(hour: hour, referenceTime: referenceTime, scale: scale)
            }
        }
    }
    
    @ViewBuilder
    private func modernNowLine(at date: Date) -> some View {
        let currentMinutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let offsetY = CGFloat(currentMinutes - referenceTime) * scale

        if offsetY >= 0 {
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
    
    private func calculateOffset(for event: ScheduleEvent) -> CGFloat {
        let eventStartMinutes = timeToMinutes(event.startTime)
        let minutesFromReference = eventStartMinutes - referenceTime
        return CGFloat(minutesFromReference) * scale
    }
    
    private func calculateTotalHeight() -> CGFloat {
        guard let lastLayout = eventLayouts.last else { return 0 }
        let duration = calculateDuration(start: lastLayout.event.startTime, end: lastLayout.event.endTime)
        return calculateOffset(for: lastLayout.event) + max(30, CGFloat(duration) * scale) + 40
    }
    
    private func timeToMinutes(_ time: String) -> Int {
        let separator = time.contains(":") ? ":" : "."
        let parts = time.split(separator: Character(separator)).compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
    }
    
    private func calculateDuration(start: String, end: String) -> Int {
        timeToMinutes(end) - timeToMinutes(start)
    }
}

struct HourGridLine: View {
    let hour: Int
    let referenceTime: Int
    let scale: CGFloat
    
    var body: some View {
        let hourMinutes = hour * 60
        let offset = CGFloat(hourMinutes - referenceTime) * scale
        
        if offset >= 0 {
            HStack(alignment: .top, spacing: 10) {
                Text("\(hour):00")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.8))
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


struct ModernScheduleCard: View {
    let event: ScheduleEvent
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settingsStore = SettingsStore.shared

    private var themeColor: Color {
        settingsStore.accentColor(for: event)
    }

    /// Light mode: tint toward white. Dark mode: tint toward black so cards stay saturated on dark backgrounds.
    private var cardBackgroundColor: Color {
        if event.status == .cancelled {
            // light gray
            return Color(colorScheme == .dark ? UIColor.systemGray4 : UIColor.systemGray6)
        } else {
            // swap it with dark gray 
            let neutral: Color = colorScheme == .dark ? Color(UIColor.systemGray6) : .white
            return themeColor.blended(with: colorScheme == .dark ? 0.6 : 0.85, of: neutral)
        }
    }
    
    private var displayTitle: String {
        SubjectMapper.displayName(for: event.title)
    }
    
    private var cancelledOpacity: CGFloat { event.status == .cancelled ? 0.5 : 1 }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Background
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(cardBackgroundColor)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                        // SPACER

                HStack(alignment: .center, spacing: 6) {
                    Text(displayTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary.opacity(0.6))
                        .lineLimit(1)
                        .strikethrough(event.status == .cancelled)
                    Spacer() 
                    Image(systemName: SubjectMapper.iconName(for: event.title))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary.opacity(0.4))
                }
                
                HStack(spacing: 6) {
                    if let room = event.room, !room.isEmpty {
                        Text(room)
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(.primary.opacity(0.5))
                            .lineLimit(1)
                    }
                    if let teacher = event.teacher, !teacher.isEmpty {
                        Text("• \(teacher)")
                            .font(.system(size: 13, weight: .light))
                            .foregroundColor(.primary.opacity(0.5))
                            .lineLimit(1)
                    }
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
                        Image(systemName: event.status == .cancelled ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(event.status == .cancelled ? .red : .orange)
                            .padding(6)
                    }
                    Spacer()
                }
            }
        }
        .opacity(cancelledOpacity)
    }
}
