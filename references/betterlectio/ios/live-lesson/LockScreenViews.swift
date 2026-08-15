//
//  LockScreenViews.swift
//  live-lesson
//
//  Created by Elliott Friedrich on 27/02/2026.
//

import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Dispatcher

struct LockScreenView: View {
    let attributes: LectioActivityAttributes
    let state: LectioActivityAttributes.ContentState

    var body: some View {
        Group {
            switch LiveActivityVariant(rawValue: attributes.variant) ?? .standard {
            case .compact:
                CompactLockScreenView(attributes: attributes, state: state)
            case .standard:
                StandardLockScreenView(attributes: attributes, state: state)
            case .expanded:
                ExpandedLockScreenView(attributes: attributes, state: state)
            }
        }
        .activityBackgroundTint(.clear)
    }
}

// MARK: - Compact

/// Single-line: subject name + time remaining
struct CompactLockScreenView: View {
    let attributes: LectioActivityAttributes
    let state: LectioActivityAttributes.ContentState

    var body: some View {
        Group {
            if let (lesson, isUpcoming) = attributes.currentOrUpcomingLesson(at: Date()) {
                let lessonStart = LectioActivityAttributes.dateFromTimeString(lesson.startTime, on: lesson.date)
                let lessonEnd   = LectioActivityAttributes.dateFromTimeString(lesson.endTime,   on: lesson.date)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: lesson.subjectIconName)
                        .foregroundStyle(Color.lessonMappingHue(lesson.subjectColorHue))

                    Text(lesson.subjectName)
                        .font(.headline)
                        .fontWeight(.bold)
                        .lineLimit(1)

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
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .id(state.version)
    }
}

// MARK: - Standard

/// Subject + room + time + progress bar — mirrors ScheduleHeaderView
struct StandardLockScreenView: View {
    let attributes: LectioActivityAttributes
    let state: LectioActivityAttributes.ContentState

    var body: some View {
        Group {
            if let (lesson, isUpcoming) = attributes.currentOrUpcomingLesson(at: Date()) {
                let lessonStart = LectioActivityAttributes.dateFromTimeString(lesson.startTime, on: lesson.date)
                let lessonEnd   = LectioActivityAttributes.dateFromTimeString(lesson.endTime,   on: lesson.date)
                let progress    = isUpcoming ? 0.0 : attributes.progress(for: lesson, at: Date())
                let subjectColor = Color.lessonMappingHue(lesson.subjectColorHue)

                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HStack(alignment: .center, spacing: 6) {
                            Text(lesson.subjectName)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(subjectColor)

                            if let room = lesson.room {
                                Text("\u{2022}")
                                    .font(.title3)
                                    .fontWeight(.light)
                                    .foregroundStyle(.secondary)

                                Text(room)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .lineLimit(1)
                            }
                        }

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

                    if !isUpcoming {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(subjectColor.opacity(0.15))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(subjectColor)
                                    .frame(width: geometry.size.width * progress, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .id(state.version)
    }
}

// MARK: - Expanded

/// Full info: subject + room + teacher + time range + progress + next lesson
struct ExpandedLockScreenView: View {
    let attributes: LectioActivityAttributes
    let state: LectioActivityAttributes.ContentState

    var body: some View {
        Group {
            if let (lesson, isUpcoming) = attributes.currentOrUpcomingLesson(at: Date()) {
                let lessonStart  = LectioActivityAttributes.dateFromTimeString(lesson.startTime, on: lesson.date)
                let lessonEnd    = LectioActivityAttributes.dateFromTimeString(lesson.endTime,   on: lesson.date)
                let progress     = isUpcoming ? 0.0 : attributes.progress(for: lesson, at: Date())
                let subjectColor = Color.lessonMappingHue(lesson.subjectColorHue)
                let next         = attributes.nextLesson(after: lesson)

                VStack(spacing: 10) {
                    // Current lesson header
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HStack(alignment: .center, spacing: 6) {
                            Text(lesson.subjectName)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(subjectColor)

                            if let room = lesson.room {
                                Text("\u{2022}")
                                    .font(.title3)
                                    .fontWeight(.light)
                                    .foregroundStyle(.secondary)

                                Text(room)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .lineLimit(1)
                            }
                        }

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

                    // Teacher + time range
                    HStack {
                        if let teacher = lesson.teacher {
                            Label(teacher, systemImage: "person.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(lesson.startTime) – \(lesson.endTime)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Progress bar
                    if !isUpcoming {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(subjectColor.opacity(0.15))
                                    .frame(height: 6)

                                Capsule()
                                    .fill(subjectColor)
                                    .frame(width: geometry.size.width * progress, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }

                    // Next lesson preview
                    if let next {
                        Divider()
                        HStack(spacing: 6) {
                            Text("Næste:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Image(systemName: next.subjectIconName)
                                .font(.caption)
                                .foregroundStyle(Color.lessonMappingHue(next.subjectColorHue))

                            Text(next.subjectName)
                                .font(.caption)
                                .fontWeight(.semibold)

                            if let nextRoom = next.room {
                                Text("\u{2022} \(nextRoom)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(next.startTime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .id(state.version)
    }
}
