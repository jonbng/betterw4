//
//  live_lessonLiveActivity.swift
//  live-lesson
//
//  Created by Elliott Friedrich on 27/02/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct live_lessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LectioActivityAttributes.self) { context in
            // Lock screen / banner UI — dispatches based on variant
            LockScreenView(attributes: context.attributes, state: context.state)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island (long-press)
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityLessonSnapshot(attributes: context.attributes, state: context.state) { lesson, _ in
                        Label(lesson.subjectName, systemImage: lesson.subjectIconName)
                            .font(.headline)
                            .foregroundStyle(Color.lessonMappingHue(lesson.subjectColorHue))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityLessonSnapshot(attributes: context.attributes, state: context.state) { lesson, isUpcoming in
                        let lessonStart = LectioActivityAttributes.dateFromTimeString(lesson.startTime, on: lesson.date)
                        let lessonEnd   = LectioActivityAttributes.dateFromTimeString(lesson.endTime,   on: lesson.date)
                        LectureTimerText(
                            isUpcoming: isUpcoming,
                            lessonStart: lessonStart,
                            lessonEnd: lessonEnd
                        )
                        .font(.headline)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityLessonSnapshot(attributes: context.attributes, state: context.state) { lesson, isUpcoming in
                        let progress = isUpcoming ? 0.0 : context.attributes.progress(for: lesson, at: Date())
                        VStack(spacing: 8) {
                            if let room = lesson.room {
                                Text(room)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if !isUpcoming {
                                ProgressView(value: progress)
                                    .tint(Color.lessonMappingHue(lesson.subjectColorHue))
                            }
                            Text("\(lesson.startTime) – \(lesson.endTime)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                LiveActivityLessonSnapshot(attributes: context.attributes, state: context.state) { lesson, _ in
                    Label {
                        Text(lesson.subjectName.prefix(4))
                    } icon: {
                        Image(systemName: lesson.subjectIconName)
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.lessonMappingHue(lesson.subjectColorHue))
                }
            } compactTrailing: {
                LiveActivityLessonSnapshot(attributes: context.attributes, state: context.state) { lesson, isUpcoming in
                    let lessonStart = LectioActivityAttributes.dateFromTimeString(lesson.startTime, on: lesson.date)
                    let lessonEnd   = LectioActivityAttributes.dateFromTimeString(lesson.endTime,   on: lesson.date)
                    LectureTimerText(
                        isUpcoming: isUpcoming,
                        lessonStart: lessonStart,
                        lessonEnd: lessonEnd
                    )
                    .font(.caption2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } minimal: {
                LiveActivityLessonSnapshot(attributes: context.attributes, state: context.state) { lesson, _ in
                    Image(systemName: lesson.subjectIconName)
                        .foregroundStyle(Color.lessonMappingHue(lesson.subjectColorHue))
                }
            }
        }
    }
}

// MARK: - Re-render on Activity.update (TimelineView is unreliable in ActivityKit, iOS 18+)

private struct LiveActivityLessonSnapshot<Content: View>: View {
    let attributes: LectioActivityAttributes
    let state: LectioActivityAttributes.ContentState
    private let content: (LectioActivityAttributes.EmbeddedLesson, Bool) -> Content

    init(
        attributes: LectioActivityAttributes,
        state: LectioActivityAttributes.ContentState,
        @ViewBuilder content: @escaping (LectioActivityAttributes.EmbeddedLesson, Bool) -> Content
    ) {
        self.attributes = attributes
        self.state = state
        self.content = content
    }

    var body: some View {
        Group {
            if let (lesson, isUpcoming) = attributes.currentOrUpcomingLesson(at: Date()) {
                content(lesson, isUpcoming)
            }
        }
        .id(state.version)
    }
}

// MARK: - Preview helpers

private extension LectioActivityAttributes.EmbeddedLesson {
    static func make(
        subject: String, icon: String, hue: Int,
        room: String? = nil, teacher: String? = nil,
        start: String, end: String, on day: Date = Calendar.current.startOfDay(for: Date())
    ) -> LectioActivityAttributes.EmbeddedLesson {
        .init(id: UUID().uuidString, subjectName: subject, subjectIconName: icon,
              subjectColorHue: hue, room: room, teacher: teacher,
              startTime: start, endTime: end, date: day)
    }
}

private var previewAttributes: LectioActivityAttributes {
    let day = Calendar.current.startOfDay(for: Date())
    return LectioActivityAttributes(
        todaysLessons: [
            .make(subject: "Matematik", icon: "function",          hue: 238, room: "A2.14", teacher: "JEH", start: "08:10", end: "09:40", on: day),
            .make(subject: "Dansk",     icon: "text.book.closed.fill", hue: 342, room: "B1.03",              start: "09:55", end: "11:25", on: day),
        ],
        variant: "standard"
    )
}

#Preview("Notification", as: .content, using: previewAttributes) {
    live_lessonLiveActivity()
} contentStates: {
    LectioActivityAttributes.ContentState(version: 0)
    LectioActivityAttributes.ContentState(version: 1)
}
