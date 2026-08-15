import SwiftUI

struct CalendarStripView: View {
    private static let dayNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.dateFormat = "EEE"
        return formatter
    }()

    let selectedDate: Date
    var onDateSelected: ((Date) -> Void)?
    var onWeekChanged: ((Date) -> Void)?

    private let calendar = Calendar.current
    private let totalWeeks = 104
    private let centerIndex = 52

    @State private var anchorWeekStart: Date
    @State private var scrolledID: Int?

    init(
        selectedDate: Date,
        onDateSelected: ((Date) -> Void)? = nil,
        onWeekChanged: ((Date) -> Void)? = nil
    ) {
        self.selectedDate = selectedDate
        self.onDateSelected = onDateSelected
        self.onWeekChanged = onWeekChanged

        var comps = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        comps.weekday = 2 // Monday
        let startOfWeek = Calendar.current.date(from: comps) ?? Calendar.current.startOfDay(for: selectedDate)
        _anchorWeekStart = State(initialValue: startOfWeek)
        _scrolledID = State(initialValue: 52)
    }

    private func startOfCurrentWeek(for date: Date) -> Date {
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        comps.weekday = 2 // Monday
        return calendar.date(from: comps) ?? calendar.startOfDay(for: date)
    }

    private func weekStart(for index: Int) -> Date {
        calendar.date(byAdding: .weekOfYear, value: index - centerIndex, to: anchorWeekStart) ?? anchorWeekStart
    }

    private func weekDays(for weekStart: Date) -> [(date: Date, dayNumber: String, dayName: String)] {
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }

            let dayNumber = String(calendar.component(.day, from: date))
            let raw = Self.dayNameFormatter.string(from: date).replacingOccurrences(of: ".", with: "")
            let dayName = String(raw.prefix(3)).capitalized

            return (date, dayNumber, dayName)
        }
    }

    @ViewBuilder
    private func weekContent(for weekStart: Date) -> some View {
        HStack(spacing: 6) {
            ForEach(weekDays(for: weekStart), id: \.date) { item in
                let isSelected = calendar.isDate(item.date, inSameDayAs: selectedDate)

                Button(action: {
                    onDateSelected?(item.date)
                }) {
                    VStack(spacing: 4) {
                        Text(item.dayNumber)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text(item.dayName)
                            .font(.system(size: 11, weight: .medium))
                            .textCase(.none)
                    }
                    .foregroundColor(isSelected ? .white : (calendar.isDateInToday(item.date) ? .blue : .primary.opacity(0.55)))
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .center)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 12, style: .continuous)
                            .fill(isSelected ? Color.blue : Color.clear)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.horizontal, 12)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(0..<totalWeeks, id: \.self) { index in
                    weekContent(for: weekStart(for: index))
                        .containerRelativeFrame(.horizontal)
                        .id(index)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledID)
        .frame(minHeight: 72, maxHeight: .infinity)
        .onChange(of: scrolledID) { _, newID in
            guard let newID else { return }
            let newWeekStart = weekStart(for: newID)
            let currentWeekStart = startOfCurrentWeek(for: selectedDate)
            guard !calendar.isDate(newWeekStart, inSameDayAs: currentWeekStart) else { return }

            let weekday = calendar.component(.weekday, from: selectedDate)
            let dayOffset = (weekday - 2 + 7) % 7
            let targetDate = calendar.date(byAdding: .day, value: dayOffset, to: newWeekStart) ?? newWeekStart
            onWeekChanged?(targetDate)
        }
        .onChange(of: selectedDate) { _, newDate in
            let selectedWeekStart = startOfCurrentWeek(for: newDate)
            let dayDiff = calendar.dateComponents([.day], from: anchorWeekStart, to: selectedWeekStart).day ?? 0
            let targetIndex = centerIndex + (dayDiff / 7)
            if targetIndex >= 0, targetIndex < totalWeeks, targetIndex != scrolledID {
                scrolledID = targetIndex
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDate)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}
