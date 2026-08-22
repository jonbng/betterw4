//
//  BirthdaysView.swift
//  BetterW4
//
//  More ▸ Birthdays — upcoming birthdays from `people/birthdays`, with a
//  compact month grid so you can browse the rest of the year.
//

import SwiftUI

struct BirthdaysView: View {
    @StateObject private var viewModel = BirthdaysViewModel()
    @StateObject private var directory = DirectoryViewModel()
    @State private var highlightedDay: Date?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    Picker("Show", selection: $viewModel.filter) {
                        ForEach(BirthdayKindFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section {
                    monthHeader
                    BirthdayMonthGrid(
                        month: viewModel.displayedMonth,
                        selected: viewModel.selected,
                        highlightedDay: highlightedDay,
                        today: W4Dates.startOfDay(TimeProvider.now)
                    ) { day in
                        guard let date = day.date else { return }
                        highlightedDay = date
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(day.id, anchor: .top)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
                }

                if viewModel.isCurrentMonth {
                    todaySection
                    if !viewModel.tomorrowPeople.isEmpty {
                        peopleSection(
                            title: "Tomorrow",
                            people: viewModel.tomorrowPeople,
                            dayId: "tomorrow"
                        )
                    }
                }

                ForEach(listDays) { day in
                    peopleSection(
                        title: BirthdaysViewModel.caption(for: day),
                        people: day.people,
                        dayId: day.id
                    )
                }

                ForEach(viewModel.earlierDays) { day in
                    peopleSection(
                        title: BirthdaysViewModel.caption(for: day),
                        people: day.people,
                        dayId: day.id
                    )
                }

                if viewModel.upcomingDays.isEmpty,
                   viewModel.todayPeople.isEmpty,
                   viewModel.earlierDays.isEmpty,
                   !viewModel.isLoading,
                   viewModel.month != nil {
                    Section {
                        W4SurfaceEmptyRow(
                            text: emptyText,
                            systemImage: "birthday.cake"
                        )
                    }
                }

                if viewModel.freshness != nil {
                    Section {
                        W4SurfaceFreshnessLabel(freshness: viewModel.freshness)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Birthdays")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
        .overlay { overlay }
    }

    private var listDays: [BirthdayDay] {
        if viewModel.isCurrentMonth {
            return viewModel.upcomingDays.filter { day in
                guard let date = day.date else { return true }
                let today = W4Dates.startOfDay(TimeProvider.now)
                if date == today { return false }
                if date == W4Dates.adding(days: 1, to: today) { return viewModel.tomorrowPeople.isEmpty }
                return true
            }
        }
        return viewModel.upcomingDays
    }

    private var emptyText: String {
        switch viewModel.filter {
        case .all: return "No birthdays this month."
        case .students: return "No student birthdays this month."
        case .staff: return "No staff birthdays this month."
        }
    }

    private var monthHeader: some View {
        HStack {
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Previous month")

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text(viewModel.monthLabel)
                    .font(.headline)
                if !viewModel.isCurrentMonth {
                    Button("This month") {
                        viewModel.goToCurrentMonth()
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            Spacer(minLength: 0)

            Button {
                viewModel.goToNextMonth()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Next month")
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var todaySection: some View {
        Section {
            if viewModel.todayPeople.isEmpty {
                W4SurfaceEmptyRow(
                    text: "No birthdays today.",
                    systemImage: "birthday.cake"
                )
            } else {
                ForEach(viewModel.todayPeople) { person in
                    NavigationLink {
                        StudentProfileView(person: person.directoryPerson, directory: directory)
                    } label: {
                        BirthdayPersonRow(person: person, prominent: true)
                    }
                }
            }
        } header: {
            Label("Today", systemImage: "birthday.cake.fill")
        }
        .id("today")
    }

    private func peopleSection(title: String, people: [BirthdayPerson], dayId: String) -> some View {
        Section {
            ForEach(people) { person in
                NavigationLink {
                    StudentProfileView(person: person.directoryPerson, directory: directory)
                } label: {
                    BirthdayPersonRow(person: person, prominent: false)
                }
            }
        } header: {
            Text(title)
        }
        .id(dayId)
    }

    @ViewBuilder
    private var overlay: some View {
        if viewModel.isLoading, viewModel.month?.ref != viewModel.selected {
            ProgressView("Loading birthdays…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
        } else if let message = viewModel.errorMessage, viewModel.month?.ref != viewModel.selected {
            ContentUnavailableView {
                Label("Birthdays unavailable", systemImage: "birthday.cake")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") {
                    Task { await viewModel.refresh() }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
        }
    }
}

// MARK: - Person row

private struct BirthdayPersonRow: View {
    let person: BirthdayPerson
    var prominent: Bool

    var body: some View {
        HStack(spacing: 12) {
            W4AvatarView(
                url: person.photoURL,
                name: person.displayName,
                size: prominent ? 56 : 44
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName)
                    .font(prominent ? .headline : .body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(person.roleLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, prominent ? 4 : 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(person.displayName), \(person.roleLabel)")
    }
}

// MARK: - Month grid

private struct BirthdayMonthGrid: View {
    let month: BirthdayMonth
    let selected: BirthdayMonthRef
    let highlightedDay: Date?
    let today: Date
    let onSelect: (BirthdayDay) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(Self.weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    switch cell {
                    case .empty:
                        Color.clear.frame(height: 40)
                    case .day(let day):
                        dayCell(day)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(month.monthLabel ?? selected.label)
    }

    private func dayCell(_ day: BirthdayDay) -> some View {
        let isToday = day.date.map { W4Dates.startOfDay($0) == today } ?? false
        let isHighlighted = day.date != nil && day.date.flatMap { W4Dates.startOfDay($0) } == highlightedDay
        let hasPeople = !day.people.isEmpty
        return Button {
            guard hasPeople else { return }
            onSelect(day)
        } label: {
            VStack(spacing: 4) {
                Text("\(day.dayNumber)")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : (hasPeople ? Color.primary : Color.secondary))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(isToday ? Color.accentColor : Color.clear)
                    )
                HStack(spacing: 2) {
                    ForEach(day.people.prefix(3)) { person in
                        Circle()
                            .fill(person.isStaff ? Color.orange : Color.accentColor)
                            .frame(width: 4, height: 4)
                    }
                    if day.people.isEmpty {
                        Circle().fill(Color.clear).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasPeople)
        .accessibilityLabel(accessibilityLabel(for: day, isToday: isToday))
        .accessibilityAddTraits(hasPeople ? .isButton : [])
    }

    private func accessibilityLabel(for day: BirthdayDay, isToday: Bool) -> String {
        var parts: [String] = []
        if isToday { parts.append("Today") }
        parts.append(day.dateLabel)
        if day.people.isEmpty {
            parts.append("no birthdays")
        } else if day.people.count == 1 {
            parts.append(day.people[0].displayName)
        } else {
            parts.append("\(day.people.count) birthdays")
        }
        return parts.joined(separator: ", ")
    }

    private var cells: [Cell] {
        let year = month.year ?? selected.year
        let monthNumber = month.month ?? selected.month
        guard let first = W4Dates.date(year: year, month: monthNumber, day: 1)
        else {
            return month.days.map { .day($0) }
        }
        let weekday = W4Dates.calendar.component(.weekday, from: first)
        let leading = (weekday + 5) % 7
        let length = W4Dates.calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let byNumber = Dictionary(uniqueKeysWithValues: month.days.map { ($0.dayNumber, $0) })
        var result: [Cell] = Array(repeating: .empty, count: leading)
        for number in 1...length {
            if let existing = byNumber[number] {
                result.append(.day(existing))
            } else {
                let date = W4Dates.date(year: year, month: monthNumber, day: number)
                result.append(.day(BirthdayDay(
                    date: date,
                    dayNumber: number,
                    dateLabel: date.map { Self.fallbackDayFormatter.string(from: $0) } ?? "\(number)",
                    people: []
                )))
            }
        }
        while result.count % 7 != 0 {
            result.append(.empty)
        }
        return result
    }

    private enum Cell {
        case empty
        case day(BirthdayDay)
    }

    private static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    private static let fallbackDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = W4Dates.zone
        formatter.calendar = W4Dates.calendar
        formatter.dateFormat = "EEE d MMM"
        return formatter
    }()
}

#Preview("Birthdays") {
    NavigationStack {
        BirthdaysView()
    }
}
