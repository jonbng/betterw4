//
//  CampusModels.swift
//  BetterW4
//
//  Domain models for the W4 campus-status control that lives in the page chrome
//  of every authenticated page.
//
//  Evidence: `references/pages/UWCRCN W4.html:38-49` [V] (real Home capture),
//  `UWCRCN W4_files/campusstatusdropdown.js:6-31` [V] (the write path W4 itself
//  uses) and `campusstatusdropdown.css:16-21` [V] (the `.oncampus` / `.offcampus`
//  state classes).
//
//  Plan decision D-12 / bug B6: an option carries its POST **value** and its
//  visible **label** separately. Two of the eleven options break if the label is
//  posted instead of the value — "On campus" must post `status=on` with no
//  `location` key at all, and "Other" must post the free text from `#other`.
//
//  Naming follows plan D-5: domain models the UI consumes are unprefixed.
//

import Foundation

// MARK: - Location option

/// One radio button in the campus-status widget
/// (`div.selection-box > span#location > input[type=radio] + label`).
///
/// `value` is what `r=site/setstatus` expects in its `location` field; `label`
/// is only ever shown to a human. Keeping them apart is bug B6.
struct CampusLocationOption: Identifiable, Hashable, Codable, Sendable {

    /// The radio input's DOM id, e.g. `location_2`. Stable within one render of
    /// the page, which is all the UI needs it for.
    let id: String

    /// The POST value: `oncampus`, `other`, or the location string itself
    /// (`At Raudbua`, `In A building (after 10:30pm)`, …).
    let value: String

    /// The `<label for=…>` text as W4 renders it.
    let label: String

    init(id: String, value: String, label: String) {
        self.id = id
        self.value = value
        self.label = label
    }

    /// The sentinel value that means "on campus" — posts `status=on`, no location.
    static let onCampusValue = "oncampus"

    /// The sentinel value that means "free text" — posts the `#other` field.
    static let freeTextValue = "other"

    var isOnCampus: Bool {
        value.caseInsensitiveCompare(Self.onCampusValue) == .orderedSame
    }

    var isFreeText: Bool {
        value.caseInsensitiveCompare(Self.freeTextValue) == .orderedSame
    }
}

// MARK: - Status

/// The parsed campus status: where the signed-in student currently says they are,
/// plus the option list the widget offers.
struct CampusStatus: Equatable, Codable, Sendable {

    /// `div.status-dropdown > div.status.oncampus` (green) vs `.offcampus` (red).
    let isOnCampus: Bool

    /// `div.location`, with a wrapping `(…)` stripped (bug B7).
    /// `nil` while on campus — W4 renders the node empty in that state [V].
    let location: String?

    /// Every radio in `span#location`, in document order. Falls back to
    /// ``defaultOptions`` when the widget is absent from the page.
    let options: [CampusLocationOption]

    /// The DOM id of the radio carrying `checked="checked"`, if any.
    let selectedOptionID: String?

    init(
        isOnCampus: Bool,
        location: String? = nil,
        options: [CampusLocationOption] = CampusStatus.defaultOptions,
        selectedOptionID: String? = nil
    ) {
        self.isOnCampus = isOnCampus
        self.location = location
        self.options = options
        self.selectedOptionID = selectedOptionID
    }

    /// `input#other[maxlength=20]` [V]. Enforce it in the UI *and* before posting.
    static let freeTextMaxLength = 20

    /// What the capsule button shows.
    var label: String {
        if isOnCampus { return "On campus" }
        if let location, !location.isEmpty { return location }
        return "Off campus"
    }

    /// The option the widget has selected, or the closest match to the parsed
    /// state when no radio was marked `checked`.
    var selectedOption: CampusLocationOption? {
        if let selectedOptionID,
           let match = options.first(where: { $0.id == selectedOptionID }) {
            return match
        }
        if isOnCampus { return onCampusOption }
        if let location, !location.isEmpty {
            return options.first { $0.value.caseInsensitiveCompare(location) == .orderedSame }
        }
        return nil
    }

    var onCampusOption: CampusLocationOption? {
        options.first { $0.isOnCampus }
    }

    var freeTextOption: CampusLocationOption? {
        options.first { $0.isFreeText }
    }

    /// The eleven options, verbatim and in order, from the real Home capture [V]
    /// (`UWCRCN W4.html:47`). Used only when the page does not carry the widget —
    /// a parsed list always wins.
    static let defaultOptions: [CampusLocationOption] = [
        CampusLocationOption(id: "location_0", value: "oncampus", label: "On campus"),
        CampusLocationOption(id: "location_1", value: "On a walk", label: "On a walk"),
        CampusLocationOption(id: "location_2", value: "At Raudbua", label: "At Raudbua"),
        CampusLocationOption(id: "location_3", value: "On Jarstadheia", label: "On Jarstadheia"),
        CampusLocationOption(id: "location_4", value: "On the island", label: "On the island"),
        CampusLocationOption(id: "location_5", value: "In Flekke", label: "In Flekke"),
        CampusLocationOption(id: "location_6", value: "In Dale", label: "In Dale"),
        CampusLocationOption(
            id: "location_7",
            value: "In A building (after 10:30pm)",
            label: "In A building (after 10:30pm)"
        ),
        CampusLocationOption(
            id: "location_8",
            value: "In K building (after 10:30pm)",
            label: "In K building (after 10:30pm)"
        ),
        CampusLocationOption(
            id: "location_9",
            value: "In Library/Study room (after 10:30pm)",
            label: "In Library/Study room (after 10:30pm)"
        ),
        CampusLocationOption(id: "location_10", value: "other", label: "Other")
    ]

    /// The state a demo session shows, and the safest optimistic default.
    static let onCampus = CampusStatus(
        isOnCampus: true,
        location: nil,
        options: CampusStatus.defaultOptions,
        selectedOptionID: "location_0"
    )
}
