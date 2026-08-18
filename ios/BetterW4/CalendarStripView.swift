//
//  CalendarStripView.swift
//  BetterW4
//
//  The week strip under the header: seven day buttons, one page per ISO week.
//
//  Every date here is Oslo, ISO-numbered, via `W4Dates` — never `Calendar.current`. A student on a
//  trip with the phone set to another timezone must still see W4's Monday in W4's week.
//

import SwiftUI

struct CalendarStripView: View {
    let selectedDate: Date
    /// True when W4 has proven it ignores `?year=&week=`, in which case paging away from the
    /// current week would only ever show the current week's data (plan D-18).
    var weekNavigationEnabled: Bool = true
    /// Whether the day has anything to show, for the dot under the number.
    var hasEvents: ((Date) -> Bool)?
    var onDateSelected: ((Date) -> Void)?
    var onWeekChanged: ((Date) -> Void)?

    private let totalWeeks = 104
    private let centerIndex = 52

    @State private var anchorWeekStart: Date
    @State private var scrolledID: Int?

    init(
        selectedDate: Date,
        weekNavigationEnabled: Bool = true,
        hasEvents: ((Date) -> Bool)? = nil,
        onDateSelected: ((Date) -> Void)? = nil,
        onWeekChanged: ((Date) -> Void)? = nil
    ) {
        self.selectedDate = selectedDate
        self.weekNavigationEnabled = weekNavigationEnabled
        self.hasEvents = hasEvents
        self.onDateSelected = onDateSelected
        self.onWeekChanged = onWeekChanged
        _anchorWeekStart = State(initialValue: W4Dates.startOfWeek(containing: selectedDate))
        _scrolledID = State(initialValue: 52)
    }

    // MARK: - Week maths

    private func weekStart(for index: Int) -> Date {
        W4Dates.adding(days: (index - centerIndex) * 7, to: anchorWeekStart)
    }

    private func weekDays(for weekStart: Date) -> [DayCell] {
        (0..<7).map { offset in
            let date = W4Dates.startOfDay(W4Dates.adding(days: offset, to: weekStart))
            return DayCell(
                date: date,
                dayNumber: String(W4Dates.calendar.component(.day, from: date)),
                dayName: String(W4Dates.weekdayName(of: date).prefix(3))
            )
        }
    }

    private struct DayCell: Identifiable {
        let date: Date
        let dayNumber: String
        let dayName: String
        var id: Date { date }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if weekNavigationEnabled {
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
                .onChange(of: scrolledID) { _, newID in
                    guard let newID else { return }
                    let newWeekStart = weekStart(for: newID)
                    let currentWeekStart = W4Dates.startOfWeek(containing: selectedDate)
                    guard !W4Dates.isSameDay(newWeekStart, currentWeekStart) else { return }

                    // Keep the weekday the student was looking at when the week flips.
                    let weekday = W4Dates.calendar.component(.weekday, from: selectedDate)
                    let dayOffset = (weekday - 2 + 7) % 7
                    onWeekChanged?(W4Dates.adding(days: dayOffset, to: newWeekStart))
                }
                .onChange(of: selectedDate) { _, newDate in
                    let selectedWeekStart = W4Dates.startOfWeek(containing: newDate)
                    let dayDiff = W4Dates.calendar
                        .dateComponents([.day], from: anchorWeekStart, to: selectedWeekStart).day ?? 0
                    let targetIndex = centerIndex + Int((Double(dayDiff) / 7).rounded())
                    if targetIndex >= 0, targetIndex < totalWeeks, targetIndex != scrolledID {
                        scrolledID = targetIndex
                    }
                }
            } else {
                // W4 ignores the week parameters, so there is exactly one week to show.
                weekContent(for: W4Dates.startOfWeek(containing: selectedDate))
            }
        }
        .frame(minHeight: 72, maxHeight: .infinity)
        .sensoryFeedback(.selection, trigger: selectedDate)
    }

    @ViewBuilder
    private func weekContent(for weekStart: Date) -> some View {
        HStack(spacing: 6) {
            ForEach(weekDays(for: weekStart)) { item in
                dayButton(item)
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func dayButton(_ item: DayCell) -> some View {
        let isSelected = W4Dates.isSameDay(item.date, selectedDate)
        let isToday = W4Dates.isSameDay(item.date, TimeProvider.now)

        Button {
            onDateSelected?(item.date)
        } label: {
            VStack(spacing: 3) {
                Text(item.dayNumber)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(item.dayName)
                    .font(.system(size: 11, weight: .medium))
                    .textCase(.none)

                Circle()
                    .fill(dotColor(for: item.date, isSelected: isSelected))
                    .frame(width: 4, height: 4)
            }
            .foregroundColor(isSelected ? .white : (isToday ? .blue : .primary.opacity(0.55)))
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .center)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 12,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 12,
                    style: .continuous
                )
                .fill(isSelected ? Color.blue : Color.clear)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(Text(accessibilityLabel(for: item)))
    }

    private func dotColor(for date: Date, isSelected: Bool) -> Color {
        guard hasEvents?(date) == true else { return .clear }
        return isSelected ? .white.opacity(0.9) : .blue.opacity(0.7)
    }

    private func accessibilityLabel(for item: DayCell) -> String {
        "\(W4Dates.weekdayName(of: item.date)) \(W4Dates.format(item.date))"
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}
