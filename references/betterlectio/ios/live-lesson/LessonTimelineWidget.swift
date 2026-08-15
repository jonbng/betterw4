//
//  LessonTimelineWidget.swift
//  live-lesson
//
//  Created by Elliott Friedrich on 23/03/2026.
//

import SwiftUI
import WidgetKit

struct LessonTimelineEntry: TimelineEntry {
    let date: Date
    let activeLesson: SharedLesson?
    let lessonEndDate: Date?
    let upcomingLesson: SharedLesson?
    let lessonStartDate: Date?
}

struct LessonTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> LessonTimelineEntry {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date())
        let start = cal.date(bySettingHour: 8, minute: 10, second: 0, of: day)!
        let end = cal.date(bySettingHour: 9, minute: 40, second: 0, of: day)!
        let lesson = SharedLesson(
            id: "1",
            title: "1x Ma",
            displayName: "Matematik",
            iconName: "function",
            colorHue: 238,
            room: "A2.14",
            teacher: "JEH",
            startTime: "08:10",
            endTime: "09:40",
            status: "normal",
            date: day
        )
        return LessonTimelineEntry(
            date: Date(),
            activeLesson: lesson,
            lessonEndDate: end,
            upcomingLesson: nil,
            lessonStartDate: start
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LessonTimelineEntry) -> Void) {
        let now = Date()
        let entries = buildEntries(referenceDate: now)
        let current = entries.filter { $0.date <= now }.max(by: { $0.date < $1.date })
        completion(current ?? entries.first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LessonTimelineEntry>) -> Void) {
        let now = Date()
        let entries = buildEntries(referenceDate: now)
        let policy = reloadPolicy(lessons: todaysLessons(on: now), referenceDate: now)
        completion(Timeline(entries: entries, policy: policy))
    }

    // MARK: - Timeline construction

    private func todaysLessons(on referenceDate: Date) -> [(lesson: SharedLesson, start: Date, end: Date)] {
        let calendar = Calendar.current
        return SharedScheduleData.load()
            .filter { calendar.isDate($0.date, inSameDayAs: referenceDate) && $0.status != "cancelled" }
            .map { lesson in
                let start = LectioActivityAttributes.dateFromTimeString(lesson.startTime, on: lesson.date)
                let end = LectioActivityAttributes.dateFromTimeString(lesson.endTime, on: lesson.date)
                return (lesson, start, end)
            }
            .sorted { $0.start < $1.start }
    }

    private func entry(at instant: Date, bounds: [(lesson: SharedLesson, start: Date, end: Date)]) -> LessonTimelineEntry {
        if let row = bounds.first(where: { $0.start <= instant && instant < $0.end }) {
            return LessonTimelineEntry(
                date: instant,
                activeLesson: row.lesson,
                lessonEndDate: row.end,
                upcomingLesson: nil,
                lessonStartDate: row.start
            )
        }
        if let row = bounds.first(where: { $0.start > instant }) {
            return LessonTimelineEntry(
                date: instant,
                activeLesson: nil,
                lessonEndDate: nil,
                upcomingLesson: row.lesson,
                lessonStartDate: row.start
            )
        }
        return LessonTimelineEntry(
            date: instant,
            activeLesson: nil,
            lessonEndDate: nil,
            upcomingLesson: nil,
            lessonStartDate: nil
        )
    }

    private func buildEntries(referenceDate: Date) -> [LessonTimelineEntry] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: referenceDate)
        let bounds = todaysLessons(on: referenceDate)

        guard !bounds.isEmpty else {
            return [
                LessonTimelineEntry(
                    date: referenceDate,
                    activeLesson: nil,
                    lessonEndDate: nil,
                    upcomingLesson: nil,
                    lessonStartDate: nil
                )
            ]
        }

        var transitionTimes: [Date] = [dayStart]
        for row in bounds {
            transitionTimes.append(row.start)
            transitionTimes.append(row.end)
        }
        transitionTimes.sort()

        var unique: [Date] = []
        for t in transitionTimes {
            if let last = unique.last, abs(t.timeIntervalSince(last)) < 1 {
                continue
            }
            unique.append(t)
        }

        return unique.map { entry(at: $0, bounds: bounds) }
    }

    private func reloadPolicy(lessons: [(lesson: SharedLesson, start: Date, end: Date)], referenceDate: Date) -> TimelineReloadPolicy {
        guard let lastEnd = lessons.map({ $0.end }).max() else {
            return .after(referenceDate.addingTimeInterval(3600))
        }
        return .after(lastEnd)
    }
}

// MARK: - Views

struct LessonTimelineWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: LessonTimelineEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangularContent
        case .accessoryCircular:
            circularContent
        case .accessoryInline:
            inlineContent
        default:
            rectangularContent
        }
    }

    private var rectangularContent: some View {
        Group {
            if let lesson = entry.activeLesson,
               let start = entry.lessonStartDate,
               let end = entry.lessonEndDate {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(lesson.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    LectureTimerText(isUpcoming: false, lessonStart: start, lessonEnd: end)
                        .font(.caption)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else if let lesson = entry.upcomingLesson, let start = entry.lessonStartDate {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(lesson.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    LectureTimerText(isUpcoming: true, lessonStart: start, lessonEnd: start)
                        .font(.caption)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                Text("Ingen lektion")
                    .font(.headline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var circularContent: some View {
        ZStack {
            if let lesson = entry.activeLesson,
               let start = entry.lessonStartDate,
               let end = entry.lessonEndDate {
                VStack(spacing: 0) {
                    Image(systemName: lesson.iconName)
                        .font(.caption2)
                        .foregroundStyle(Color.lessonMappingHue(lesson.colorHue))
                    LectureTimerText(isUpcoming: false, lessonStart: start, lessonEnd: end)
                        .font(.caption2)
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                }
            } else if let lesson = entry.upcomingLesson, let start = entry.lessonStartDate {
                VStack(spacing: 0) {
                    Image(systemName: lesson.iconName)
                        .font(.caption2)
                        .foregroundStyle(Color.lessonMappingHue(lesson.colorHue))
                    LectureTimerText(isUpcoming: true, lessonStart: start, lessonEnd: start)
                        .font(.caption2)
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                }
            } else {
                Image(systemName: "calendar")
                    .font(.caption)
            }
        }
    }

    private var inlineContent: some View {
        Group {
            if let lesson = entry.activeLesson,
               let start = entry.lessonStartDate,
               let end = entry.lessonEndDate {
                HStack(spacing: 4) {
                    Text(lesson.displayName)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LectureTimerText(isUpcoming: false, lessonStart: start, lessonEnd: end)
                        .monospacedDigit()
                }
            } else if let lesson = entry.upcomingLesson, let start = entry.lessonStartDate {
                HStack(spacing: 4) {
                    Text(lesson.displayName)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LectureTimerText(isUpcoming: true, lessonStart: start, lessonEnd: start)
                        .monospacedDigit()
                }
            } else {
                Text("Ingen lektion")
            }
        }
    }
}

struct LessonTimelineWidget: Widget {
    let kind = "LessonTimelineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LessonTimelineProvider()) { entry in
            LessonTimelineWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Lektion")
        .description("Naeste eller aktive lektion med nedtaelling.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

#Preview(as: .accessoryRectangular) {
    LessonTimelineWidget()
} timeline: {
    LessonTimelineEntry(
        date: Date(),
        activeLesson: SharedLesson(
            id: "1",
            title: "1x Ma",
            displayName: "Matematik",
            iconName: "function",
            colorHue: 238,
            room: "A2.14",
            teacher: nil,
            startTime: "08:10",
            endTime: "09:40",
            status: "normal",
            date: Calendar.current.startOfDay(for: Date())
        ),
        lessonEndDate: Date().addingTimeInterval(1800),
        upcomingLesson: nil,
        lessonStartDate: Date().addingTimeInterval(-900)
    )
}
