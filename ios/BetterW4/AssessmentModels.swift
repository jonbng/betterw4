//
//  AssessmentModels.swift
//  BetterW4
//
//  Domain models for the W4 assessments calendar (`index.php?r=academics/deadlines`).
//
//  Product note (README section 4, plan section 1.3): this single W4 surface replaces BOTH of
//  BetterLectio's `lektier` and `opgaver` tabs. `Assignment`, `AssignmentDetail`,
//  `AssignmentFile`, `AssignmentSubmission`, `HomeworkEntry` and `HomeworkItem` in
//  `AssignmentModels.swift` are its Lectio ancestors and are removed in a later wave; nothing
//  here touches them.
//
//  EVIDENCE (docs/spec/parsers.md section 6, bug B12, docs/spec/reviewer-notes.md section 7):
//  the assessments calendar has NEVER been captured. Every `data-assessment-*` attribute the
//  parser reads is invented by the Android port, whose own fixture is hand-written. The only
//  independently corroborated names are the FORM fields below — `assessment_id`,
//  `student_assessment_id`, `student_deadline_date`, `student_assessment_title` — and the button
//  labels "Confirm done" / "Revert to pending" / "Save" / "Delete", which README section 5.2
//  read off a live page. Treat everything else as a hypothesis with a test attached.
//
//  Naming follows plan D-5: domain models the UI consumes are unprefixed; only wire/protocol
//  types and parsers carry the `W4` prefix.
//

import Foundation

// MARK: - Kind

/// Who owns an assessment. W4 renders both in the same month calendar, but they post
/// different id fields, so getting this wrong makes "Confirm done" silently do nothing.
///
/// Raw values mirror the (unverified) `data-assessment-type` attribute.
enum AssessmentKind: String, Codable, Sendable, CaseIterable {
    /// Set by a teacher for a class. Posts `assessment_id`.
    case classAssigned = "class"
    /// Created by the student themselves. Posts `student_assessment_id`.
    case studentCreated = "student"

    /// Maps a raw `data-assessment-type` value. Anything that is not explicitly `student`
    /// is treated as a class-assigned item, which is what the Android port does and what the
    /// markup implies (only student-created items are expected to be tagged).
    static func from(_ raw: String) -> AssessmentKind {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return token == AssessmentKind.studentCreated.rawValue ? .studentCreated : .classAssigned
    }

    /// The POST field name W4 expects for an item of this kind.
    var identifierFieldName: String {
        switch self {
        case .classAssigned: return AssessmentFieldNames.classAssessmentID
        case .studentCreated: return AssessmentFieldNames.studentAssessmentID
        }
    }
}

// MARK: - Status

/// The only two states W4 actually models server-side (README section 5.2: the buttons are
/// "Confirm done" and "Revert to pending"). "Overdue" is *styling*, not a state — it lives on
/// `Assessment.isOverdue` so a filter can use it without pretending it is a third status.
enum AssessmentStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case done

    /// Tokens we are willing to read as "done". Everything else — including anything we have
    /// never seen — stays `.pending`.
    ///
    /// This deliberately inverts the Android port, which does `done = status != "pending"` and
    /// therefore marks an item done on any unrecognised string. Showing a finished item as
    /// pending is a small annoyance; hiding an unfinished one is a missed deadline.
    private static let doneTokens: Set<String> = [
        "done", "complete", "completed", "confirmed", "1", "true", "yes"
    ]

    static func from(_ raw: String) -> AssessmentStatus {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return doneTokens.contains(token) ? .done : .pending
    }
}

/// The two transitions W4 exposes on an assessment. Both post the same identifier field
/// (`AssessmentKind.identifierFieldName`); only the target URL differs.
enum AssessmentTransition: String, Codable, Sendable, CaseIterable {
    /// "Confirm done" -> `AssessmentActionURLs.confirm`.
    case confirmDone
    /// "Revert to pending" -> `AssessmentActionURLs.revert`.
    case revertToPending

    /// The status the item should hold once the server accepts this transition.
    var resultingStatus: AssessmentStatus {
        switch self {
        case .confirmDone: return .done
        case .revertToPending: return .pending
        }
    }

    /// The transition offered to a student looking at an item in `current`.
    static func offered(for current: AssessmentStatus) -> AssessmentTransition {
        switch current {
        case .pending: return .confirmDone
        case .done: return .revertToPending
        }
    }
}

// MARK: - Field names

/// W4 form field names for the assessments calendar.
///
/// These four are the only part of this surface with independent corroboration: README
/// section 5.2 lists them from a live page. Never hardcode them at a call site.
enum AssessmentFieldNames {
    /// Class-assigned item identifier.
    static let classAssessmentID = "assessment_id"
    /// Student-created item identifier.
    static let studentAssessmentID = "student_assessment_id"
    /// Deadline of a student-created item, rendered `dd-MMM-yyyy` (see `W4Dates.format`).
    static let deadlineDate = "student_deadline_date"
    /// Title of a student-created item.
    static let title = "student_assessment_title"
}

// MARK: - Assessment

/// One entry in the W4 assessments calendar.
///
/// Optionality is deliberate and evidence-driven: a student-created item has no subject,
/// class code or teacher, and no field on this page has ever been observed, so anything that
/// can be absent is modelled as absent rather than as an empty string.
struct Assessment: Identifiable, Codable, Hashable, Sendable {
    /// Stable, collision-free identity: `"class:42"` / `"student:99"`. The two id spaces are
    /// independent on W4, so the kind has to be part of the key.
    let id: String
    /// The identifier W4 itself uses, without the kind prefix (`"42"`).
    let rawId: String
    let kind: AssessmentKind
    /// The verbatim `data-assessment-type` value, kept so a capture can be diffed against the
    /// enum without re-scraping.
    let rawKind: String
    /// Anchor text, falling back to unit, then subject, then a generic label.
    let title: String
    /// `nil` for student-created items.
    let subject: String?
    /// Class code such as `"BIO HL"`; `nil` when absent.
    let classCode: String?
    /// `nil` for student-created items.
    let teacher: String?
    /// Unit / topic label; `nil` when absent.
    let unit: String?
    /// Midnight Europe/Oslo on the due day, or `nil` when neither the item's own date nor the
    /// calendar-cell fallback produced one.
    let dueDate: Date?
    /// W4's own countdown. Negative values are kept as-is.
    let daysLeft: Int?
    /// Server truth. `var` so a repository can apply an optimistic overlay and drop it on the
    /// next refresh (plan section 1.3: W4 owns done-state, never a local store).
    var status: AssessmentStatus
    /// The verbatim `data-status` value, rendered when the enum is not enough to explain
    /// what W4 said.
    let rawStatus: String
    /// Styling-derived, not a status. True when `data-css-class` or the anchor's own class
    /// list mentions "overdue".
    let isOverdue: Bool
    /// Whether W4 marked the item editable (`data-editable`). Advisory only.
    let isEditable: Bool
    /// The anchor's `href`, normalised: `nil` for `#`, `javascript:` and blanks.
    let href: String?

    var isDone: Bool { status == .done }

    /// The transition a student can perform from the current status.
    var offeredTransition: AssessmentTransition { AssessmentTransition.offered(for: status) }

    init(
        id: String,
        rawId: String,
        kind: AssessmentKind,
        rawKind: String,
        title: String,
        subject: String? = nil,
        classCode: String? = nil,
        teacher: String? = nil,
        unit: String? = nil,
        dueDate: Date? = nil,
        daysLeft: Int? = nil,
        status: AssessmentStatus,
        rawStatus: String,
        isOverdue: Bool = false,
        isEditable: Bool = false,
        href: String? = nil
    ) {
        self.id = id
        self.rawId = rawId
        self.kind = kind
        self.rawKind = rawKind
        self.title = title
        self.subject = subject
        self.classCode = classCode
        self.teacher = teacher
        self.unit = unit
        self.dueDate = dueDate
        self.daysLeft = daysLeft
        self.status = status
        self.rawStatus = rawStatus
        self.isOverdue = isOverdue
        self.isEditable = isEditable
        self.href = href
    }
}

// MARK: - Draft (student-created items)

/// A student-created assessment being composed or edited.
///
/// The parser does not produce these; a repository does. `deadline` is formatted for the wire
/// with `W4Dates.format` (`dd-MMM-yyyy`) at POST time, not here, so this stays a pure value.
struct AssessmentDraft: Codable, Hashable, Sendable {
    /// `nil` means "create"; non-`nil` means "save an existing student item".
    var studentAssessmentId: String?
    /// Posts as `student_assessment_title`.
    var title: String
    /// Posts as `student_deadline_date`.
    var deadline: Date

    init(studentAssessmentId: String? = nil, title: String, deadline: Date) {
        self.studentAssessmentId = studentAssessmentId
        self.title = title
        self.deadline = deadline
    }

    var isCreate: Bool { studentAssessmentId == nil }
}

// MARK: - Action URLs

/// The five write endpoints, scraped from the page's inline `var ajax_urls = {…}` object.
///
/// Never hardcode these: the URLs carry `&month=&year=&uwc_id=` and W4 regenerates them per
/// page render. An endpoint W4 did not publish is the empty string; use `url(for:)` /
/// `resolved(_:)` so a caller cannot POST to `""`.
struct AssessmentActionURLs: Codable, Hashable, Sendable {
    let confirm: String
    let revert: String
    let save: String
    let create: String
    let delete: String

    init(confirm: String = "", revert: String = "", save: String = "", create: String = "", delete: String = "") {
        self.confirm = confirm
        self.revert = revert
        self.save = save
        self.create = create
        self.delete = delete
    }

    /// `nil` when W4 did not publish this endpoint.
    func url(for transition: AssessmentTransition) -> String? {
        switch transition {
        case .confirmDone: return Self.nonEmpty(confirm)
        case .revertToPending: return Self.nonEmpty(revert)
        }
    }

    var saveURL: String? { Self.nonEmpty(save) }
    var createURL: String? { Self.nonEmpty(create) }
    var deleteURL: String? { Self.nonEmpty(delete) }

    /// True when W4 published nothing at all — the signal to keep every write affordance hidden.
    var isEmpty: Bool {
        Self.nonEmpty(confirm) == nil
            && Self.nonEmpty(revert) == nil
            && Self.nonEmpty(save) == nil
            && Self.nonEmpty(create) == nil
            && Self.nonEmpty(delete) == nil
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Feature gate

/// OQ-3: every `data-assessment-*` name is invented and no *Confirm done* request has ever been
/// observed, so assessment writes stay off until capture C-3 lands
/// (`GET index.php?r=academics/deadlines` in term time plus one Confirm-done round trip).
///
/// The plan calls this `W4Feature.assessmentWrites`; `W4Feature` is not owned by any item in
/// this wave, so the flag is namespaced here instead and can be folded into a shared
/// `W4Feature` later without changing its meaning.
enum AssessmentFeatureFlags {
    /// Flip to `true` only when C-3 has landed and the write payload is verified.
    static let writesEnabled = false
}
