//
//  W4HouseParserTests.swift
//  BetterW4Tests
//
//  Fixture provenance:
//
//    houses-index.html / houses-denmark.html — [I] SYNTHESIZED from the live
//    people/students/byhouse capture of 19 Aug 2026. Identities are invented
//    (nc00…). Assertions verify the parser, not that W4 still emits this markup.
//

import XCTest
@testable import BetterW4

final class W4HouseParserTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "Fixtures/W4")
            ?? bundle.url(forResource: name, withExtension: "html") else {
            throw XCTSkip("Fixture \(name).html is not in the test bundle")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testIndexListsHousesInDocumentOrder() throws {
        let houses = W4HouseParser.parseIndex(try fixture("houses-index"))
        XCTAssertEqual(
            houses.map(\.id),
            ["denmark", "finland", "grad", "iceland", "norway", "sweden"]
        )
        XCTAssertEqual(houses.first?.name, "Denmark")
        XCTAssertEqual(houses.first { $0.id == "grad" }?.name, "Graduated")
        XCTAssertTrue(houses.allSatisfy { !$0.loaded })
    }

    func testHousePageGroupsLeaderRoomsAndUnassigned() throws {
        let house = W4HouseParser.parseHouse(try fixture("houses-denmark"))
        XCTAssertEqual(house.id, "denmark")
        XCTAssertEqual(house.name, "Denmark")
        XCTAssertTrue(house.loaded)
        XCTAssertEqual(house.leaders.map(\.id), ["nc00lead"])
        XCTAssertEqual(house.leaders.single.person.name, "Chris Chen")
        XCTAssertEqual(house.leaders.single.person.kind, .staff)
        XCTAssertEqual(house.rooms.map(\.name), ["Room 101", "Room 102"])
        XCTAssertEqual(house.rooms[0].residents.map(\.id), ["nc00aaa", "nc00bbb"])
        XCTAssertEqual(house.rooms[1].residents.map(\.id), ["nc00ddd"])
        XCTAssertEqual(house.unassigned.map(\.id), ["nc00eee"])
        XCTAssertEqual(house.studentCount, 4)
    }

    func testResidentFieldsComeFromTheListItem() throws {
        let house = W4HouseParser.parseHouse(try fixture("houses-denmark"))
        let alex = try XCTUnwrap(house.rooms[0].residents.first { $0.id == "nc00aaa" })
        XCTAssertEqual(alex.person.name, "Alex Andersen")
        XCTAssertEqual(alex.person.house, "Denmark")
        XCTAssertEqual(alex.country, "Denmark")
        XCTAssertEqual(alex.year, "1")
        XCTAssertEqual(alex.status, "On campus")
        XCTAssertNil(alex.person.photoURL)
        XCTAssertTrue(try XCTUnwrap(alex.detailLine).contains("1st year"))

        let bea = try XCTUnwrap(house.rooms[0].residents.first { $0.id == "nc00bbb" })
        XCTAssertEqual(bea.country, "Italy")
        XCTAssertEqual(bea.year, "2")
        XCTAssertEqual(
            bea.person.photoURL?.absoluteString,
            "https://w4.uwcrcn.no/files/user_photos/nc00bbb_photo.jpg"
        )

        let dana = try XCTUnwrap(house.rooms[1].residents.first)
        XCTAssertTrue(try XCTUnwrap(dana.status).hasPrefix("Off campus"))
        XCTAssertTrue(try XCTUnwrap(dana.status).contains("01-May-2026"))
    }

    func testPlacementFindsRoomAndUnassignedStudents() throws {
        let house = W4HouseParser.parseHouse(try fixture("houses-denmark"))
        let alex = try XCTUnwrap(house.placement(of: "nc00aaa"))
        XCTAssertEqual(alex.house.id, "denmark")
        XCTAssertEqual(alex.room?.name, "Room 101")
        XCTAssertEqual(alex.resident.person.name, "Alex Andersen")

        let eli = try XCTUnwrap(house.placement(of: "NC00EEE"))
        XCTAssertEqual(eli.house.id, "denmark")
        XCTAssertNil(eli.room)
        XCTAssertEqual(eli.resident.id, "nc00eee")

        XCTAssertNil(house.placement(of: "nc00lead"))
        XCTAssertNil(house.placement(of: ""))
    }

    func testHouseFlagsMapIdsAndNames() {
        XCTAssertEqual(HouseFlagKind.of("denmark"), .denmark)
        XCTAssertEqual(HouseFlagKind.of("Finland"), .finland)
        XCTAssertEqual(HouseFlagKind.of("iceland"), .iceland)
        XCTAssertEqual(HouseFlagKind.of("Norway"), .norway)
        XCTAssertEqual(HouseFlagKind.of("sweden"), .sweden)
        XCTAssertEqual(HouseFlagKind.of("grad"), .graduated)
        XCTAssertEqual(HouseFlagKind.of("Graduated"), .graduated)
        XCTAssertNil(HouseFlagKind.of("unknown"))
        XCTAssertEqual(houseFlagLabel("Denmark", houseId: "denmark"), "🇩🇰 Denmark")
        XCTAssertEqual(houseFlagLabel("Graduated", houseId: "grad"), "🎓 Graduated")
    }

    func testHouseIdIsReadFromTheSiblingQuery() {
        XCTAssertEqual(
            W4HouseParser.houseId(fromHref: "/index.php?r=people/students/byhouse/index&house_id=denmark"),
            "denmark"
        )
        XCTAssertEqual(W4HouseParser.slug(fromName: "Graduated"), "grad")
    }
}

private extension Array {
    var single: Element {
        precondition(count == 1)
        return self[0]
    }
}
