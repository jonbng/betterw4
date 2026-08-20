//
//  W4OnDutyParserTests.swift
//  BetterW4Tests
//
//  Fixture provenance:
//    onduty.html — live capture of `people/onduty` on 19 Aug 2026 **[V]**
//    onduty-schedule.html — live capture of `people/onduty/schedule` **[V]**
//    The two-role markup in testTwoRolesAndEmptyLocation is **[I]** synthesized
//    to cover a shape the live page can emit but did not on that day.
//

import XCTest
@testable import BetterW4

final class W4OnDutyParserTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesLiveTodayPage() throws {
        let page = W4OnDutyParser.parseToday(try fixture("onduty"))
        XCTAssertEqual(page.title, "People on duty 19-Aug-2026")
        XCTAssertEqual(page.date, W4Dates.date(year: 2026, month: 8, day: 19))
        XCTAssertEqual(page.groups.count, 1)
        XCTAssertEqual(page.groups[0].role, "House Leader on Call")
        let person = try XCTUnwrap(page.people.first)
        XCTAssertEqual(person.uwcId, "nc26lguz")
        XCTAssertEqual(person.name, "Luis Guzmán García Valdecasas")
        XCTAssertEqual(person.phone, "+34 691 701579")
        XCTAssertEqual(person.email, "luis.guzman.garcia.valdecasas@uwcrcn.no")
        XCTAssertNil(person.location)
        XCTAssertTrue(person.photoURL?.absoluteString.contains("/files/user_photos/nc26lguz_photo.jpg") == true)
    }

    func testParsesLiveSchedule() throws {
        let schedule = W4OnDutyParser.parseSchedule(try fixture("onduty-schedule"))
        XCTAssertEqual(schedule.monthLabel, "August 2026")
        XCTAssertEqual(schedule.year, 2026)
        XCTAssertEqual(schedule.month, 8)
        let today = try XCTUnwrap(schedule.days.first(where: \.isToday))
        XCTAssertEqual(today.date, W4Dates.date(year: 2026, month: 8, day: 19))
        XCTAssertEqual(today.groups.first?.role, "House Leader on Call")
        XCTAssertEqual(today.people.first?.name, "Luis Guzmán García Valdecasas")

        let friday = try XCTUnwrap(schedule.days.first { $0.date == W4Dates.date(year: 2026, month: 8, day: 21) })
        XCTAssertEqual(friday.groups.first?.role, "Weekend OVERNIGHT House Leader")
        XCTAssertEqual(friday.people.first?.name, "Mariya Georgieva")

        let saturday = try XCTUnwrap(schedule.days.first { $0.date == W4Dates.date(year: 2026, month: 8, day: 22) })
        XCTAssertEqual(saturday.groups.count, 2)
    }

    func testUpcomingSkipsToday() throws {
        let upcoming = W4OnDutyParser.upcomingDays(
            in: W4OnDutyParser.parseSchedule(try fixture("onduty-schedule")),
            from: W4Dates.date(year: 2026, month: 8, day: 19)!
        )
        XCTAssertEqual(
            upcoming.compactMap(\.date),
            [
                W4Dates.date(year: 2026, month: 8, day: 20),
                W4Dates.date(year: 2026, month: 8, day: 21),
                W4Dates.date(year: 2026, month: 8, day: 22)
            ]
        )
    }

    func testTwoRolesAndEmptyLocation() {
        let html = """
        <div id="content_inner">
          <h2>People on duty 20-Aug-2026</h2>
          <h3>House Leader on Call</h3>
          <table><tr><td><table><tr>
            <td><img src="/files/user_photos/nc00fff_thumb.jpg" alt="Photo of nc00fff" /></td>
            <td>
              <b>Frankie Fossum</b><br />
              <b>Phone:</b> +47 12 34 56 78<br />
              <b>E-mail:</b> frankie@uwcrcn.no<br />
              <b>Location:</b> Haugland<br />
            </td>
          </tr></table></td></tr></table>
          <h3>Nurse on Call</h3>
          <table><tr><td><table><tr>
            <td><img src="/files/user_photos/nc00ccc_thumb.jpg" alt="Photo of nc00ccc" /></td>
            <td>
              <b>Chris Chen</b><br />
              <b>Phone:</b> +47 98 76 54 32<br />
              <b>E-mail:</b> chris@uwcrcn.no<br />
              <b>Location:</b> <br />
            </td>
          </tr></table></td></tr></table>
        </div>
        """
        let page = W4OnDutyParser.parseToday(html)
        XCTAssertEqual(page.groups.count, 2)
        XCTAssertEqual(page.groups[0].people.first?.location, "Haugland")
        XCTAssertNil(page.groups[1].people.first?.location)
    }

    func testTelephoneURLStripsSpaces() {
        XCTAssertEqual(OnDutyContact.telephoneURL("+34 691 701579")?.absoluteString, "tel:+34691701579")
        XCTAssertEqual(OnDutyContact.mailtoURL("luis@uwcrcn.no")?.scheme, "mailto")
        XCTAssertNil(OnDutyContact.telephoneURL("n/a"))
    }

    func testEnrichCopiesPhoneOntoScheduleNameMatch() throws {
        let today = W4OnDutyParser.parseToday(try fixture("onduty")).people
        let saturday = try XCTUnwrap(
            W4OnDutyParser.parseSchedule(try fixture("onduty-schedule"))
                .days.first { $0.date == W4Dates.date(year: 2026, month: 8, day: 22) }
        )
        let luis = try XCTUnwrap(W4OnDutyParser.enrich(saturday, with: today).people.first { $0.name.contains("Luis") })
        XCTAssertEqual(luis.phone, "+34 691 701579")
        XCTAssertEqual(luis.uwcId, "nc26lguz")
    }
}
