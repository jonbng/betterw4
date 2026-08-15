//
//  StudentParser.swift
//  BetterLectio
//

import Foundation
import SwiftSoup

/// Parser for student-specific data, search, and absence records.
enum StudentParser {
    
    // MARK: - Parse Student Info

    /// Extracts student ID and name from Lectio HTML page
    static func parseStudentInfo(from html: String) throws -> (id: String, name: String) {
        let doc = try SwiftSoup.parse(html)

        // Look for student ID in elevid parameter in any link
        let links = try doc.select("a[href*=elevid]")
        var studentId: String?

        for link in links {
            let href = try link.attr("href")
            if let range = href.range(of: "elevid=(\\d+)", options: .regularExpression) {
                let idStr = href[range].replacingOccurrences(of: "elevid=", with: "")
                studentId = idStr
                break
            }
        }

        guard let id = studentId else {
            throw LectioError.parsingError("Could not find student ID")
        }

        // Look for student name in header
        var studentName = "Student"

        if let headerDiv = try doc.select("div[id*=subHeaderDiv]").first() {
            let headerText = try headerDiv.text()
            if let nameRange = headerText.range(of: "Elev:\\s*(.+)", options: .regularExpression) {
                studentName = String(headerText[nameRange])
                    .replacingOccurrences(of: "Elev:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let trimmedName = studentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName.caseInsensitiveCompare("Student") == .orderedSame,
           let fromTitle = parseStudentNameFromTitle(from: html) {
            studentName = fromTitle
        }

        return (id, studentName)
    }

    /// Extracts the current student's class (e.g. "3a", "BShannon") from the forside/homepage header.
    /// Format: "Elev: Name (3a 10)" or "Elev: Name (3a)" — parenthetical contains class and optional seat number.
    static func parseCurrentStudentClass(from html: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            guard let headerDiv = try doc.select("div[id*=subHeaderDiv]").first() else { return nil }
            let headerText = try headerDiv.text()
            guard let nameRange = headerText.range(of: "Elev:\\s*(.+)", options: .regularExpression) else { return nil }
            let namePart = String(headerText[nameRange])
                .replacingOccurrences(of: "Elev:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Extract parenthetical: "Name (3a 10)" or "Name (3a)" → "3a 10" or "3a"
            guard let open = namePart.lastIndex(of: "("),
                  let close = namePart.lastIndex(of: ")"),
                  open < close else { return nil }
            let info = String(namePart[namePart.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            let parts = info.split(separator: " ", maxSplits: 1)
            let className = parts.first.map(String.init) ?? ""
            // Named classes like "BShannon" do not start with a digit. Reject only
            // the kostelev marker when it is the entire parenthetical.
            guard !className.isEmpty, className.lowercased() != "k" else { return nil }
            return className
        } catch {
            print("⚠️ Failed to parse current student class: \(error)")
            return nil
        }
    }

    // MARK: - Parse Dropdown URL

    /// Extracts the autocomplete dataset URL from the FindSkemaAdv.aspx page.
    /// Looks for: Autocomplete.registerDataSetUrl('AvanceretSkema_...', '/lectio/.../cache/DropDown.aspx?...')
    static func parseDropdownURL(from html: String) -> String? {
        // Match the registerDataSetUrl call and capture the URL
        guard let range = html.range(
            of: #"Autocomplete\.registerDataSetUrl\('AvanceretSkema_[^']*',\s*'([^']+)'"#,
            options: .regularExpression
        ) else {
            print("⚠️ Autocomplete dropdown URL not found in HTML")
            return nil
        }

        let match = String(html[range])
        // Extract the URL from the second quoted argument
        guard let urlStart = match.range(of: "', '")?.upperBound ?? match.range(of: "','")?.upperBound else {
            return nil
        }
        let urlEnd = match.index(before: match.endIndex) // before trailing '
        guard urlStart < urlEnd else { return nil }
        return String(match[urlStart..<urlEnd])
    }

    // MARK: - Parse Dropdown Entries

    /// Parses the dropdown JSON response into StudentEntry array.
    /// JSON format: { "items": [["Name (class)", "S/TID", "", "11", " fs/ft", null, true], ...] }
    static func parseDropdownEntries(from data: Data, gymId: Int) throws -> [StudentEntry] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[Any]] else {
            throw LectioError.parsingError("Invalid dropdown JSON structure")
        }

        var entries: [StudentEntry] = []

        for item in items {
            guard item.count >= 2,
                  let nameField = item[0] as? String,
                  let typeAndId = item[1] as? String,
                  typeAndId.count > 1 else {
                continue
            }

            // Skip inactive/archived entries (field [2] = "i")
            if item.count > 2, let status = item[2] as? String, status == "i" {
                continue
            }

            // Map Lectio prefixes to DropdownEntityType
            let type: DropdownEntityType
            if typeAndId.hasPrefix("S") { type = .student }
            else if typeAndId.hasPrefix("T") { type = .teacher }
            else if typeAndId.hasPrefix("HE") { type = .team }
            else if typeAndId.hasPrefix("RO") { type = .room }
            else if typeAndId.hasPrefix("GE") { type = .group }
            else { type = .other }

            let entryId = String(typeAndId.drop(while: { !$0.isNumber }))

            guard !entryId.isEmpty else { continue }

            // Parse name and class/abbreviation from "Name (class info)" or "Name (abbrev)"
            let name: String
            let className: String
            let classNumber: String

            if let parenOpen = nameField.lastIndex(of: "("),
               let parenClose = nameField.lastIndex(of: ")") {
                var rawName = String(nameField[nameField.startIndex..<parenOpen]).trimmingCharacters(in: .whitespaces)
                let info = String(nameField[nameField.index(after: parenOpen)..<parenClose])

                if type == .teacher {
                    // For teachers, the parenthetical is their abbreviation
                    name = rawName
                    className = info
                    classNumber = ""
                } else {
                    // Strip (k) kostelev suffix from student names: "Iris Schibsbye Møller(k)" → "Iris Schibsbye Møller"
                    if rawName.hasSuffix("(k)") {
                        rawName = String(rawName.dropLast(3)).trimmingCharacters(in: .whitespaces)
                    }
                    name = rawName
                    // Active students: "2c 13" or "3a 10" → class + seat number
                    let parts = info.split(separator: " ", maxSplits: 1)
                    className = parts.first.map(String.init) ?? ""
                    classNumber = parts.count > 1 ? String(parts[1]) : ""
                }
            } else {
                name = nameField
                className = ""
                classNumber = ""
            }

            guard !name.isEmpty else { continue }

            entries.append(StudentEntry(
                studentId: entryId,
                name: name,
                classLabel: className,
                classNumber: classNumber,
                gymId: gymId,
                type: type
            ))
        }

        let students = entries.filter { $0.type == .student }
        let teachers = entries.filter { $0.type == .teacher }
        print("👥 Parsed \(entries.count) entries from dropdown JSON (\(teachers.count) teachers, \(students.count) students, \(entries.count - students.count - teachers.count) others)")

        return entries
    }

    // MARK: - Parse Student Picture ID

    /// Parses the student's schedule page to extract their profile picture ID.
    /// Looks for: `<img id="s_m_HeaderContent_picctrlthumbimage" src="...?pictureid={id}">`
    static func parseStudentPictureId(from html: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            guard let img = try doc.select("img#s_m_HeaderContent_picctrlthumbimage").first() else {
                return nil
            }
            let src = try img.attr("src")
            // Extract pictureid from: "/lectio/94/GetImage.aspx?pictureid=74096247556"
            guard let range = src.range(of: "pictureid=(\\d+)", options: .regularExpression) else {
                return nil
            }
            let match = String(src[range])
            return match.replacingOccurrences(of: "pictureid=", with: "")
        } catch {
            print("⚠️ Failed to parse picture ID: \(error)")
            return nil
        }
    }

    /// Parses the student's birthday from common Lectio elements.
    /// Look for: `<span id="s_m_Content_Content_StudentBirthday">`
    static func parseBirthday(from html: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            if let span = try doc.select("span#s_m_Content_Content_StudentBirthday").first() {
                return try span.text()
                    .replacingOccurrences(of: "Fødselsdag: ", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Parses the student's name from the maintitle div on SkemaNy.aspx.
    /// Format: "Eleven Name(k), Class - Skema" → "Name"
    /// Example: "Eleven Elliott Friedrich(k), 1x - Skema" → "Elliott Friedrich"
    static func parseStudentNameFromTitle(from html: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            guard let titleDiv = try doc.select("div#s_m_HeaderContent_MainTitle").first() else {
                return nil
            }
            let fullText = try titleDiv.text()
            // Pattern: "Eleven Name(k), Class - Skema" or "Eleven Name - Skema".
            // Class tokens are \\S+ so named (`BShannon`) and dotted (`10.st.kl.2`) codes parse.
            let namePattern = #"Eleven\s+(.+?)(?:\(k\))?(?:,\s*\S+)?\s*-"#
            guard let match = fullText.range(of: namePattern, options: .regularExpression) else {
                return nil
            }
            let matchedText = String(fullText[match])
            let nsRange = NSRange(matchedText.startIndex..., in: matchedText)
            if let regex = try? NSRegularExpression(pattern: namePattern),
               let result = regex.firstMatch(in: matchedText, range: nsRange) {
                let nameRange = result.range(at: 1)
                if let swiftRange = Range(nameRange, in: matchedText) {
                    return String(matchedText[swiftRange]).trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        } catch {
            print("⚠️ Failed to parse student name from title: \(error)")
            return nil
        }
    }

    /// Parses the student's class from the maintitle div on SkemaNy.aspx.
    /// Format: "Eleven Name(k), Class - Skema" → "Class"
    /// Example: "Eleven Elliott Friedrich(k), 1x - Skema" → "1x"
    static func parseStudentClassFromTitle(from html: String) -> String? {
        do {
            let doc = try SwiftSoup.parse(html)
            guard let titleDiv = try doc.select("div#s_m_HeaderContent_MainTitle").first() else {
                return nil
            }
            let fullText = try titleDiv.text()
            // Pattern: "Eleven Name(k), Class - Skema" — class may be named (`BShannon`),
            // dotted (`10.st.kl.2`), or hyphenated (`3hx-u`), so capture \\S+ not \\w+.
            let classPattern = #",\s*(\S+)\s*-"#
            guard let match = fullText.range(of: classPattern, options: .regularExpression) else {
                return nil
            }
            let matchedText = String(fullText[match])
            let nsRange = NSRange(matchedText.startIndex..., in: matchedText)
            if let regex = try? NSRegularExpression(pattern: classPattern),
               let result = regex.firstMatch(in: matchedText, range: nsRange) {
                let classNsRange = result.range(at: 1)
                if let swiftRange = Range(classNsRange, in: matchedText) {
                    return String(matchedText[swiftRange])
                }
            }
            return nil
        } catch {
            print("⚠️ Failed to parse student class from title: \(error)")
            return nil
        }
    }

    // MARK: - Parse Holds from Homepage

    /// Parses the hold/team list from the homepage (forside.aspx).
    /// Returns an array of (name, holdElementId) tuples.
    static func parseHoldsFromHomepage(from html: String) -> [(name: String, holdElementId: String)] {
        do {
            let doc = try SwiftSoup.parse(html)
            let links = try doc.select("#s_m_Content_Content_HoldAndGroupList ul.linklist-horizontal a")

            var holds: [(name: String, holdElementId: String)] = []
            for link in links {
                let name = try link.text().trimmingCharacters(in: .whitespacesAndNewlines)
                let href = try link.attr("href")

                // Extract holdelementid from href like "/lectio/94/SkemaNy.aspx?type=holdelement&holdelementid=71871521694"
                guard let range = href.range(of: "holdelementid=(\\d+)", options: .regularExpression) else {
                    continue
                }
                let holdElementId = String(href[range]).replacingOccurrences(of: "holdelementid=", with: "")
                holds.append((name: name, holdElementId: holdElementId))
            }

            print("📋 Parsed \(holds.count) holds from homepage")
            return holds
        } catch {
            print("⚠️ Failed to parse holds from homepage: \(error)")
            return []
        }
    }

    // MARK: - Parse Team Member Picture IDs

    /// Parses the team members page to extract studentId → pictureId mappings.
    /// The members page table contains rows with `data-lectiocontextcard` (e.g. "S72721770937")
    /// and `img` elements with `src` containing `pictureid=...`.
    static func parseTeamMemberPictureIds(from html: String) -> [String: String] {
        do {
            let doc = try SwiftSoup.parse(html)
            let rows = try doc.select("table#s_m_Content_Content_laerereleverpanel_alm_gv tr")

            var mapping: [String: String] = [:]
            for row in rows {
                // Find the first td with data-lectiocontextcard to get the person ID
                guard let contextTd = try row.select("td[data-lectiocontextcard]").first() else {
                    continue
                }
                let contextCard = try contextTd.attr("data-lectiocontextcard")
                // Extract the numeric ID — contextCard is like "S72721770937" or "T1498492783"
                guard contextCard.count > 1 else { continue }
                let personId = String(contextCard.dropFirst()) // drop S or T prefix

                // Find the img with pictureid in its src
                guard let img = try row.select("img[src*=pictureid]").first() else {
                    continue
                }
                let src = try img.attr("src")
                guard let pidRange = src.range(of: "pictureid=(\\d+)", options: .regularExpression) else {
                    continue
                }
                let pictureId = String(src[pidRange]).replacingOccurrences(of: "pictureid=", with: "")

                mapping[personId] = pictureId
            }

            print("🖼️ Parsed \(mapping.count) picture IDs from team members page")
            return mapping
        } catch {
            print("⚠️ Failed to parse team member picture IDs: \(error)")
            return [:]
        }
    }

    // MARK: - Parse Absence

    /// Parses the complete absence report from fravaerelev_fravaersaarsager.aspx HTML
    static func parseAbsenceReport(from html: String) throws -> AbsenceReport {
        let doc = try SwiftSoup.parse(html)

        let summary = try parseAbsenceSummary(from: doc)
        let missingReasons = try parseMissingReasons(from: doc)
        let registrations = try parseAbsenceRegistrations(from: doc)

        return AbsenceReport(
            summary: summary,
            missingReasons: missingReasons,
            registrations: registrations
        )
    }

    /// Parses the "Samlet fravær" section showing overall absence percentages
    private static func parseAbsenceSummary(from doc: Document) throws -> AbsenceSummary {
        let regularAbsence = try doc.select("span#s_m_Content_Content_FremmoedeFravaer").first()?.text() ?? "0%"
        let writtenAbsence = try doc.select("span#s_m_Content_Content_SkriftligFravaer").first()?.text() ?? "0%"

        return AbsenceSummary(
            regularAbsence: regularAbsence,
            writtenAbsence: writtenAbsence
        )
    }

    /// Parses the "Manglende fraværsårsager" table
    private static func parseMissingReasons(from doc: Document) throws -> [AbsenceEntry] {
        guard let table = try doc.select("table#s_m_Content_Content_FatabMissingAarsagerGV").first() else {
            return []
        }

        return try parseAbsenceTable(table, hasReasonColumns: false)
    }

    /// Parses the "Fraværsregistreringer" table
    private static func parseAbsenceRegistrations(from doc: Document) throws -> [AbsenceEntry] {
        guard let table = try doc.select("table#s_m_Content_Content_FatabAbsenceFravaerGV").first() else {
            return []
        }

        return try parseAbsenceTable(table, hasReasonColumns: true)
    }

    /// Parses an absence table (shared between missing reasons and registrations)
    private static func parseAbsenceTable(_ table: Element, hasReasonColumns: Bool) throws -> [AbsenceEntry] {
        let rows = try table.select("tbody tr")
        var entries: [AbsenceEntry] = []

        for row in rows {
            // Skip header row (has th elements)
            let headers = try row.select("th")
            if !headers.isEmpty() { continue }

            // Get all non-mobile cells (activity td has no class, so td.OnlyDesktop misses it)
            let cells = try row.select("td:not(.OnlyMobile)")
            guard cells.count >= 5 else { continue }

            // Week
            let week = try cells[0].text().trimmingCharacters(in: .whitespacesAndNewlines)

            // Activity info from the anchor element
            let activityLink = try cells[1].select("a.s2skemabrik").first()
            let activityText = try activityLink?.text() ?? cells[1].text()
            let activityHref = try activityLink?.attr("href") ?? ""

            // The edit endpoint uses its own registration `id`. It is not the lesson's
            // `absid`, so keep both values and use the registration id as model identity.
            let activityId = extractLectioActivityId(from: activityHref)
            let registrationId = try extractAbsenceRegistrationId(from: row)
            guard registrationId != nil || !activityId.isEmpty else { continue }

            // Parse activity details from tooltip data and content
            let activityDetails = parseActivityDetails(from: activityLink, activityText: activityText)

            // Absence percentage
            let absencePercent = try cells[2].text().trimmingCharacters(in: .whitespacesAndNewlines)

            // Absence type (or reason column for registrations)
            var absenceType = "Fravær"
            var reason: String? = nil
            var note: String? = nil
            var isApproved = false

            if hasReasonColumns && cells.count >= 7 {
                // For registrations table
                let typeCell = cells[3]
                let typeText = try typeCell.text().trimmingCharacters(in: .whitespacesAndNewlines)
                let hasOkImage = try !typeCell.select("img[src*=ok.gif]").isEmpty()
                isApproved = hasOkImage
                absenceType = hasOkImage ? "Godskrevet" : typeText

                // Registered at and by
                let registeredText = try cells[4].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let registeredParts = registeredText.split(separator: "\n", maxSplits: 1).map(String.init)
                // Registration date
                let registeredAt = registeredParts.first?.trimmingCharacters(in: .whitespaces) ?? ""
                let registeredBy = registeredParts.count > 1 ? registeredParts[1].trimmingCharacters(in: .whitespaces) : ""
                
                // Determine entry date: activity date > registration date
                let date = parseAbsenceDate(from: activityDetails?.dateTime ?? registeredAt)

                // Remark
                let remark = try cells[5].text().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

                // Reason and note
                // `Element.text()` collapses <br> into a space. Preserve the boundary so an
                // existing note is not accidentally folded into the reason label.
                let reasonHTML = try cells[6].html().replacingOccurrences(
                    of: #"(?i)<br\s*/?>"#,
                    with: "␞",
                    options: .regularExpression
                )
                let reasonCellText = try SwiftSoup.parseBodyFragment(reasonHTML).text()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let reasonParts = reasonCellText.split(separator: "␞").map(String.init)
                reason = reasonParts.first?.nilIfEmpty
                note = reasonParts.count > 1
                    ? reasonParts.dropFirst().joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    : nil

                entries.append(AbsenceEntry(
                    id: registrationId ?? activityId,
                    registrationId: registrationId,
                    activityId: activityId.nilIfEmpty,
                    date: date,
                    week: week,
                    activity: activityText,
                    activityDetails: activityDetails,
                    absencePercent: absencePercent,
                    absenceType: absenceType,
                    registeredAt: registeredAt,
                    registeredBy: registeredBy,
                    reason: reason,
                    note: note,
                    remark: remark,
                    isApproved: isApproved
                ))
            } else {
                // For missing reasons table (no reason columns)
                absenceType = try cells[3].text().trimmingCharacters(in: .whitespacesAndNewlines)

                // Registered at and by
                let registeredText = try cells[4].text().trimmingCharacters(in: .whitespacesAndNewlines)
                let registeredParts = registeredText.split(separator: "\n", maxSplits: 1).map(String.init)
                // Registration date
                let registeredAt = registeredParts.first?.trimmingCharacters(in: .whitespaces) ?? ""
                let registeredBy = registeredParts.count > 1 ? registeredParts[1].trimmingCharacters(in: .whitespaces) : ""
                
                // Determine entry date
                let date = parseAbsenceDate(from: activityDetails?.dateTime ?? registeredAt)

                // Remark
                let remark = cells.count > 5 ? try cells[5].text().trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil

                entries.append(AbsenceEntry(
                    id: registrationId ?? activityId,
                    registrationId: registrationId,
                    activityId: activityId.nilIfEmpty,
                    date: date,
                    week: week,
                    activity: activityText,
                    activityDetails: activityDetails,
                    absencePercent: absencePercent,
                    absenceType: absenceType,
                    registeredAt: registeredAt,
                    registeredBy: registeredBy,
                    reason: nil,
                    note: nil,
                    remark: remark,
                    isApproved: false
                ))
            }
        }

        return entries
    }

    /// Extracts the `id` query value from the row's fravaer_aarsag edit link.
    private static func extractAbsenceRegistrationId(from row: Element) throws -> String? {
        for link in try row.select("a[href*=fravaer_aarsag]") {
            let href = try link.attr("href")
            guard let components = URLComponents(
                url: URL(string: href, relativeTo: URL(string: "https://www.lectio.dk"))!,
                resolvingAgainstBaseURL: true
            ) else { continue }
            if let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
               !id.isEmpty {
                return id
            }
        }
        return nil
    }

    /// Extracts an event identifier from a Lectio link.
    /// Prefers `absid` (regular lesson) and falls back to `aftaleid` (private event).
    private static func extractLectioActivityId(from href: String) -> String {
        if let absRange = href.range(of: #"absid=(\d+)"#, options: .regularExpression) {
            return String(href[absRange]).replacingOccurrences(of: "absid=", with: "")
        }

        if let aftaleRange = href.range(of: #"aftaleid=(\d+)"#, options: .regularExpression) {
            return String(href[aftaleRange]).replacingOccurrences(of: "aftaleid=", with: "")
        }

        return ""
    }

    /// Parses activity details from a schedule brick element
    private static func parseActivityDetails(from link: Element?, activityText: String) -> ActivityDetails? {
        guard let link = link else { return nil }

        do {
            let tooltip = try link.attr("data-tooltip")
            let hasNote = try !link.select("span.ls-note").isEmpty()
            let hasHomework = try !link.select("span.ls-lektier").isEmpty()
            let isChanged = try link.hasClass("s2changed")

            // Extract title from tooltip (first line before date if present)
            let tooltipLines = tooltip.components(separatedBy: "\n")
            var title: String? = nil
            var dateTime = ""
            var hold = ""
            var teacher = ""
            var room = ""

            for (index, line) in tooltipLines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if index == 0 && !trimmed.contains("/") {
                    title = trimmed
                } else if trimmed.contains("/") && trimmed.contains("til") {
                    dateTime = trimmed
                } else if trimmed.hasPrefix("Hold: ") {
                    hold = String(trimmed.dropFirst(6))
                } else if trimmed.hasPrefix("Lærer: ") {
                    let teacherPart = String(trimmed.dropFirst(7))
                    // Extract abbreviation from "Name (Abbrev)"
                    if let open = teacherPart.lastIndex(of: "("),
                       let close = teacherPart.lastIndex(of: ")") {
                        teacher = String(teacherPart[teacherPart.index(after: open)..<close])
                    } else {
                        teacher = teacherPart
                    }
                } else if trimmed.hasPrefix("Lokale: ") {
                    room = String(trimmed.dropFirst(8))
                }
            }

            // Parse hold, teacher, room from activity text if not found in tooltip
            if hold.isEmpty {
                // Try to extract from activity text: "fr 10/10 1. modul - 1g4 da • Ka • 24"
                let pattern = try? NSRegularExpression(pattern: "([•\\-])\\s*([^•]+?)(?=\\s*[•\\-]|$)", options: [])
                let nsRange = NSRange(activityText.startIndex..., in: activityText)
                let matches = pattern?.matches(in: activityText, options: [], range: nsRange) ?? []

                if hold.isEmpty && matches.count > 0 {
                    let match = matches[0]
                    if let range = Range(match.range(at: 2), in: activityText) {
                        hold = String(activityText[range]).trimmingCharacters(in: .whitespaces)
                    }
                }
                if teacher.isEmpty && matches.count > 1 {
                    let match = matches[1]
                    if let range = Range(match.range(at: 2), in: activityText) {
                        teacher = String(activityText[range]).trimmingCharacters(in: .whitespaces)
                    }
                }
                if room.isEmpty && matches.count > 2 {
                    let match = matches[2]
                    if let range = Range(match.range(at: 2), in: activityText) {
                        room = String(activityText[range]).trimmingCharacters(in: .whitespaces)
                    }
                }
            }

            return ActivityDetails(
                title: title,
                hold: hold,
                teacher: teacher,
                room: room,
                dateTime: dateTime,
                hasNote: hasNote,
                hasHomework: hasHomework,
                isChanged: isChanged
            )
        } catch {
            return nil
        }
    }
    
    /// Parses absence date strings (e.g. "10/10-2025 08:10 til 09:50" or "10/10-2025 08:12")
    private static func parseAbsenceDate(from string: String) -> Date {
        // Formats:
        // 1. "10/10-2025 08:10 til 09:50"
        // 2. "10/10-2025 08:12"
        
        let cleanString = string.replacingOccurrences(of: " til.*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        
        // Try with time
        formatter.dateFormat = "dd/MM-yyyy HH:mm"
        if let date = formatter.date(from: cleanString) {
            return date
        }
        
        // Try without time (just in case)
        formatter.dateFormat = "dd/MM-yyyy"
        if let date = formatter.date(from: cleanString) {
            return date
        }
        
        return Date()
    }
}
