//
//  W4CampusStatusParser.swift
//  BetterW4
//
//  Reads the campus-status control out of the chrome of any authenticated W4
//  page, and builds the exact `r=site/setstatus` POST body.
//
//  Everything this file parses is [V] — verified against the real Home capture
//  `references/pages/UWCRCN W4.html:38-49` and the script W4 serves,
//  `UWCRCN W4_files/campusstatusdropdown.js`.
//
//  ```html
//  <div class="status-dropdown">
//    <div class="status oncampus">
//      <div class="status-value">on campus</div>
//      <div class="location"></div>          <!-- empty while on campus -->
//    </div>
//  </div>
//  <div class="selection-box">
//    <span id="location">
//      <input value="oncampus" id="location_0" checked="checked" type="radio" name="location">
//      <label for="location_0">On campus</label>
//      … location_1 … location_10 …
//    </span>
//    <input maxlength="20" type="text" value="" name="other" id="other">
//  </div>
//  ```
//
//  Bugs deliberately NOT copied from the Kotlin port
//  (`android/.../feature/campus/CampusStatusParser.kt`):
//
//  * **B6** — it maps radios to their *labels* and posts the label. Two of the
//    eleven options break: "On campus" must post `status=on` with **no**
//    `location` key at all, and "Other" must post the `#other` free text.
//    This parser keeps `value` and `label` apart (plan D-12).
//  * **B7** — `campusstatusdropdown.js:28` writes `'(' + location + ')'` into
//    `div.location` after a successful POST, so a page rendered after a
//    client-side update shows `(At Raudbua)`. Strip one wrapping pair.
//
//  Pure, synchronous and `nonisolated` (plan D-30): no I/O, no singletons.
//

import Foundation
import SwiftSoup

enum W4CampusStatusParser {

    /// `POST index.php?r=site/setstatus` — published by the page itself as
    /// `var status_urls = {'set':'/index.php?r=site/setstatus'}` [V].
    static let setStatusRoute = W4Routes.R.setStatus

    // MARK: - Reading

    /// Parses the campus control out of any authenticated W4 page.
    ///
    /// Returns `nil` when the page carries no campus chrome at all (the login
    /// page, an AJAX fragment, a parse failure). Never throws: a malformed page
    /// degrades to `nil` plus a logged warning.
    nonisolated static func parse(_ html: String) -> CampusStatus? {
        guard !html.isEmpty else { return nil }
        do {
            return try parse(document: try SwiftSoup.parse(html))
        } catch {
            warn("could not parse the campus chrome: \(error)")
            return nil
        }
    }

    private nonisolated static func parse(document: Document) throws -> CampusStatus? {
        let dropdown = try document.select(".status-dropdown").first()
        let statusElement = try document.select(".status-dropdown .status").first()
        let (parsedOptions, checkedID) = try parseOptions(in: document)

        // No widget, no state node, no radios: this page has no campus chrome.
        guard dropdown != nil || statusElement != nil || !parsedOptions.isEmpty else {
            return nil
        }

        let options = parsedOptions.isEmpty ? CampusStatus.defaultOptions : parsedOptions
        if parsedOptions.isEmpty {
            warn("no location radios on the page; falling back to the 11 captured options")
        }

        let isOnCampus = try resolveIsOnCampus(
            statusElement: statusElement,
            options: options,
            checkedID: checkedID
        )

        var location: String?
        if let locationElement = try statusElement?.select(".location").first() {
            location = normalizedLocation(try locationElement.text())
        }

        return CampusStatus(
            isOnCampus: isOnCampus,
            // `div.location` is rendered empty while on campus [V]; keep the
            // model honest rather than carrying a stale off-campus string.
            location: isOnCampus ? nil : location,
            options: options,
            selectedOptionID: parsedOptions.isEmpty ? nil : checkedID
        )
    }

    // MARK: - Writing

    /// The exact `r=site/setstatus` body for one option (plan D-12, bug B6).
    ///
    /// * on-campus option  → `["status": "on"]` — **no `location` key at all**
    /// * free-text option  → `["status": "off", "location": <trimmed #other text>]`
    /// * every other option → `["status": "off", "location": <option.value>]`
    ///
    /// Returns `nil` when the free-text option was chosen without any text, which
    /// is exactly what `campusstatusdropdown.js:12-15` refuses to post. Callers
    /// must ask the student for a location instead of sending a meaningless body.
    nonisolated static func setStatusBody(
        option: CampusLocationOption,
        freeText: String? = nil
    ) -> [String: String]? {
        if option.isOnCampus {
            return ["status": "on"]
        }

        let location: String
        if option.isFreeText {
            let trimmed = trim(freeText ?? "")
            guard !trimmed.isEmpty else { return nil }
            // `input#other[maxlength=20]` [V] — enforce it here too, because the
            // UI's limit is only advisory.
            location = String(trimmed.prefix(CampusStatus.freeTextMaxLength))
        } else {
            location = trim(option.value)
        }

        guard !location.isEmpty else { return nil }
        return ["status": "off", "location": location]
    }

    /// The same body from raw state, for callers that already know where the
    /// student is (optimistic updates, the demo session).
    ///
    /// Note there is no length cap here: several captured option values are far
    /// longer than 20 characters ("In Library/Study room (after 10:30pm)"); the
    /// `maxlength` applies to the free-text field only.
    nonisolated static func setStatusBody(onCampus: Bool, location: String?) -> [String: String] {
        if onCampus { return ["status": "on"] }
        let trimmed = trim(location ?? "")
        guard !trimmed.isEmpty else { return ["status": "off"] }
        return ["status": "off", "location": trimmed]
    }

    // MARK: - Options

    private nonisolated static func parseOptions(
        in document: Document
    ) throws -> (options: [CampusLocationOption], checkedID: String?) {
        var radios = try document.select("#location input[type=radio]").array()
        if radios.isEmpty {
            radios = try document.select("input[type=radio][name=location]").array()
        }
        guard !radios.isEmpty else { return ([], nil) }

        let labels = try labelTexts(in: document)
        var options: [CampusLocationOption] = []
        var checkedID: String?

        for (index, radio) in radios.enumerated() {
            let value = trim(try radio.attr("value"))
            // A radio with no value cannot be posted, so it cannot be offered.
            guard !value.isEmpty else { continue }

            let domID = trim(try radio.attr("id"))
            let id = domID.isEmpty ? "location_\(index)" : domID
            let label = labels[domID].flatMap { $0.isEmpty ? nil : $0 } ?? fallbackLabel(for: value)

            options.append(CampusLocationOption(id: id, value: value, label: label))
            if checkedID == nil, radio.hasAttr("checked") {
                checkedID = id
            }
        }

        return (options, checkedID)
    }

    /// `label[for=…]` → text, for every label in the document.
    ///
    /// Built as a map on purpose: a `label[for='\(id)']` selector would have to
    /// escape ids containing quotes or slashes (parsers.md §0.5.2).
    private nonisolated static func labelTexts(in document: Document) throws -> [String: String] {
        var map: [String: String] = [:]
        for label in try document.select("label[for]").array() {
            let key = try label.attr("for")
            guard !key.isEmpty, map[key] == nil else { continue }
            map[key] = trim(try label.text())
        }
        return map
    }

    private nonisolated static func fallbackLabel(for value: String) -> String {
        if value.caseInsensitiveCompare(CampusLocationOption.onCampusValue) == .orderedSame {
            return "On campus"
        }
        if value.caseInsensitiveCompare(CampusLocationOption.freeTextValue) == .orderedSame {
            return "Other"
        }
        return value
    }

    // MARK: - State

    private nonisolated static func resolveIsOnCampus(
        statusElement: Element?,
        options: [CampusLocationOption],
        checkedID: String?
    ) throws -> Bool {
        if let statusElement {
            if statusElement.hasClass("oncampus") { return true }
            if statusElement.hasClass("offcampus") { return false }

            let value = trim(try statusElement.select(".status-value").first()?.text() ?? "")
                .lowercased()
            if value.contains("off campus") || value.contains("offcampus") { return false }
            if value.contains("on campus") || value.contains("oncampus") { return true }
        }

        if let checkedID, let checked = options.first(where: { $0.id == checkedID }) {
            return checked.isOnCampus
        }

        warn("campus chrome carries no readable state; assuming on campus")
        return true
    }

    // MARK: - Location text

    /// Trims, strips one wrapping `(…)` pair (bug B7), and maps blank to `nil`.
    nonisolated static func normalizedLocation(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = trim(raw)
        guard !trimmed.isEmpty else { return nil }
        let unwrapped = trim(strippingWrappingParentheses(trimmed))
        return unwrapped.isEmpty ? nil : unwrapped
    }

    /// `"(At Raudbua)"` → `"At Raudbua"`, but `"(A) and (B)"` is left alone: the
    /// leading `(` must actually be the partner of the trailing `)`.
    private nonisolated static func strippingWrappingParentheses(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("("), value.hasSuffix(")") else { return value }
        let inner = value.dropFirst().dropLast()
        var depth = 0
        for character in inner {
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth < 0 { return value }
            }
        }
        guard depth == 0 else { return value }
        return String(inner)
    }

    // MARK: - Helpers

    private nonisolated static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func warn(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("⚠️ W4CampusStatusParser: \(message())")
        #endif
    }
}
