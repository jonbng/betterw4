//
//  W4ClassParser.swift
//  BetterW4
//
//  `academics/classes/myclasses` and `academics/classes/class&class_id=`.
//
//  Live capture 19 Aug 2026. The list is a `dl.class-list` of subject `<dt>`s
//  and one `<a class_id>` per class. The class page is `dl.class-details`
//  (subject / year / block / level / room) plus `ul.student-list` under
//  Teacher and Students headings.
//
//  Purity: `nonisolated`, synchronous, `(String) -> Model`. No network.
//  PII: names and UWC ids are never logged.
//

import Foundation
import SwiftSoup

enum W4ClassParser {

    struct ClassCaption: Equatable, Sendable {
        let code: String
        let subject: String
        let year: String?
        let level: ClassLevel
        let teacher: String?
        let room: String?
    }

    private static let captionPattern =
        #"^([A-Za-z0-9]+):\s*(.+?)\s+(\d+)\s*(?:st|nd|rd|th)?\s*Year\s+([A-Z])\s+level(?:\s+with\s+(.+?))?(?:\s+in room\s+(.+))?$"#
    private static let leadingCodePattern = #"^([A-Z]{3,5})\s+(.+)$"#
    private static let yearNumberPattern = #"\d+"#

    // MARK: - Caption

    nonisolated static func parseCaption(_ caption: String) -> ClassCaption? {
        let clean = collapse(caption.replacingOccurrences(of: "\u{00a0}", with: " "))
        guard let match = captures(captionPattern, in: clean, count: 6) else { return nil }
        let code = match[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = match[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let year = match[2].trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let level = ClassLevel.parse(match[3])
        let teacher = match[4].trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let room = match[5].trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard !code.isEmpty, !subject.isEmpty else { return nil }
        return ClassCaption(
            code: code,
            subject: subject,
            year: year,
            level: level,
            teacher: teacher,
            room: room
        )
    }

    // MARK: - Index

    /// Classes on My classes, in document order.
    nonisolated static func parseIndex(_ html: String) -> [MyClass] {
        guard let document = try? SwiftSoup.parse(html, W4Routes.origin) else { return [] }
        let root = contentRoot(of: document)
        let list = firstElement(root, "dl.class-list") ?? root
        var order: [String] = []
        var byId: [String: MyClass] = [:]
        var subjectHeading: String?

        for child in list.children() {
            switch child.tagName().lowercased() {
            case "dt":
                subjectHeading = text(of: child).nilIfEmpty
            case "dd":
                for anchor in elements(child, "a[href*=class_id]") {
                    guard let parsed = parseListLink(anchor, subjectHeading: subjectHeading) else { continue }
                    let key = parsed.id.lowercased()
                    if byId[key] == nil {
                        byId[key] = parsed
                        order.append(key)
                    }
                }
            default:
                continue
            }
        }

        if order.isEmpty {
            for anchor in elements(root, "a[href*=class_id]") {
                guard let parsed = parseListLink(anchor, subjectHeading: nil) else { continue }
                let key = parsed.id.lowercased()
                if byId[key] == nil {
                    byId[key] = parsed
                    order.append(key)
                }
            }
        }

        return order.compactMap { byId[$0] }
    }

    // MARK: - Class page

    nonisolated static func parseClass(_ html: String, classId explicitId: String? = nil) -> MyClass {
        guard let document = try? SwiftSoup.parse(html, W4Routes.origin) else {
            let id = explicitId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "unknown"
            return MyClass(id: id, subject: id, loaded: true)
        }
        let root = contentRoot(of: document)
        let headingId = firstElement(root, "h2")
            .map { text(of: $0) }
            .flatMap { heading -> String? in
                let stripped: String
                if heading.lowercased().hasPrefix("class") {
                    stripped = heading.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    stripped = heading
                }
                return stripped.nilIfEmpty
            }
        let id = explicitId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? headingId
            ?? classIdFromHref(html)
            ?? "unknown"

        let fields = parseDetails(firstElement(root, "dl.class-details"))
        let parsedId = W4ClassId.parse(id)
        let subjectRaw = fields["subject"]
        let subjectCode = parsedId?.subjectCode
            ?? leadingCode(in: subjectRaw)?.code
        let subject = stripSubjectCode(subjectRaw, code: subjectCode)?.nilIfEmpty
            ?? subjectCode
            ?? id

        let year = yearNumber(fields["year"]) ?? parsedId.map { String($0.year) }
        let block = fields["block"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? parsedId?.block
        let levelRaw = fields["level"]
        let level = {
            let parsed = ClassLevel.parse(levelRaw)
            if parsed != .unknown { return parsed }
            if let letter = parsedId.map({ String($0.level) }) {
                return ClassLevel.parse(letter)
            }
            return .unknown
        }()
        let levelLabel = levelLabelFrom(levelRaw, level: level)
        let room = parseRoom(firstElement(root, "dl.class-details"))

        var teachers: [ClassMember] = []
        var students: [ClassMember] = []
        var section: MemberSection = .none
        for child in root.children() {
            switch child.tagName().lowercased() {
            case "h3":
                section = classifySection(text(of: child))
            case "ul":
                guard classNames(of: child).contains("student-list") else { continue }
                switch section {
                case .teachers:
                    teachers.append(contentsOf: parseMembers(child, defaultKind: .staff))
                case .students:
                    students.append(contentsOf: parseMembers(child, defaultKind: .student))
                case .none:
                    continue
                }
            default:
                continue
            }
        }

        return MyClass(
            id: id,
            subject: subject,
            subjectCode: subjectCode,
            year: year,
            block: block,
            level: level,
            levelLabel: levelLabel,
            room: room,
            teachers: uniqued(teachers),
            students: uniqued(students),
            loaded: true
        )
    }

    nonisolated static func merge(base: MyClass, detail: MyClass) -> MyClass {
        MyClass(
            id: base.id,
            subject: preferSubjectName(base.subject, detail.subject),
            subjectCode: detail.subjectCode ?? base.subjectCode,
            year: detail.year ?? base.year,
            block: detail.block ?? base.block,
            level: detail.level != .unknown ? detail.level : base.level,
            levelLabel: detail.levelLabel ?? base.levelLabel,
            room: detail.room ?? base.room,
            teachers: detail.teachers.isEmpty ? base.teachers : detail.teachers,
            students: detail.students.isEmpty ? base.students : detail.students,
            loaded: detail.loaded || base.loaded
        )
    }

    nonisolated static func classIdFromHref(_ href: String) -> String? {
        ClassRoster.classId(from: href)
    }

    nonisolated static func roomIdFromHref(_ href: String) -> String? {
        guard !href.isEmpty else { return nil }
        let decoded = href.removingPercentEncoding ?? href
        guard let match = firstCapture(#"(?:^|[?&])room_id=([^&#]+)"#, in: decoded) else {
            return nil
        }
        let id = (match.removingPercentEncoding ?? match)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    // MARK: - List link

    private nonisolated static func parseListLink(
        _ anchor: Element,
        subjectHeading: String?
    ) -> MyClass? {
        let href = absHref(anchor)
        guard let id = classIdFromHref(href) else { return nil }
        let caption = collapse(text(of: anchor).replacingOccurrences(of: "\u{00a0}", with: " "))
        let parsedId = W4ClassId.parse(id)
        let match = captures(captionPattern, in: caption, count: 6)
        let restSubject = match?[1].trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let year = match?[2].trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? parsedId.map { String($0.year) }
        let levelChar = match?[3]
        let level = {
            let parsed = ClassLevel.parse(levelChar)
            if parsed != .unknown { return parsed }
            if let letter = parsedId.map({ String($0.level) }) {
                return ClassLevel.parse(letter)
            }
            return .unknown
        }()
        let teacherName = match?[4].trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let roomName = match?[5].trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let subject = subjectHeading?.nilIfEmpty
            ?? restSubject
            ?? parsedId?.subjectCode
            ?? id
        let teachers = teacherName.map {
            [
                ClassMember(
                    id: slug("teacher-\($0)"),
                    name: $0,
                    kind: .staff
                )
            ]
        } ?? []
        return MyClass(
            id: id,
            subject: subject,
            subjectCode: parsedId?.subjectCode,
            year: year,
            block: parsedId?.block,
            level: level,
            levelLabel: level.badge.nilIfEmpty,
            room: roomName.map { ClassRoom(id: nil, name: $0) },
            teachers: teachers,
            loaded: false
        )
    }

    // MARK: - Details

    private nonisolated static func parseDetails(_ dl: Element?) -> [String: String] {
        guard let dl else { return [:] }
        var fields: [String: String] = [:]
        var pending: String?
        for child in dl.children() {
            switch child.tagName().lowercased() {
            case "dt":
                pending = text(of: child)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                    .lowercased()
                    .nilIfEmpty
            case "dd":
                guard let key = pending else { continue }
                let value = collapse(text(of: child).replacingOccurrences(of: "\u{00a0}", with: " "))
                if !value.isEmpty { fields[key] = value }
                pending = nil
            default:
                continue
            }
        }
        return fields
    }

    private nonisolated static func parseRoom(_ dl: Element?) -> ClassRoom? {
        guard let dl else { return nil }
        var pending: String?
        for child in dl.children() {
            switch child.tagName().lowercased() {
            case "dt":
                pending = text(of: child)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                    .lowercased()
            case "dd":
                defer { pending = nil }
                guard pending == "room" else { continue }
                let link = firstElement(child, "a[href*=room_id]")
                let name = collapse(
                    (link.map { text(of: $0) } ?? text(of: child))
                        .replacingOccurrences(of: "\u{00a0}", with: " ")
                )
                guard !name.isEmpty else { return nil }
                let href = link.map(absHref) ?? ""
                return ClassRoom(id: roomIdFromHref(href), name: name)
            default:
                continue
            }
        }
        return nil
    }

    // MARK: - Members

    private enum MemberSection {
        case none, teachers, students
    }

    private nonisolated static func parseMembers(
        _ list: Element,
        defaultKind: DirectoryPersonKind
    ) -> [ClassMember] {
        var order: [String] = []
        var byId: [String: ClassMember] = [:]
        let items = elements(list, "> li").isEmpty
            ? list.children().array().filter { $0.tagName().lowercased() == "li" }
            : elements(list, "> li")
        for item in items {
            guard let member = parseMember(item, defaultKind: defaultKind) else { continue }
            if byId[member.id] == nil {
                byId[member.id] = member
                order.append(member.id)
            }
        }
        return order.compactMap { byId[$0] }
    }

    private nonisolated static func parseMember(
        _ item: Element,
        defaultKind: DirectoryPersonKind
    ) -> ClassMember? {
        let links = elements(item, "a[href*=uwc_id]")
        guard !links.isEmpty else { return nil }
        let named = links.first { firstElement($0, "img") == nil } ?? links.first
        guard let named else { return nil }
        let href = absHref(named)
        guard let id = W4PeopleParser.uwcId(fromHref: href) else { return nil }
        let kind = W4PeopleParser.kind(fromHref: href) ?? defaultKind
        var name = (ownText(of: named).nilIfEmpty ?? text(of: named))
            .replacingOccurrences(
                of: #"Photo of\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.caseInsensitiveCompare(id) == .orderedSame {
            name = id
        }
        let img = firstElement(item, "img.photo") ?? firstElement(item, "img")
        let photo = img.flatMap {
            W4PeopleParser.photoURL(fromSource: attribute($0, "src"), uwcId: id)
        }
        let overlay = firstElement(item, ".level-overlay")
            .map { text(of: $0) }?
            .nilIfEmpty
        return ClassMember(
            id: id,
            name: name,
            kind: kind,
            photoURL: photo,
            level: ClassLevel.parse(overlay)
        )
    }

    private nonisolated static func classifySection(_ title: String) -> MemberSection {
        let compact = title.lowercased().filter(\.isLetter)
        if compact.hasPrefix("teacher") { return .teachers }
        if compact.hasPrefix("student") { return .students }
        return .none
    }

    // MARK: - Subject / level helpers

    private nonisolated static func yearNumber(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return firstCapture(yearNumberPattern, in: raw)
    }

    private nonisolated static func leadingCode(in raw: String?) -> (code: String, rest: String)? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              let match = captures(leadingCodePattern, in: text, count: 2, caseInsensitive: false)
        else { return nil }
        return (match[0], match[1])
    }

    private nonisolated static func stripSubjectCode(_ raw: String?, code: String?) -> String? {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return nil }
        if let code, !code.isEmpty, text.lowercased().hasPrefix(code.lowercased()) {
            let stripped = text.dropFirst(code.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? text : stripped
        }
        return leadingCode(in: text)?.rest ?? text
    }

    private nonisolated static func preferSubjectName(_ left: String, _ right: String) -> String {
        let leftCode = leadingCode(in: left)
        let rightCode = leadingCode(in: right)
        let preferred: String
        if leftCode != nil, rightCode == nil {
            preferred = right
        } else if rightCode != nil, leftCode == nil {
            preferred = left
        } else if right.count > left.count {
            preferred = right
        } else {
            preferred = left
        }
        return preferred.nilIfEmpty ?? left.nilIfEmpty ?? right
    }

    private nonisolated static func levelLabelFrom(_ raw: String?, level: ClassLevel) -> String? {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { return level.badge.nilIfEmpty }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        let long = words.dropFirst().joined(separator: " ").nilIfEmpty ?? words.last ?? ""
        switch level {
        case .higher: return "HL"
        case .standard: return "SL"
        case .combined: return long.nilIfEmpty ?? "Combined"
        case .none: return nil
        case .unknown: return long.nilIfEmpty ?? text
        }
    }

    private nonisolated static func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        let dashed = lowered.replacingOccurrences(
            of: #"\s+"#,
            with: "-",
            options: .regularExpression
        )
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "@._+-"))
        let filtered = dashed.unicodeScalars.map { allowed.contains($0) ? Character($0) : nil }
            .compactMap { $0 }
        let result = String(filtered)
        return result.isEmpty ? value : result
    }

    private nonisolated static func uniqued(_ members: [ClassMember]) -> [ClassMember] {
        var seen = Set<String>()
        return members.filter { seen.insert($0.id).inserted }
    }

    // MARK: - DOM

    private nonisolated static func contentRoot(of document: Document) -> Element {
        if let inner = firstElement(document, "#content_inner") { return inner }
        if let main = firstElement(document, "#content_main") { return main }
        if let body = document.body() { return body }
        return document
    }

    private nonisolated static func firstElement(_ root: Element, _ query: String) -> Element? {
        guard let found = try? root.select(query) else { return nil }
        return found.first()
    }

    private nonisolated static func elements(_ root: Element, _ query: String) -> [Element] {
        guard let found = try? root.select(query) else { return [] }
        return found.array()
    }

    private nonisolated static func text(of element: Element) -> String {
        collapse((try? element.text()) ?? "")
    }

    private nonisolated static func ownText(of element: Element) -> String {
        collapse((try? element.ownText()) ?? "")
    }

    private nonisolated static func attribute(_ element: Element, _ name: String) -> String {
        ((try? element.attr(name)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func absHref(_ element: Element) -> String {
        let abs = ((try? element.absUrl("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !abs.isEmpty { return abs }
        return attribute(element, "href")
    }

    private nonisolated static func classNames(of element: Element) -> Set<String> {
        let raw = ((try? element.attr("class")) ?? "").lowercased()
        return Set(raw.split(whereSeparator: { $0.isWhitespace }).map(String.init))
    }

    private nonisolated static func collapse(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private nonisolated static func captures(
        _ pattern: String,
        in text: String,
        count: Int,
        caseInsensitive: Bool = true
    ) -> [String]? {
        guard !text.isEmpty, count > 0 else { return nil }
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > count else { return nil }
        var result: [String] = []
        for index in 1...count {
            guard let captured = Range(match.range(at: index), in: text) else {
                result.append("")
                continue
            }
            result.append(String(text[captured]))
        }
        return result
    }

    private nonisolated static func firstCapture(_ pattern: String, in text: String) -> String? {
        captures(pattern, in: text, count: 1)?.first?.nilIfEmpty
    }
}
