//
//  ScheduleParser.swift
//  BetterLectio
//

import Foundation
import SwiftSoup
import CryptoKit

/// Parser for schedule and lesson content from Lectio.
enum ScheduleParser {
    
    // MARK: - Parse Schedule

    /// Parses schedule HTML into ScheduleEvent array using SwiftSoup
    static func parseSchedule(from html: String) throws -> [ScheduleEvent] {
        let doc = try SwiftSoup.parse(html)
        var events: [ScheduleEvent] = []

        // Find the schedule table
        guard let scheduleTable = try doc.select("table.s2skema").first() else {
            throw LectioError.parsingError("Schedule table not found")
        }

        // Find all day columns (td elements with data-date attribute)
        let dayColumns = try scheduleTable.select("td[data-date]")

        print("📅 Found \(dayColumns.count) day columns")

        // Build column-index → date map for the all-day row (parsed below).
        var dateByColumnIndex: [Int: Date] = [:]

        for dayColumn in dayColumns {
            // Get the date for this column
            let dateString = try dayColumn.attr("data-date")
            guard let date = parseDate(from: dateString) else {
                print("⚠️ Could not parse date: \(dateString)")
                continue
            }

            dateByColumnIndex[try dayColumn.elementSiblingIndex()] = date

            // Find all event bricks in this day
            let eventBricks = try dayColumn.select("a.s2skemabrik.s2brik")

            print("📋 Found \(eventBricks.count) events for \(dateString)")

            for brick in eventBricks {
                if let event = try parseEvent(from: brick, date: date) {
                    events.append(event)
                }
            }
        }

        // All-day ("Hele dagen") events live in a separate row above the timed
        // grid — typically the previous sibling of the data-date row, with
        // s2infoHeader cells matched by column index.
        if let dataRow = try dayColumns.first()?.parent(),
           let infoRow = try dataRow.previousElementSibling() {
            for cell in infoRow.children() where (try? cell.hasClass("s2infoHeader")) == true {
                let columnIndex = try cell.elementSiblingIndex()
                guard let date = dateByColumnIndex[columnIndex] else { continue }

                // All-day chips lack the s2brik class; match s2skemabrik only.
                let bricks = try cell.select("a.s2skemabrik")
                for brick in bricks {
                    let tooltip = try brick.attr("data-tooltip")
                    // Skip duplicates of timed events that are also rendered in the info row.
                    guard tooltip.contains("Hele dagen") else { continue }
                    if let event = try parseEvent(from: brick, date: date) {
                        events.append(event)
                    }
                }
            }
        }

        return events
    }

    // MARK: - Parse Individual Event

    /// Parses a single event brick element
    private static func parseEvent(from brick: Element, date: Date) throws -> ScheduleEvent? {
        // Get the data-tooltip attribute which contains structured info
        let tooltip = try brick.attr("data-tooltip")

        // Get unique ID from data-brikid (preferred)
        let brikId = try brick.attr("data-brikid")
        let href = try brick.attr("href")

        // Get teacher ID from data-lectiocontextcard (format: "T{teacherId}")
        let contextCard = try brick.attr("data-lectiocontextcard")
        let teacherId: String?
        if contextCard.hasPrefix("T"), contextCard.count > 1 {
            teacherId = String(contextCard.dropFirst())
        } else {
            teacherId = nil
        }

        // Determine status from CSS classes
        let status: EventStatus
        if try brick.hasClass("s2cancelled") {
            status = .cancelled
        } else if try brick.hasClass("s2changed") {
            status = .changed
        } else {
            status = .normal
        }

        // Parse tooltip content
        let (title, timeInfo, teacher, room, notes, homework, _, _, isAllDay) = parseTooltip(tooltip)

        // All-day events have no clock range; render as a top-of-day chip
        let startTime: String
        let endTime: String
        let subtitle: String
        if isAllDay {
            startTime = ""
            endTime = ""
            subtitle = "Hele dagen"
        } else {
            (startTime, endTime) = extractTimes(from: timeInfo)
            subtitle = "\(startTime) - \(endTime)"
        }

        // All-day chips often lack data-brikid/href; fall back to a stable hash
        // of (date + tooltip) so identity survives refreshes.
        let id = resolvedEventId(brikId: brikId, href: href)
            ?? contentBasedId(date: date, tooltip: tooltip)

        return ScheduleEvent(
            id: id,
            title: title,
            subtitle: subtitle,
            startTime: startTime,
            endTime: endTime,
            teacher: teacher,
            teacherId: teacherId,
            room: room,
            status: status,
            date: date,
            notes: notes,
            homework: homework,
            isAllDay: isAllDay
        )
    }

    /// Stable content-based id for events lacking brikid/href (e.g. all-day chips).
    private static func contentBasedId(date: Date, tooltip: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let base = "\(formatter.string(from: date))|\(tooltip)"
        let digest = SHA256.hash(data: Data(base.utf8))
        return "AD" + digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// Resolves a stable event id from the schedule brick.
    /// Falls back to IDs embedded in `href` for private events where `data-brikid` may be empty.
    private static func resolvedEventId(brikId: String, href: String) -> String? {
        if !brikId.isEmpty {
            return brikId
        }

        if let absRange = href.range(of: #"absid=(\d+)"#, options: .regularExpression) {
            let absId = String(href[absRange]).replacingOccurrences(of: "absid=", with: "")
            return absId.isEmpty ? nil : "ABS\(absId)"
        }

        if let aftaleRange = href.range(of: #"aftaleid=(\d+)"#, options: .regularExpression) {
            let aftaleId = String(href[aftaleRange]).replacingOccurrences(of: "aftaleid=", with: "")
            return aftaleId.isEmpty ? nil : "AFT\(aftaleId)"
        }

        return nil
    }

    // MARK: - Parse Tooltip

    /// Parses the data-tooltip attribute which contains event details
    /// Format:
    /// - Status like "Ændret!" or "Aflyst!" (optional)
    /// - Title (if present before time)
    /// - Date and time (e.g., "2/2-2026 09:00 til 09:50")
    /// - Hold: Class name (preferred source for title)
    /// - Lærer: Teacher, Lokale: Room
    /// - Optional: Note:, Lektier:, Øvrigt indhold:
    static func parseTooltip(_ tooltip: String) -> (title: String, timeInfo: String, teacher: String?, room: String?, notes: String?, homework: String?, activityTitle: String?, holdName: String?, isAllDay: Bool) {
        let lines = tooltip.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }

        var title: String?
        var timeInfo = ""
        var teacher: String?
        var room: String?
        var notes: String?
        var homework: String?
        var holdName: String?
        var isAllDay = false

        var currentSection: String?

        for line in lines where !line.isEmpty {
            // Skip status indicators
            if line == "Ændret!" || line == "Aflyst!" {
                continue
            }
            // Detect "Hele dagen" anywhere in the tooltip — Lectio doesn't always put it
            // on a line that matches the HH:mm regex below.
            else if line.contains("Hele dagen") {
                isAllDay = true
                continue
            }
            // Look for time info (has format like "09:00 til 09:50" or "2/2-2026 09:00 til 09:50")
            else if timeInfo.isEmpty && (line.range(of: #"\d{2}:\d{2}\s+(til|-)\s+\d{2}:\d{2}"#, options: .regularExpression) != nil) {
                timeInfo = line
            }
            // Extract class name from "Hold:" - this is the preferred title
            else if line.hasPrefix("Hold:") {
                holdName = line.replacingOccurrences(of: "Hold:", with: "").trimmingCharacters(in: .whitespaces)
            }
            // Extract teacher
            else if line.hasPrefix("Lærer:") || line.hasPrefix("Lærere:") {
                teacher = line.replacingOccurrences(of: "Lærer:", with: "")
                    .replacingOccurrences(of: "Lærere:", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            // Extract room
            else if line.hasPrefix("Lokale:") {
                room = line.replacingOccurrences(of: "Lokale:", with: "").trimmingCharacters(in: .whitespaces)
            }
            else if line.hasPrefix("Lokaler:") {
                room = line.replacingOccurrences(of: "Lokaler:", with: "").trimmingCharacters(in: .whitespaces)
            }
            // Section markers
            else if line.hasPrefix("Note:") {
                currentSection = "note"
                notes = ""
            }
            else if line.hasPrefix("Lektier:") {
                currentSection = "homework"
                homework = ""
            }
            else if line.hasPrefix("Øvrigt indhold:") {
                currentSection = "other"
            }
            // Collect content for sections
            else if currentSection == "note" {
                notes = (notes ?? "") + line + "\n"
            }
            else if currentSection == "homework" {
                homework = (homework ?? "") + line + "\n"
            }
            // If no section is active and no title yet, use as title (but not if it looks like time)
            else if title == nil && currentSection == nil && !line.contains("/") && !line.contains(":") {
                title = line
            }
        }

        // Hold names starting with a digit (e.g. "1x Fy") are real subjects — prefer those.
        // Generic groups like "Alle 1. G. elever" lack a subject, so fall back to the real title.
        let finalTitle: String
        if let hold = holdName, hold.first?.isNumber == true {
            finalTitle = hold
        } else {
            finalTitle = title ?? holdName ?? "Ukendt"
        }

        // Clean up multiline content
        notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        homework = homework?.trimmingCharacters(in: .whitespacesAndNewlines)

        return (finalTitle, timeInfo, teacher, room, notes, homework, title, holdName, isAllDay)
    }

    // MARK: - Extract Times

    /// Extracts start and end times from time info string
    /// Formats: "2/2-2026 09:00 til 09:50" or "09:00-09:50" or "Hele dagen"
    private static func extractTimes(from timeInfo: String) -> (start: String, end: String) {
        // Try "til" format (Danish)
        if let tilRange = timeInfo.range(of: #"(\d{2}:\d{2})\s+til\s+(\d{2}:\d{2})"#, options: .regularExpression) {
            let match = String(timeInfo[tilRange])
            let components = match.components(separatedBy: " til ")
            if components.count == 2 {
                return (components[0].trimmingCharacters(in: .whitespaces),
                        components[1].trimmingCharacters(in: .whitespaces))
            }
        }

        // Try dash format
        if let dashRange = timeInfo.range(of: #"(\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})"#, options: .regularExpression) {
            let match = String(timeInfo[dashRange])
            let components = match.components(separatedBy: "-")
            if components.count == 2 {
                return (components[0].trimmingCharacters(in: .whitespaces),
                        components[1].trimmingCharacters(in: .whitespaces))
            }
        }

        // Check for "Hele dagen" (all day)
        if timeInfo.contains("Hele dagen") {
            return ("00:00", "23:59")
        }

        return ("", "")
    }

    // MARK: - Parse Date

    /// Parses date string from data-date attribute (format: "2026-02-03")
    private static func parseDate(from dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateString)
    }

    // MARK: - Parse Lesson Content

    /// Parses the lesson detail page (aktivitetforside2.aspx) into structured content.
    /// The input HTML should be the full page; we extract `#homeworkContentContainer`.
    static func parseLessonContent(from html: String) throws -> LessonContent {
        let doc = try SwiftSoup.parse(html)

        guard let container = try doc.select("#homeworkContentContainer").first() else {
            print("⚠️ homeworkContentContainer not found")
            return .empty
        }

        // Extract teacher note from textarea (lives in actHeader, outside inlineHomeworkDiv —
        // must be read before the empty-content early return below, otherwise lessons with
        // only a teacher note and no Lektier render as blank.
        let teacherNote: String?
        if let textarea = try container.select("textarea.activity-note").first() {
            let text = try textarea.text().trimmingCharacters(in: .whitespacesAndNewlines)
            teacherNote = text.isEmpty ? nil : text
        } else {
            teacherNote = nil
        }

        // Check for empty state
        let inlineDiv = try container.select("#s_m_Content_Content_tocAndToolbar_inlineHomeworkDiv").first() ?? container
        let fullText = try inlineDiv.text()
        if fullText.contains("Aktiviteten har ikke noget indhold") {
            return LessonContent(teacherNote: teacherNote, items: [])
        }

        // Parse content items
        var items: [LessonContentItem] = []
        var currentSectionIsHomework = true // default to homework if first section

        // Walk through all direct children of the inline homework div
        let children = inlineDiv.children()

        for child in children {
            // Check if this is a section heading container
            let sectionHeading = try child.select("h1.ls-paper-section-heading").first()
            if let heading = sectionHeading {
                let headingText = try heading.text().trimmingCharacters(in: .whitespacesAndNewlines)
                if headingText == "Lektier" {
                    currentSectionIsHomework = true
                } else if headingText == "Øvrigt indhold" {
                    currentSectionIsHomework = false
                }
                continue
            }

            // Check if this is a content block (div with ACH id containing an article)
            let childId = try child.attr("id")
            guard childId.hasPrefix("ACH"),
                  let article = try child.select("article.lc-display-fragment").first() else {
                continue
            }

            let item = try parseContentArticle(article, id: childId, isHomework: currentSectionIsHomework)
            items.append(item)
        }

        print("📝 Parsed lesson content: \(items.count) items (\(items.filter { $0.isHomework }.count) homework), teacherNote: \(teacherNote != nil)")

        return LessonContent(teacherNote: teacherNote, items: items)
    }

    /// Parses a single `<article>` element into a `LessonContentItem`.
    private static func parseContentArticle(_ article: Element, id: String, isHomework: Bool) throws -> LessonContentItem {
        // Homework flag override via icon style
        let styledEls = try article.select("[style*=doc-homework]")
        var itemIsHomework = isHomework
        if !styledEls.isEmpty() {
            let styles = try styledEls.array().map { try $0.attr("style") }
            itemIsHomework = !styles.allSatisfy { $0.contains("doc-not-homework") }
        }

        // Title element — hasTitleHeader derived from same query to avoid duplicate traversal
        let titleEl: Element?
        let hasTitleHeader: Bool
        if let header = try article.select("h2[id*=titleHeader]").first() {
            titleEl = header
            hasTitleHeader = true
        } else {
            titleEl = try article.select("h1[style*=doc-], h2[style*=doc-]").first()
            hasTitleHeader = false
        }
        let title = try titleEl.map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }

        // Note
        let note: String?
        if let bq = try article.select("blockquote[data-lc-role=note]").first() {
            let t = try bq.text().trimmingCharacters(in: .whitespacesAndNewlines)
            note = t.isEmpty ? nil : t
        } else {
            note = nil
        }

        // Links (kept for title-as-link dedup in view)
        var links: [LessonLink] = []
        for linkEl in try article.select("a[data-lc-display-linktype]") {
            let href = try linkEl.attr("href")
            let text = try linkEl.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty else { continue }
            let rawType = try linkEl.attr("data-lc-display-linktype")
            let type: LessonLinkType = rawType == "file" ? .file : .external
            links.append(LessonLink(title: text.isEmpty ? href : text, url: href, type: type))
        }

        // Blocks
        var blocks: [ContentBlock] = []
        var titleSkipped = false

        for child in article.children() {
            let tag = child.tagName()
            let style = try child.attr("style")
            let childId = try child.attr("id")

            // Skip the title element (only once)
            if !titleSkipped {
                if hasTitleHeader && childId.contains("titleHeader") {
                    titleSkipped = true
                    continue
                } else if !hasTitleHeader &&
                    (style.contains("doc-homework") || style.contains("doc-not-homework")) &&
                    (tag == "h1" || tag == "h2") {
                    titleSkipped = true
                    continue
                }
            }

            // Skip blockquote note
            if tag == "blockquote" { continue }

            switch tag {
            case "h1", "h2", "h3":
                let level = tag == "h1" ? 1 : (tag == "h2" ? 2 : 3)
                let inlines = try parseInlines(child)
                guard !isEffectivelyEmpty(inlines) else { continue }
                blocks.append(.heading(level: level, inlines: inlines))

            case "p":
                let inlines = try parseInlines(child)
                guard !isEffectivelyEmpty(inlines) else { continue }
                // Promote <p><img only></p> to a block-level image
                if inlines.count == 1, case .image(let url, let alt) = inlines[0] {
                    blocks.append(.image(url: url, alt: alt))
                } else {
                    blocks.append(.paragraph(inlines: inlines))
                }

            case "img":
                let src = try child.attr("src")
                let alt = try child.attr("alt")
                guard !src.isEmpty, !src.contains("/lectio/img/") else { continue }
                blocks.append(.image(url: src, alt: alt))

            case "hr":
                blocks.append(.divider)

            default:
                break
            }
        }

        return LessonContentItem(
            id: id,
            title: title,
            note: note,
            blocks: blocks,
            links: links,
            isHomework: itemIsHomework
        )
    }

    /// Returns true if inlines contain only empty/whitespace text nodes.
    /// Note: parseInlines already normalises NBSP to spaces, so no special NBSP handling is needed here.
    private static func isEffectivelyEmpty(_ inlines: [InlineElement]) -> Bool {
        for inline in inlines {
            switch inline {
            case .text(let s):
                if !s.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            case .link, .image:
                return false
            }
        }
        return true
    }

    // MARK: - Parse Inlines

    /// Walks the child nodes of `element` and returns a flat array of InlineElement.
    /// Skips Lectio UI icon images (src containing "/lectio/img/").
    /// Recurses into span/strong/em/b/i elements.
    static func parseInlines(_ element: Element) throws -> [InlineElement] {
        var result: [InlineElement] = []
        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                let raw = textNode.getWholeText()
                let str = raw
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    result.append(.text(str))
                }
            } else if let el = node as? Element {
                switch el.tagName() {
                case "a":
                    let href = try el.attr("href")
                    let text = try el.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !href.isEmpty, !text.isEmpty else { continue }
                    let rawType = try el.attr("data-lc-display-linktype")
                    let type: LessonLinkType = rawType == "file" ? .file : .external
                    result.append(.link(text: text, url: href, type: type))
                case "img":
                    let src = try el.attr("src")
                    let alt = try el.attr("alt")
                    guard !src.isEmpty, !src.contains("/lectio/img/") else { continue }
                    result.append(.image(url: src, alt: alt))
                case "br":
                    result.append(.text("\n"))
                case "span", "strong", "em", "b", "i":
                    result += try parseInlines(el)
                default:
                    result += try parseInlines(el)
                }
            }
        }
        return result
    }

    // MARK: - Parse Homework Overview

    /// Parses the homework overview page (material_lektieoversigt.aspx) into HomeworkEntry array.
    /// Extracts date, activity info (hold, teacher, room), note, and individual homework items.
    static func parseHomeworkOverview(from html: String) throws -> [HomeworkEntry] {
        let doc = try SwiftSoup.parse(html)

        guard let table = try doc.select("table#s_m_Content_Content_MaterialLektieOverblikGV").first() else {
            print("⚠️ Homework overview table not found")
            return []
        }

        let rows = try table.select("tr")
        var entries: [HomeworkEntry] = []
        let currentYear = Calendar.current.component(.year, from: Date())

        for row in rows {
            // Skip header row
            let headerCells = try row.select("th")
            if !headerCells.isEmpty() { continue }

            // Use desktop columns (OnlyDesktop)
            let cells = try row.select("td.OnlyDesktop")
            guard cells.count >= 3 else { continue }

            // Column 0: Date (e.g. "fr 13/3")
            let displayDate = try cells[0].text().trimmingCharacters(in: .whitespacesAndNewlines)

            // Column 1: Activity link with tooltip
            guard let activityLink = try cells[1].select("a.s2skemabrik").first() else { continue }

            let tooltip = try activityLink.attr("data-tooltip")
            let brikId = try activityLink.attr("data-brikid")
            let absId = brikId.replacingOccurrences(of: "ABS", with: "")

            // Determine status from CSS classes
            let status: EventStatus
            if try activityLink.hasClass("s2cancelled") {
                status = .cancelled
            } else if try activityLink.hasClass("s2changed") {
                status = .changed
            } else {
                status = .normal
            }

            // Reuse tooltip parser for hold, teacher, room, and activity title
            let (hold, _, teacher, room, _, _, activityTitle, _, _) = parseTooltip(tooltip)

            // Parse date into Date value
            let date = parseHomeworkDate(displayDate, currentYear: currentYear)

            // Column 2: Note & Lektier
            let contentCell = cells[2]
            let (note, homeworkItems) = try parseHomeworkContentCell(contentCell, absId: absId)

            guard !homeworkItems.isEmpty || note != nil else { continue }

            entries.append(HomeworkEntry(
                id: absId,
                date: date,
                displayDate: displayDate,
                hold: hold,
                title: activityTitle,
                teacher: teacher,
                room: room,
                status: status,
                note: note,
                items: homeworkItems
            ))
        }

        print("📝 Parsed homework overview: \(entries.count) entries")
        return entries
    }

    /// Parses the "Note & Lektier" cell into a note string and homework items.
    private static func parseHomeworkContentCell(_ cell: Element, absId: String) throws -> (note: String?, items: [HomeworkItem]) {
        var items: [HomeworkItem] = []
        var noteParts: [String] = []
        var itemIndex = 0

        // Walk through child nodes to separate note text from homework items
        let children = cell.getChildNodes()
        var currentText = ""

        for child in children {
            if let element = child as? Element {
                if element.tagName() == "br" {
                    // Line break - flush current text as note if before any homework
                    if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && items.isEmpty {
                        noteParts.append(currentText.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    currentText = ""
                } else if element.tagName() == "img" {
                    let src = try element.attr("src")
                    if src.contains("doc-homework") {
                        // Flush any preceding text as note
                        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && items.isEmpty {
                            noteParts.append(currentText.trimmingCharacters(in: .whitespacesAndNewlines))
                            currentText = ""
                        }
                        // Next sibling text or link is the homework item
                    }
                } else if element.tagName() == "a" {
                    let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    let href = try element.attr("href")
                    guard !text.isEmpty else { continue }

                    // Check if this link is preceded by a homework icon
                    let prevSibling = child.previousSibling()
                    let isHomeworkLink: Bool
                    if let prevEl = prevSibling as? Element, prevEl.tagName() == "img" {
                        let src = try prevEl.attr("src")
                        isHomeworkLink = src.contains("doc-homework")
                    } else {
                        // Links inside homework cells that have doc-homework img anywhere are homework
                        isHomeworkLink = try !cell.select("img[src*=doc-homework]").isEmpty()
                    }

                    if isHomeworkLink {
                        items.append(HomeworkItem(
                            id: "\(absId)_\(itemIndex)",
                            text: text,
                            url: href.hasPrefix("http") ? href : nil
                        ))
                        itemIndex += 1
                    } else {
                        noteParts.append(text)
                    }
                } else if element.tagName() == "div", try element.hasClass("ls-homework-note") {
                    // Sub-note for a homework item (e.g. "læs. 11-18")
                    let noteText = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !noteText.isEmpty, let lastIdx = items.indices.last {
                        var updated = items[lastIdx]
                        items[lastIdx] = HomeworkItem(
                            id: updated.id,
                            text: "\(updated.text) (\(noteText))",
                            url: updated.url
                        )
                    }
                } else {
                    let text = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        currentText += text
                    }
                }
            } else if let textNode = child as? TextNode {
                let text = textNode.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    // Check if preceded by homework icon
                    let prevSibling = child.previousSibling()
                    if let prevEl = prevSibling as? Element, prevEl.tagName() == "img",
                       try prevEl.attr("src").contains("doc-homework") {
                        items.append(HomeworkItem(
                            id: "\(absId)_\(itemIndex)",
                            text: text,
                            url: nil
                        ))
                        itemIndex += 1
                    } else if items.isEmpty {
                        currentText += text
                    }
                }
            }
        }

        // Flush remaining text as note
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && items.isEmpty {
            noteParts.append(currentText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let note = noteParts.isEmpty ? nil : noteParts.joined(separator: "\n")
        return (note, items)
    }

    /// Parses a display date like "fr 13/3" or "ma 16/3" into a Date.
    private static func parseHomeworkDate(_ displayDate: String, currentYear: Int) -> Date {
        // Format: "fr 13/3" or "ma 16/3" - day abbreviation + day/month
        let parts = displayDate.split(separator: " ")
        guard parts.count >= 2 else { return Date() }

        let datePart = parts.last!
        let dayMonth = datePart.split(separator: "/")
        guard dayMonth.count == 2,
              let day = Int(dayMonth[0]),
              let month = Int(dayMonth[1]) else { return Date() }

        var comps = DateComponents()
        comps.day = day
        comps.month = month
        comps.year = currentYear
        comps.timeZone = TimeZone.current

        return Calendar.current.date(from: comps) ?? Date()
    }
}
