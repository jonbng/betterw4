//
//  live_lessonBundle.swift
//  live-lesson
//
//  Created by Elliott Friedrich on 27/02/2026.
//

import WidgetKit
import SwiftUI

@main
struct live_lessonBundle: WidgetBundle {
    var body: some Widget {
        live_lessonLiveActivity()
        LessonTimelineWidget()
    }
}
