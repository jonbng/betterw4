//
//  HomeModels.swift
//  BetterW4
//
//  Domain models for the W4 Home page (`index.php?r=site/index`).
//
//  Evidence: every field here is backed by the one real Home capture
//  (`references/pages/UWCRCN W4.html`, sanitized to
//  `BetterW4Tests/Fixtures/W4/home.html`) — see docs/spec/parsers.md §13 and
//  docs/spec/reviewer-notes.md §7. Nothing is modelled that the capture does
//  not show; in particular birthday entries carry **no name**, only a photo and
//  a UWC id, so there is deliberately no `name` field to fill.
//
//  Scope note (plan Wave 4, item 4.6): the Home page also carries the week
//  timetable (`#timetable`), the two attendance meters (`#absences`) and the
//  campus-status control (`.status-dropdown`). Those belong to items 4.1, 4.4
//  and 4.5 respectively and are deliberately **not** modelled here, so this file
//  stays self-contained and free of cross-item type dependencies. A Wave 5
//  `HomeRepository` composes `HomePage` with those three.
//
//  Naming follows plan D-5: the `W4` prefix is for wire/protocol types and
//  parsers only, so the parser is `W4HomeParser` and the models it returns are
//  unprefixed.
//

import Foundation

// MARK: - Home page

/// The parts of `r=site/index` that are not the timetable, the meters or the
/// campus chip: greeting + identity, birthdays, announcements, the links block
/// and the server version.
///
/// Every field is optional or empty-able: `W4HomeParser` never throws and never
/// invents, so a Home page that changed shape degrades to `.empty` rather than
/// failing.
struct HomePage: Codable, Hashable, Sendable {

    /// The whole first line of `#hello`, verbatim — `"Hello Alex Andersen"` **[V]**.
    var greetingText: String?

    /// The display name pulled out of `greetingText` — `"Alex Andersen"` **[V]**.
    var greetingName: String?

    /// The signed-in student's own UWC id (`nc26abcd`) **[V]**.
    ///
    /// This is the authoritative source: `#hello` carries *this* student's
    /// public-profile link, whereas a document-wide `nc\d{2}[a-z]+` sweep on
    /// Home hits a birthday classmate first (bug B17 in docs/spec/parsers.md).
    var uwcId: String?

    /// The W4 route of that public profile in the project's route-with-siblings
    /// spelling — `"people/students/student&uwc_id=nc26abcd"`, which is exactly
    /// what `W4Routes.url(_:)` accepts back.
    var publicProfileRoute: String?

    /// The same link as an absolute URL.
    var publicProfileURL: URL?

    /// `#birthdays-today` **[V]**. Empty when the block holds no `<ul>`.
    var birthdaysToday: [HomeBirthday]

    /// `#birthdays-tomorrow` **[V]**.
    var birthdaysTomorrow: [HomeBirthday]

    /// `#birthdays div.calendar > a` → `r=people/birthdays` **[V]**.
    var birthdaysCalendarURL: URL?

    /// Parsed announcement items. The one capture we have is the *empty* state,
    /// so a non-empty result rests on the item markup being what
    /// `homepage.css` implies (`ul li dl dt/dd`) — inferred, not captured.
    var announcements: [HomeAnnouncement]

    /// The captured empty state, verbatim: `"No announcements..."` **[V]**.
    /// Non-nil means "W4 said there is nothing", which is different from
    /// "we could not find the block at all".
    var announcementsEmptyText: String?

    /// `#announcements div.rss > a` → `r=site/rss` **[V]**. The public RSS feed
    /// is the honest way to read announcements until a populated capture exists.
    var announcementsRSSURL: URL?

    /// `#links` **[V]**, parsed dynamically. This block is configuration, not
    /// code (README §6) — the ten captured entries are never hardcoded.
    var links: [HomeLink]

    /// `#version` → `"25.9.1"` **[V]**.
    var serverVersion: String?

    /// `#version > a` → `r=site/relnotes` **[V]**.
    var releaseNotesURL: URL?

    init(
        greetingText: String? = nil,
        greetingName: String? = nil,
        uwcId: String? = nil,
        publicProfileRoute: String? = nil,
        publicProfileURL: URL? = nil,
        birthdaysToday: [HomeBirthday] = [],
        birthdaysTomorrow: [HomeBirthday] = [],
        birthdaysCalendarURL: URL? = nil,
        announcements: [HomeAnnouncement] = [],
        announcementsEmptyText: String? = nil,
        announcementsRSSURL: URL? = nil,
        links: [HomeLink] = [],
        serverVersion: String? = nil,
        releaseNotesURL: URL? = nil
    ) {
        self.greetingText = greetingText
        self.greetingName = greetingName
        self.uwcId = uwcId
        self.publicProfileRoute = publicProfileRoute
        self.publicProfileURL = publicProfileURL
        self.birthdaysToday = birthdaysToday
        self.birthdaysTomorrow = birthdaysTomorrow
        self.birthdaysCalendarURL = birthdaysCalendarURL
        self.announcements = announcements
        self.announcementsEmptyText = announcementsEmptyText
        self.announcementsRSSURL = announcementsRSSURL
        self.links = links
        self.serverVersion = serverVersion
        self.releaseNotesURL = releaseNotesURL
    }

    /// What every failed or unrecognised parse returns.
    static let empty = HomePage()

    /// True when the parse found nothing at all worth showing.
    var isEmpty: Bool {
        greetingName == nil
            && uwcId == nil
            && birthdaysToday.isEmpty
            && birthdaysTomorrow.isEmpty
            && announcements.isEmpty
            && announcementsEmptyText == nil
            && links.isEmpty
            && serverVersion == nil
    }

    /// Today's and tomorrow's birthdays in one list, today first.
    var allBirthdays: [HomeBirthday] { birthdaysToday + birthdaysTomorrow }

    /// True when W4 itself said there are no announcements, as opposed to the
    /// block being missing or unreadable.
    var announcementsAreConfirmedEmpty: Bool {
        announcements.isEmpty && announcementsEmptyText != nil
    }
}

// MARK: - Birthdays

/// One birthday entry from `#birthdays-today` / `#birthdays-tomorrow`.
///
/// **There is no name.** The captured markup is
/// `li > a[href*=uwc_id] > img.photo[alt="Photo of nc16efgh"]` and nothing else
/// **[V]** — W4 renders a bare thumbnail wall. Resolve names lazily through the
/// directory cache; do not add a `name` field that the page cannot fill.
struct HomeBirthday: Identifiable, Codable, Hashable, Sendable {

    /// `nc25mnop` **[V]**.
    let uwcId: String

    /// `"people/students/student&uwc_id=nc25mnop"` or the staff equivalent.
    let profileRoute: String?

    /// The profile link as an absolute URL.
    let profileURL: URL?

    /// True when the link points at `people/staff/staff` rather than
    /// `people/students/student`. Both appear in the capture **[V]** — staff
    /// birthdays show up in the same list.
    let isStaff: Bool

    /// The `img.photo` `src` **exactly as the page rendered it**.
    ///
    /// On the saved captures this is a saved-page relative path
    /// (`./UWCRCN W4_files/nc16efgh_thumb.jpg`), which is an artefact of
    /// "Save page as", not of W4. It is kept verbatim rather than resolved into
    /// a fake absolute URL.
    let photoSource: String?

    /// The photo as an absolute URL — non-nil only when `photoSource` was
    /// already absolute or root-relative. W4's own default avatar
    /// (`/images/user.png`) is treated as "no photo", matching the rest of the
    /// port.
    let photoURL: URL?

    var id: String { uwcId }

    init(
        uwcId: String,
        profileRoute: String? = nil,
        profileURL: URL? = nil,
        isStaff: Bool = false,
        photoSource: String? = nil,
        photoURL: URL? = nil
    ) {
        self.uwcId = uwcId
        self.profileRoute = profileRoute
        self.profileURL = profileURL
        self.isStaff = isStaff
        self.photoSource = photoSource
        self.photoURL = photoURL
    }
}

// MARK: - Announcements

/// One College Announcement.
///
/// The captured Home page has **none** (`<p>No announcements...</p>`), so the
/// item shape below is inferred from the rules `homepage.css` ships
/// (`#announcements-content ul li dl dt`, `… dl dd`, `… dl dt span`) rather
/// than from markup anyone has seen. Prefer `site/rss` for real content.
struct HomeAnnouncement: Identifiable, Codable, Hashable, Sendable {

    /// Content-derived and stable across fetches — never a row index
    /// (bug B19 in docs/spec/parsers.md).
    let id: String

    let title: String

    /// Rendered verbatim; W4 date strings are not parsed here, so this stays a
    /// `String` and no timezone assumption is baked in.
    let date: String?

    /// Inner HTML of the announcement body, for `HTMLContentRenderer`.
    let bodyHTML: String?

    init(id: String, title: String, date: String? = nil, bodyHTML: String? = nil) {
        self.id = id
        self.title = title
        self.date = date
        self.bodyHTML = bodyHTML
    }
}

// MARK: - Links

/// One entry of the Home `#links` block **[V]**.
///
/// The captured block mixes W4 routes (Trip Form, three CMS pages) with
/// third-party destinations (Google Sites, Google Drive, Google Forms,
/// ManageBac). ManageBac is a third SIS: link only, never scraped (README §7).
struct HomeLink: Identifiable, Codable, Hashable, Sendable {

    /// The anchor text, verbatim — including non-ASCII
    /// (`Høegh Kitchen Booking Form`, the page is UTF-8) **[V]**.
    let title: String

    /// The absolute destination.
    let url: URL

    /// For W4 destinations only: the route in the project's
    /// route-with-siblings spelling (`documents/index&page_id=870`), ready to
    /// hand to `W4Routes.url(_:)`. `nil` for external links.
    let route: String?

    var id: String { url.absoluteString }

    /// True when this link stays inside W4 and can be deep-linked in-app;
    /// false for Google Sites / Drive / Forms and ManageBac, which open
    /// externally.
    var isInternalRoute: Bool { W4Routes.isW4Host(url.host) }

    init(title: String, url: URL, route: String? = nil) {
        self.title = title
        self.url = url
        self.route = route
    }
}
