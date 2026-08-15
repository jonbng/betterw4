//
//  LectureTimerText.swift
//  live-lesson
//
//  Created by Elliott Friedrich on 23/03/2026.
//

import SwiftUI

/// System-driven countdown for Live Activities and widgets.
/// Prefer this over `TimelineView` in ActivityKit — periodic timelines are unreliable on iOS 18+.
struct LectureTimerText: View {
    let isUpcoming: Bool
    let lessonStart: Date
    /// Ignored when `isUpcoming` is true; pass the lesson end for in-progress.
    let lessonEnd: Date

    private var upcomingWindowStart: Date {
        Calendar.current.date(byAdding: .hour, value: -1, to: lessonStart)
            ?? lessonStart.addingTimeInterval(-3600)
    }

    var body: some View {
        if isUpcoming {
            Text(timerInterval: upcomingWindowStart...lessonStart, countsDown: true)
        } else {
            Text(timerInterval: lessonStart...lessonEnd, countsDown: true)
        }
    }
}
