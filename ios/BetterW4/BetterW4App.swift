//
//  BetterW4App.swift
//  BetterW4
//
//  Created by Elliott Friedrich on 02/02/2026.
//

import SwiftUI
#if os(iOS)
import BackgroundTasks
#endif

@main
struct BetterW4App: App {
    init() {
        Task.detached(priority: .utility) {
            OutgoingMessageAttachment.purgeStaleTemporaryFiles()
        }
        #if os(iOS)
        NotificationBackgroundRefresh.register { task in
            NotificationRefresh.handle(task)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
