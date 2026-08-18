//
//  DocumentModels.swift
//  BetterW4
//
//  Domain models for the W4 Documents CMS: `documents/index` (School) and
//  `extraacademics/documents` (Extra Academics) — the same renderer behind two
//  entry points, so the same models serve both.
//
//  Wave 4 item 4.8. Sources: docs/W4_PORT_PLAN.md §3 (Wave 4, 4.8),
//  docs/spec/parsers.md §12, docs/spec/features.md §1.10.
//
//  Naming follows plan D-5: these are the models the UI consumes, so they carry
//  no `W4` prefix; only `W4DocumentsParser` does. Where parsers.md and
//  features.md disagree on a field name the union is taken, features.md's
//  spelling winning (`href`), with parsers.md's `route` kept alongside it
//  because the two carry genuinely different information — see `DocumentNode`.
//
//  Evidence, and the lack of it:
//    [V] `ul.folder-list li a.folder`, `folder_id=`, `#breadcrumb .crumbs a`,
//        `#content_inner > h2` — BetterW4Tests/Fixtures/W4/documents.html, a
//        real capture of `?r=documents`.
//    [V] `a.page`, `div.up > a`, `div.new > a`, `.page-title`, `.page-details`,
//        `.page-content` — styled in the server's own
//        references/pages/Documents_files/cmsrenderer.css, so the class names
//        are real even though no page has been captured.
//    [U] The element types and nesting of a rendered leaf page, and what a
//        folder containing pages looks like. Nothing has ever been captured.
//        Every model member below is therefore either optional or defaults to
//        an empty value; the parser never requires a node to exist.
//

import Foundation

/// What a `ul.folder-list` entry points at.
///
/// `folder` is verified in the real capture. `page` is verified as a CSS class
/// (`ul.folder-list li a.page` in `cmsrenderer.css`) and by the `page_id=` deep
/// links the Home `#links` block emits, but no folder containing pages has been
/// captured.
enum DocumentNodeKind: String, Codable, Sendable, CaseIterable {
    case folder
    case page
}

/// One entry in a CMS folder listing.
struct DocumentNode: Identifiable, Codable, Equatable, Hashable, Sendable {
    /// `folder_id` / `page_id` when the link carries one, otherwise the raw
    /// `href`, so a node is always uniquely identifiable inside a listing.
    let id: String

    /// The anchor's text, whitespace-collapsed. Empty when W4 renders an
    /// icon-only link — never `nil`, so a list row always has something to
    /// bind to.
    let title: String

    let kind: DocumentNodeKind

    /// The W4 route in the form `W4Routes.splitRouteAndQuery` accepts, e.g.
    /// `documents/index&folder_id=27`. `nil` when the anchor is not an
    /// `index.php?r=…` link (an external link, or markup we do not recognise),
    /// which is the caller's cue to open `href` externally instead.
    ///
    /// Percent-escapes are decoded here; the route is rebuilt, not re-encoded.
    let route: String?

    /// The `href` exactly as W4 emitted it (HTML entities already decoded by
    /// the HTML parser).
    let href: String

    /// The numeric `folder_id`/`page_id`, when `id` is one.
    var numericID: Int? { Int(id) }

    var isFolder: Bool { kind == .folder }
    var isPage: Bool { kind == .page }
}

/// One `#breadcrumb .crumbs a` entry.
///
/// Deliberately not a `DocumentNode`: the captured crumb is `Home` pointing at
/// `https://w4.uwcrcn.no/`, which has neither a `folder_id` nor a `page_id`, so
/// forcing it into `DocumentNode` would mean inventing an id and a kind.
struct DocumentBreadcrumb: Identifiable, Codable, Equatable, Hashable, Sendable {
    let title: String

    /// Same shape as `DocumentNode.route`; `nil` for links outside the CMS
    /// (the captured `Home` crumb is one of those — it points at the site root,
    /// which carries no `r=`).
    let route: String?

    let href: String

    var id: String { href.isEmpty ? title : href }
}

/// A rendered leaf page — TinyMCE HTML that a renderer displays later.
struct DocumentPage: Codable, Equatable, Hashable, Sendable {
    /// `.page-title`, falling back to the first heading in `#content_inner`.
    let title: String

    /// `.page-details` — the author/date line on the captured CSS's evidence.
    /// `nil` when absent or blank.
    let details: String?

    /// The **raw inner HTML** of `.page-content`, kept verbatim so a renderer
    /// can display it. It is untrusted TinyMCE output: sanitise before display
    /// and never hand it to a `WKWebView` with JavaScript enabled (plan D-24).
    let contentHTML: String
}

/// The result of parsing one Documents CMS page: a folder listing, a leaf page,
/// or — when W4 sends something we do not recognise — nothing at all.
struct DocumentListing: Codable, Equatable, Hashable, Sendable {
    /// `.page-title`, else the first `#content_inner` heading, else the
    /// document `<title>`. Empty rather than `nil` so a navigation title always
    /// has a value.
    let title: String

    /// `#breadcrumb .crumbs a`, outermost first.
    let breadcrumb: [DocumentBreadcrumb]

    /// The `ul.folder-list` entries, in document order. Empty for a leaf page
    /// and for an empty folder — those two cases are told apart by `page`, not
    /// by this being empty (bug B16).
    let items: [DocumentNode]

    /// `div.up > a` — the "up one level" link, as a route.
    let parentRoute: String?

    /// Non-`nil` only when this page really is a rendered leaf page.
    let page: DocumentPage?

    /// `true` when this node is a page rather than a folder. Derived, never
    /// guessed from `items.isEmpty` — that guess is bug B16.
    var isPage: Bool { page != nil }

    /// Convenience for `features.md`'s `bodyHTML`.
    var bodyHTML: String? { page?.contentHTML }

    var folders: [DocumentNode] { items.filter { $0.kind == .folder } }
    var pages: [DocumentNode] { items.filter { $0.kind == .page } }

    /// Nothing to show: neither children nor a body. A legitimately empty
    /// folder looks exactly like this, and so does a page we failed to parse —
    /// the parser logs a warning in the second case.
    var isEmpty: Bool { items.isEmpty && page == nil }

    /// The degraded result. Every failure path in `W4DocumentsParser` returns
    /// this or something built from it; the parser never throws and never
    /// crashes.
    static let empty = DocumentListing(
        title: "",
        breadcrumb: [],
        items: [],
        parentRoute: nil,
        page: nil
    )
}
