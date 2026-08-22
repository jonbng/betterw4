//
//  ScreenRenderSmokeTests.swift
//  BetterW4Tests
//
//  Every screen, actually rendered.
//
//  The rest of the suite tests parsers, repositories and view models — the logic. None of it
//  evaluates a SwiftUI `body`, so a screen can be completely broken (a missing environment
//  object, a nil force-unwrap in a subview, a type that no longer exists) while 700 tests stay
//  green. `ImageRenderer` evaluates the view hierarchy for real, in the test host, without
//  needing a UI-test target or a booted app.
//
//  This is a smoke test on purpose. It asserts each screen *renders at all*; it says nothing
//  about whether it renders the right thing. Failures here are the loud kind — a crash or a
//  body that cannot be built.
//

import SwiftUI
import XCTest
@testable import BetterW4

@MainActor
final class ScreenRenderSmokeTests: XCTestCase {

    /// Demo mode is deliberate: it is the one path with no network and no keychain session, so
    /// these render exactly the way an App Review reviewer would first see them.
    private let student = Student.demo

    /// Renders `view` and fails with a useful name if the hierarchy cannot be built.
    private func assertRenders(
        _ name: String,
        _ view: some View,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let renderer = ImageRenderer(
            content: view
                .frame(width: 393, height: 852)   // iPhone 16 Pro points
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 1

        XCTAssertNotNil(
            renderer.uiImage,
            "\(name) produced no image — its body could not be evaluated",
            file: file,
            line: line
        )
    }

    // MARK: - The four tabs

    func testTimetableTabRenders() {
        assertRenders("ScheduleView", NavigationStack { ScheduleView(student: student) })
    }

    func testScheduleDaySkeletonRenders() {
        assertRenders("ScheduleDaySkeleton", ScheduleDaySkeleton())
    }

    func testLessonDetailSheetRenders() {
        let event = TimetableEvent(
            id: "ac-demo-0",
            title: "Biology HL",
            source: .academics,
            date: TimeProvider.now,
            room: "Lab 2",
            teacher: "A. Nordby"
        )
        assertRenders("LessonDetailSheet", LessonDetailSheet(event: event))
    }

    func testStudentsTabRenders() {
        let path = Binding.constant(NavigationPath())
        assertRenders(
            "StudentSearchView",
            NavigationStack {
                StudentSearchView(
                    student: student,
                    authViewModel: AuthenticationViewModel(),
                    navigationPath: path
                )
            }
        )
    }

    func testAssessmentsTabRenders() {
        assertRenders("AssessmentsView", NavigationStack { AssessmentsView(student: student) })
    }

    func testRootContentViewRenders() {
        // The whole shell, including the tab bar and whichever tab opens first.
        assertRenders("ContentView", ContentView())
    }

    // MARK: - W4-only surfaces

    func testHomeRenders() {
        assertRenders("HomeView", NavigationStack { HomeView(student: student) })
    }

    func testDocumentsRenders() {
        assertRenders("DocumentsView", NavigationStack { DocumentsView() })
    }

    func testTripsRenders() {
        assertRenders("TripsView", NavigationStack { TripsView() })
    }

    func testOnDutyRenders() {
        assertRenders("OnDutyView", NavigationStack { OnDutyView() })
    }

    func testBirthdaysRenders() {
        assertRenders("BirthdaysView", NavigationStack { BirthdaysView() })
    }

    func testExtraAcademicsRenders() {
        assertRenders("ExtraAcademicsView", NavigationStack { ExtraAcademicsView() })
    }

    func testNotificationsRenders() {
        assertRenders("NotificationsView", NavigationStack { NotificationsView() })
    }

    func testCampusStatusControlRenders() {
        assertRenders("CampusStatusControl", CampusStatusControl())
    }

    // MARK: - More-tab screens

    func testAbsenceRenders() {
        assertRenders("AbsenceView", NavigationStack { AbsenceView(student: student) })
    }

    func testGradesRenders() {
        assertRenders("GradesView", NavigationStack { GradesView(student: student) })
    }

    func testMyClassesRenders() {
        assertRenders("MyClassesView", NavigationStack { MyClassesView() })
    }

    func testMyTeachersRenders() {
        assertRenders("MyTeachersView", NavigationStack { MyTeachersView() })
    }

    func testMyClassDetailRenders() {
        assertRenders(
            "MyClassDetailView",
            NavigationStack {
                MyClassDetailView(
                    classId: "1DA13HMTAA",
                    seed: MyClass(
                        id: "1DA13HMTAA",
                        subject: "Mathematics Analysis and Approaches",
                        year: "1",
                        block: "D",
                        level: .higher,
                        levelLabel: "HL",
                        loaded: true
                    ),
                    directory: DirectoryViewModel()
                )
            }
        )
    }

    func testMailRenders() {
        assertRenders("MessagesView", NavigationStack { MessagesView(student: student) })
    }

    func testDirectorySearchRenders() {
        // Teachers still open this from More with a shared path; the Students tab owns its own.
        let path = Binding.constant(NavigationPath())
        assertRenders(
            "StudentSearchView",
            NavigationStack {
                StudentSearchView(
                    student: student,
                    authViewModel: AuthenticationViewModel(),
                    navigationPath: path
                )
            }
        )
    }

    func testSettingsRenders() {
        assertRenders("SettingsView", NavigationStack { SettingsView(student: student) })
    }

    func testHousesRenders() {
        assertRenders("HousesView", NavigationStack { HousesView() })
    }

    // MARK: - Auth

    func testLoginRenders() {
        assertRenders("LoginView", LoginView(viewModel: AuthenticationViewModel()))
    }

    // MARK: - Dark mode

    /// Dark mode is a separate render pass, and a colour that only exists in one scheme is a
    /// classic way to crash or vanish. Covering the four tabs is enough to catch that class.
    func testTabsRenderInDarkMode() {
        let screens: [(String, AnyView)] = [
            ("ScheduleView", AnyView(NavigationStack { ScheduleView(student: student) })),
            ("StudentSearchView", AnyView(NavigationStack {
                StudentSearchView(
                    student: student,
                    authViewModel: AuthenticationViewModel(),
                    navigationPath: Binding.constant(NavigationPath())
                )
            })),
            ("AssessmentsView", AnyView(NavigationStack { AssessmentsView(student: student) })),
            ("HomeView", AnyView(NavigationStack { HomeView(student: student) }))
        ]

        for (name, screen) in screens {
            let renderer = ImageRenderer(
                content: screen
                    .frame(width: 393, height: 852)
                    .environment(\.colorScheme, .dark)
            )
            renderer.scale = 1
            XCTAssertNotNil(renderer.uiImage, "\(name) failed to render in dark mode")
        }
    }
}
