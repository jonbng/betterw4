//
//  DemoDataTests.swift
//  BetterW4Tests
//
//  Wave 6 item 7 — the demo catalogue an App Review reviewer sees (features.md §4).
//
//  WHAT THESE TESTS ARE FOR. `DemoDataProvider` is the one file in the app whose bugs ship
//  straight to a reviewer, in Airplane Mode, with no way to recover. Three properties are worth a
//  regression test, and they are all easy to break by accident:
//
//    1. **Zero network.** Nothing the catalogue hands out may be a fetchable remote URL. The demo
//       roster deliberately keeps `photoURL`s (the loader refuses them in demo mode), but the
//       shell's own portrait accessor must be nil, and no mail, attachment or lesson may carry an
//       `http(s)` URL for a screen to follow.
//    2. **English, UWC-shaped.** The Lectio original was a Danish gymnasium — "1x MA",
//       "Matematik A", "Læs kapitel 5". A single Danish character or Lectio token creeping back in
//       is the exact regression this file exists to catch.
//    3. **Anchored to the clock.** Every factory is built from `TimeProvider.now`, so the demo is
//       always "this week" and "due tomorrow" rather than a frozen date in 2026.
//
//  [I] Everything asserted here is INVENTED demo content, not captured W4 evidence. A green suite
//      proves the catalogue is coherent, English and offline. It proves nothing about W4.
//

import XCTest
@testable import BetterW4

final class DemoDataTests: XCTestCase {

    // MARK: - Zero network

    /// Any absolute http(s) URL in the catalogue is a request waiting to happen on a reviewer's
    /// device. `demo://` is fine — nothing resolves it.
    func testCatalogueCarriesNoFetchableURLs() {
        let now = TimeProvider.now

        XCTAssertFalse(
            DemoDataProvider.mailAttachment.url.lowercased().hasPrefix("http"),
            "The demo attachment must not be fetchable"
        )

        for folder in DemoDataProvider.mailFolders {
            for message in DemoDataProvider.mailMessages(folder: folder, relativeTo: now) {
                XCTAssertNil(message.href, "A demo mail row must not carry a link to follow")
            }
        }

        let body = DemoDataProvider.mailMessage(id: "demo-mail-1", relativeTo: now).bodyHTML
        XCTAssertFalse(body.contains("http://"), "The demo mail body must not embed a remote asset")
        XCTAssertFalse(body.contains("https://"), "The demo mail body must not embed a remote asset")

        for assessment in DemoDataProvider.assessments(relativeTo: now) {
            XCTAssertNil(assessment.href, "A demo assessment must not link out")
        }

        for event in DemoDataProvider.scheduleEvents(weekOf: now) {
            let content = DemoDataProvider.lessonContent(for: event)
            for item in content.items {
                XCTAssertTrue(item.links.isEmpty, "A demo lesson must not link out")
            }
        }
    }

    /// The demo session has no portrait to fetch, and the shell must not invent one.
    func testDemoIdentityIsOfflineAndConsistent() {
        XCTAssertEqual(DemoDataProvider.uwcId, ProfileRepository.demoOwnUwcId)
        XCTAssertEqual(DemoDataProvider.person.uwcId, DemoDataProvider.uwcId)
        XCTAssertEqual(DemoDataProvider.profile.uwcId, DemoDataProvider.uwcId)
        XCTAssertEqual(DemoDataProvider.email, "\(DemoDataProvider.uwcId)@uwcrcn.no")
        XCTAssertFalse(DemoDataProvider.displayName.isEmpty)
        XCTAssertTrue(
            DemoDataProvider.uwcId.hasPrefix("nc00"),
            "Demo ids must sit outside any real cohort's range (reviewer-notes.md §8)"
        )
    }

    // MARK: - English, UWC-shaped

    /// The Lectio original was a Danish gymnasium. Nothing Danish, and nothing Lectio-shaped, may
    /// come back.
    func testCatalogueIsEnglishAndFreeOfLectio() {
        let danish = CharacterSet(charactersIn: "æøåÆØÅ")
        // Distinctive tokens only. Anything with an English collision ("hold" in "threshold",
        // "modul" in "module") would fail on innocent prose later and teach people to delete the
        // check rather than fix the content.
        let lectioTokens = ["lectio", "lektier", "opgaver", "skema", "beskeder", "aflyst", "gymid"]

        for text in allUserFacingText() {
            XCTAssertNil(
                text.rangeOfCharacter(from: danish),
                "Demo content must be English — found a Danish character in: \(text)"
            )
            let lowered = text.lowercased()
            for token in lectioTokens {
                XCTAssertFalse(
                    lowered.contains(token),
                    "Demo content must not carry the Lectio token '\(token)' — found in: \(text)"
                )
            }
        }
    }

    /// The subjects a reviewer sees have to read as an IB day at UWC RCN.
    func testTeachingWeekIsIB() {
        let titles = Set(DemoDataProvider.lessons.map(\.title))
        XCTAssertTrue(titles.contains("Biology HL"))
        XCTAssertTrue(titles.contains("Mathematics AA SL"))
        XCTAssertTrue(titles.contains("English A HL"))
        XCTAssertTrue(titles.contains("Theory of Knowledge"))

        let extraAcademics = DemoDataProvider.lessons.filter(\.isExtraAcademic)
        XCTAssertEqual(extraAcademics.count, 1, "Exactly one Extra Academics activity")
        XCTAssertEqual(DemoDataProvider.extraAcademicActivity.title, extraAcademics[0].title)
    }

    // MARK: - Shape

    /// Two full weekday weeks, weekends empty, with one cancelled and one changed block so both
    /// renderings are visible to a reviewer.
    func testScheduleCoversTwoWeekdayWeeks() {
        let now = TimeProvider.now
        let events = DemoDataProvider.scheduleEvents(weekOf: now)

        XCTAssertEqual(events.count, 2 * 5 * DemoDataProvider.lessons.count)
        XCTAssertEqual(events.filter { $0.status == .cancelled }.count, 1)
        XCTAssertEqual(events.filter { $0.status == .changed }.count, 1)

        let calendar = W4Dates.calendar
        for event in events {
            let weekday = calendar.component(.weekday, from: event.date)
            XCTAssertNotEqual(weekday, 1, "No Sunday lessons in the demo week")
            XCTAssertNotEqual(weekday, 7, "No Saturday lessons in the demo week")
        }

        // Anchored to the clock, not to a frozen date.
        let monday = W4Dates.startOfDay(W4Dates.startOfWeek(containing: now))
        XCTAssertTrue(events.contains { W4Dates.isSameDay($0.date, monday) })
    }

    /// A reviewer needs to see a done row, an overdue row, an upcoming row and a student-created
    /// row — every state the Assessments screen renders differently.
    func testAssessmentsCoverEveryRowState() {
        let now = TimeProvider.now
        let items = DemoDataProvider.assessments(relativeTo: now)

        XCTAssertEqual(items.filter { $0.status == .done }.count, 1)
        XCTAssertEqual(items.filter(\.isOverdue).count, 1)
        XCTAssertEqual(items.filter { $0.kind == .studentCreated }.count, 1)
        XCTAssertTrue(items.contains { ($0.daysLeft ?? 0) > 0 && !$0.isOverdue && $0.status == .pending })

        // Ids are namespaced by kind, because W4's two id spaces are independent.
        XCTAssertTrue(items.allSatisfy { $0.id.hasPrefix("class:") || $0.id.hasPrefix("student:") })
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "Assessment ids must be unique")

        // Due dates move with the clock.
        let today = W4Dates.startOfDay(now)
        XCTAssertTrue(items.contains { $0.dueDate.map { $0 > today } == true })
        XCTAssertTrue(items.contains { $0.dueDate.map { $0 < today } == true })
    }

    /// Inbox: three rows, two unread, one with an attachment. Sent: one row, and W4's archive grid
    /// has no sender column at all.
    func testMailHasBothGridsAndAnUnreadBadge() {
        let now = TimeProvider.now

        let inbox = DemoDataProvider.mailListPage(folder: .inbox, relativeTo: now)
        XCTAssertEqual(inbox.messages.count, 3)
        XCTAssertEqual(inbox.messages.filter(\.isUnread).count, 2)
        XCTAssertEqual(inbox.messages.filter(\.hasAttachment).count, 1)
        XCTAssertTrue(inbox.columns.hasSenderColumn)
        XCTAssertEqual(inbox.outcome, .parsed)

        let sent = DemoDataProvider.mailListPage(folder: .archive, relativeTo: now)
        XCTAssertEqual(sent.messages.count, 1)
        XCTAssertFalse(sent.columns.hasSenderColumn, "W4's archive grid has no From column")

        let detail = DemoDataProvider.mailMessage(id: "demo-mail-1", relativeTo: now)
        XCTAssertEqual(detail.attachments.count, 1)
        XCTAssertFalse(detail.bodyHTML.isEmpty)

        let plain = DemoDataProvider.mailMessage(id: "demo-mail-2", relativeTo: now)
        XCTAssertTrue(plain.attachments.isEmpty)
    }

    /// features.md §4: the demo student has a clean attendance record and is on campus.
    func testAttendanceIsCleanAndStatusIsOnCampus() {
        let overview = DemoDataProvider.attendanceOverview()
        XCTAssertTrue(overview.academic.isClean)
        XCTAssertTrue(overview.extraAcademic.isClean)
        XCTAssertTrue(overview.records.isEmpty)

        for source in AttendanceSource.allCases {
            let list = DemoDataProvider.attendanceList(source: source)
            XCTAssertTrue(list.isEmpty)
            XCTAssertNotNil(list.emptyMessage, "An empty list must still say why it is empty")
        }

        XCTAssertTrue(DemoDataProvider.campusStatus.isOnCampus)
        XCTAssertEqual(DemoDataProvider.campusStatus.label, "On campus")
        XCTAssertEqual(
            DemoDataProvider.campusStatus.options.count,
            CampusStatus.defaultOptions.count,
            "All eleven captured options stay selectable in demo"
        )
    }

    /// The reviewer-facing copy has to say plainly what this is (features.md §4).
    func testBannerStatesTheDemoPlainly() {
        XCTAssertEqual(DemoDataProvider.bannerText, "Demo data. Not connected to W4.")
    }

    // MARK: - Helpers

    /// Every string the demo puts in front of a reviewer, in one place.
    private func allUserFacingText() -> [String] {
        let now = TimeProvider.now
        var text: [String] = [DemoDataProvider.bannerText, DemoDataProvider.displayName]

        for lesson in DemoDataProvider.lessons {
            text.append(contentsOf: [lesson.title, lesson.subject, lesson.teacher, lesson.room])
        }

        for event in DemoDataProvider.scheduleEvents(weekOf: now) {
            text.append(contentsOf: [event.title, event.subtitle])
            if let notes = event.notes { text.append(notes) }
            if let homework = event.homework { text.append(homework) }
        }

        for assessment in DemoDataProvider.assessments(relativeTo: now) {
            text.append(assessment.title)
            text.append(contentsOf: [assessment.subject, assessment.classCode, assessment.teacher, assessment.unit].compactMap { $0 })
        }

        for folder in DemoDataProvider.mailFolders {
            text.append(folder.displayName)
            for message in DemoDataProvider.mailMessages(folder: folder, relativeTo: now) {
                text.append(message.subject)
                if let from = message.from { text.append(from) }
                text.append(DemoDataProvider.mailMessage(id: message.id, relativeTo: now).bodyHTML)
            }
        }

        text.append(DemoDataProvider.mailAttachment.name)
        text.append(String(decoding: DemoDataProvider.mailAttachmentBody, as: UTF8.self))

        for source in AttendanceSource.allCases {
            if let message = DemoDataProvider.attendanceList(source: source).emptyMessage {
                text.append(message)
            }
        }

        for field in DemoDataProvider.profile.fields {
            text.append(contentsOf: [field.label, field.value])
        }

        return text
    }
}
