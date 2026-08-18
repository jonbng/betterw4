//
//  W4DocumentsParser.swift
//  BetterW4
//
//  Parses the W4 Documents CMS: `documents/index` (optionally with `folder_id=`
//  or `page_id=`) and the Extra Academics CMS at `extraacademics/documents`.
//
//  Wave 4 item 4.8. Sources: docs/W4_PORT_PLAN.md §3 (Wave 4, 4.8),
//  docs/spec/parsers.md §12, docs/spec/features.md §1.10.
//
//  This is one of the few parsers in the port with a real capture behind it
//  (BetterW4Tests/Fixtures/W4/documents.html, the `?r=documents` index) plus the
//  server's own `cmsrenderer.css`, which names every class the renderer can
//  emit. What is *not* captured is a rendered leaf page or a folder that
//  contains pages, so:
//
//    * every selector below is a ladder that ends in "give up quietly";
//    * every failure returns `DocumentListing.empty` (or a partial listing) and
//      logs a warning — nothing here throws, force-unwraps, or subscripts;
//    * bug **B16** (parsers.md §12): the Kotlin port decides "this is a page"
//      from the *absence* of folder/page links and then dumps `#content_inner`.
//      That misreads an empty folder as a page. Here a page is `.page-content`
//      — the real class — and the Kotlin heuristic is a last resort, fenced
//      behind three extra conditions (see `parsePage`).
//
//  Purity: `nonisolated`, synchronous, no I/O, no singletons, no `Date()`.
//  `(String) -> DocumentListing`, per the wave brief and plan D-30.
//

import Foundation
import OSLog
import SwiftSoup

nonisolated enum W4DocumentsParser {

    private static let log = Logger(
        subsystem: "dk.jonathanb.w4",
        category: "W4DocumentsParser"
    )

    // MARK: - Entry point

    /// Parses one Documents CMS page.
    ///
    /// Never throws: unparseable HTML, missing containers and unrecognised
    /// markup all degrade to an empty or partial `DocumentListing` plus a
    /// logged warning.
    static func parse(_ html: String) -> DocumentListing {
        guard let document = try? SwiftSoup.parse(html) else {
            log.warning("Documents page is not parseable HTML; returning an empty listing.")
            return .empty
        }

        // Page bodies are TinyMCE HTML that a renderer displays verbatim, so
        // serialise them back out as they came in rather than re-indented.
        _ = document.outputSettings().prettyPrint(pretty: false)

        // `#content_inner` is the page body on every captured W4 page
        // (parsers.md §0.3). When it is missing we still try the whole body —
        // an AJAX fragment would look like that — but we refuse to run the B16
        // page heuristic, because "the whole body" is not a page body.
        let inner = try? document.select("#content_inner").first()
        if inner == nil {
            log.warning("#content_inner missing from the documents page; falling back to <body>.")
        }
        let root = inner ?? document.body() ?? document

        let breadcrumb = parseBreadcrumb(in: document)
        let items = parseItems(in: root)
        let title = parseTitle(in: root, document: document)
        let parentRoute = parseParentRoute(in: root, document: document)
        let page = parsePage(
            in: root,
            listingTitle: title,
            items: items,
            hasContentInner: inner != nil
        )

        if items.isEmpty && page == nil {
            // Legitimate for an empty folder, so this is a warning and not an
            // error, and the listing is still returned with its title and
            // breadcrumb intact.
            log.warning("Documents page yielded no folder-list entries and no page content.")
        }

        return DocumentListing(
            title: title,
            breadcrumb: breadcrumb,
            items: items,
            parentRoute: parentRoute,
            page: page
        )
    }

    // MARK: - Title

    /// `.page-title` (a leaf page) → the first heading in the page body → the
    /// document `<title>`. The captured index renders `<h2>Documents</h2>`.
    private static func parseTitle(in root: Element, document: Document) -> String {
        if let heading = firstNonEmptyText(in: root, selectors: headingSelectors) {
            return heading
        }
        if let documentTitle = try? document.title() {
            let normalized = collapseWhitespace(documentTitle)
            if !normalized.isEmpty { return normalized }
        }
        log.warning("Documents page has no heading and no <title>.")
        return ""
    }

    private static let headingSelectors = [".page-title", "h1", "h2", "h3"]

    // MARK: - Folder listing

    /// `ul.folder-list li a.folder | a.page` **[V]**. The second rung catches a
    /// renderer that drops the `ul` wrapper; both rungs are class-driven, never
    /// positional.
    private static func parseItems(in root: Element) -> [DocumentNode] {
        var anchors = select(root, ".folder-list a[href]")
        if anchors.isEmpty {
            anchors = select(root, "a.folder[href], a.page[href]")
        }
        guard !anchors.isEmpty else { return [] }

        var nodes: [DocumentNode] = []
        var indexByHref: [String: Int] = [:]

        for anchor in anchors {
            guard let node = documentNode(from: anchor) else { continue }
            // A renderer that splits the icon and the label into two anchors
            // with the same href must not produce two rows; keep whichever of
            // the two actually has a title.
            if let existing = indexByHref[node.href] {
                if nodes[existing].title.isEmpty && !node.title.isEmpty {
                    nodes[existing] = node
                }
                continue
            }
            indexByHref[node.href] = nodes.count
            nodes.append(node)
        }
        return nodes
    }

    private static func documentNode(from anchor: Element) -> DocumentNode? {
        let href = attribute("href", of: anchor)
        guard !href.isEmpty else { return nil }

        let query = queryPairs(in: href)
        let kind = nodeKind(of: anchor, query: query)
        let identifier = identifier(for: kind, query: query) ?? href

        return DocumentNode(
            id: identifier,
            title: anchorTitle(anchor),
            kind: kind,
            route: route(fromHref: href),
            href: href
        )
    }

    /// The CSS class is the truth (`cmsrenderer.css` paints `a.folder` and
    /// `a.page` with different icons). The `folder_id=`/`page_id=` parameters
    /// are the fallback, and a documents link with neither is the CMS root,
    /// which is a folder.
    private static func nodeKind(
        of anchor: Element,
        query: [(name: String, value: String)]
    ) -> DocumentNodeKind {
        if anchor.hasClass("folder") { return .folder }
        if anchor.hasClass("page") { return .page }
        if value(of: "page_id", in: query) != nil { return .page }
        if value(of: "folder_id", in: query) != nil { return .folder }
        log.debug("Folder-list anchor has neither a folder/page class nor an id; assuming a folder.")
        return .folder
    }

    private static func identifier(
        for kind: DocumentNodeKind,
        query: [(name: String, value: String)]
    ) -> String? {
        let preferred = kind == .page ? "page_id" : "folder_id"
        let other = kind == .page ? "folder_id" : "page_id"
        if let identifier = value(of: preferred, in: query), !identifier.isEmpty { return identifier }
        if let identifier = value(of: other, in: query), !identifier.isEmpty { return identifier }
        return nil
    }

    /// Anchor text → `title=` → the icon's `alt=`. Icon-only links are real in
    /// this renderer (the icon is a CSS background, but a future template could
    /// use an `<img>`), so an empty title is tolerated rather than dropped.
    private static func anchorTitle(_ anchor: Element) -> String {
        let text = normalizedText(anchor)
        if !text.isEmpty { return text }

        let titleAttribute = collapseWhitespace(attribute("title", of: anchor))
        if !titleAttribute.isEmpty { return titleAttribute }

        if let image = try? anchor.select("img[alt]").first() {
            let alt = collapseWhitespace(attribute("alt", of: image))
            if !alt.isEmpty { return alt }
        }
        return ""
    }

    // MARK: - Up one level

    /// `div.up > a` **[V]** (`cmsrenderer.css`). Searched inside the page body
    /// first; the whole document is the fallback because `div.up` belongs to
    /// the CMS renderer and appears nowhere else in the captured chrome.
    private static func parseParentRoute(in root: Element, document: Document) -> String? {
        let scopes: [Element] = [root, document]
        for scope in scopes {
            for selector in ["div.up > a[href]", "div.up a[href]", ".up > a[href]"] {
                guard let anchor = try? scope.select(selector).first() else { continue }
                let href = attribute("href", of: anchor)
                if let route = route(fromHref: href) { return route }
                if !href.isEmpty {
                    log.debug("Up-one-level link is not a W4 route; ignoring it.")
                }
            }
        }
        return nil
    }

    // MARK: - Breadcrumb

    /// `#breadcrumb .crumbs a` **[V]**. Scoped to `.crumbs` on purpose:
    /// `#breadcrumb` also holds the help widget (`a.help`, plus the anchors
    /// inside `#help_display`), which are chrome, not navigation.
    private static func parseBreadcrumb(in document: Document) -> [DocumentBreadcrumb] {
        var anchors = select(document, "#breadcrumb .crumbs a[href]")
        if anchors.isEmpty {
            anchors = select(document, ".crumbs a[href]")
        }

        var crumbs: [DocumentBreadcrumb] = []
        for anchor in anchors {
            if anchor.hasClass("help") { continue }
            let href = attribute("href", of: anchor)
            let title = anchorTitle(anchor)
            if href.isEmpty && title.isEmpty { continue }
            crumbs.append(
                DocumentBreadcrumb(title: title, route: route(fromHref: href), href: href)
            )
        }
        return crumbs
    }

    // MARK: - Leaf page (bug B16)

    /// A page is `.page-content` **[V]** — that is what `cmsrenderer.css`
    /// styles. Only when that class is absent do we fall back to the Kotlin
    /// port's heuristic, and then only when all of the following hold, so that
    /// an *empty folder* can never be mistaken for a page:
    ///
    ///   1. the page really had a `#content_inner` (not a `<body>` fallback);
    ///   2. there is no `.folder-list` container at all — an empty one means an
    ///      empty folder;
    ///   3. no folder/page links were found;
    ///   4. what is left after removing the heading and the CMS navigation
    ///      chrome still has visible text.
    private static func parsePage(
        in root: Element,
        listingTitle: String,
        items: [DocumentNode],
        hasContentInner: Bool
    ) -> DocumentPage? {
        if let content = try? root.select(".page-content").first() {
            let title = firstNonEmptyText(in: root, selectors: headingSelectors) ?? listingTitle
            let details = firstNonEmptyText(in: root, selectors: [".page-details"])
            let contentHTML = (try? content.html()) ?? ""
            if contentHTML.isEmpty {
                log.warning(".page-content is present but empty; the page will render blank.")
            }
            return DocumentPage(title: title, details: details, contentHTML: contentHTML)
        }

        guard hasContentInner else { return nil }
        guard items.isEmpty else { return nil }
        guard (try? root.select(".folder-list").first()) == nil else {
            // An empty `ul.folder-list` is an empty folder, not a page (B16).
            return nil
        }

        let leftover = leftoverContent(of: root)
        guard !leftover.text.isEmpty else { return nil }

        log.warning(
            """
            Documents page has no .page-content; falling back to the \
            #content_inner heuristic (bug B16) — the body may include chrome.
            """
        )
        return DocumentPage(title: listingTitle, details: nil, contentHTML: leftover.html)
    }

    /// `#content_inner` minus the first heading and minus the CMS navigation
    /// chrome, as raw HTML plus its visible text (used only to decide whether
    /// there is anything worth showing).
    private static func leftoverContent(of root: Element) -> (html: String, text: String) {
        var html = ""
        var text = ""
        var droppedHeading = false

        for node in root.getChildNodes() {
            if let element = node as? Element {
                let tag = element.tagName().lowercased()
                if !droppedHeading, ["h1", "h2", "h3"].contains(tag) {
                    droppedHeading = true
                    continue
                }
                if ["script", "style", "noscript"].contains(tag) { continue }
                if element.hasClass("up") || element.hasClass("new") { continue }
                if attribute("id", of: element) == "breadcrumb" { continue }
                html += (try? element.outerHtml()) ?? ""
                text += " " + normalizedText(element)
            } else if let textNode = node as? TextNode {
                let value = collapseWhitespace(textNode.getWholeText())
                if value.isEmpty { continue }
                html += (try? textNode.outerHtml()) ?? value
                text += " " + value
            }
        }

        return (
            html.trimmingCharacters(in: .whitespacesAndNewlines),
            collapseWhitespace(text)
        )
    }

    // MARK: - Routes

    /// `https://w4.uwcrcn.no/index.php?r=documents/index&folder_id=27`
    /// → `documents/index&folder_id=27`, i.e. exactly the shape
    /// `W4Routes.splitRouteAndQuery` takes apart again.
    ///
    /// Percent-escapes are decoded and the route is rebuilt rather than
    /// re-encoded, matching `W4Routes.route(ofURLString:)`. A value containing a
    /// literal `%`, `&` or `=` would not survive the round trip — no W4
    /// documents link has ever carried one, and the raw `href` is kept on the
    /// model for exactly that kind of surprise.
    static func route(fromHref href: String) -> String? {
        let pairs = queryPairs(in: href)
        guard let raw = pairs.first(where: { $0.name.lowercased() == "r" })?.value else {
            return nil
        }

        var route = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while route.hasSuffix("/") { route.removeLast() }
        guard !route.isEmpty else { return nil }

        let siblings = pairs.filter { $0.name.lowercased() != "r" }
        guard !siblings.isEmpty else { return route }
        return route + "&" + siblings.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
    }

    /// Hand-rolled rather than `URLComponents`, because W4 hrefs are sometimes
    /// relative, sometimes absolute, and the `r` value contains literal `/`
    /// characters that `URLComponents` is entitled to be strict about.
    /// Entity decoding (`&amp;` → `&`) has already happened in SwiftSoup.
    private static func queryPairs(in href: String) -> [(name: String, value: String)] {
        guard let questionMark = href.firstIndex(of: "?") else { return [] }

        var query = String(href[href.index(after: questionMark)...])
        if let fragment = query.firstIndex(of: "#") {
            query = String(query[query.startIndex..<fragment])
        }

        var pairs: [(name: String, value: String)] = []
        for part in query.split(separator: "&", omittingEmptySubsequences: true) {
            let piece = String(part)
            let name: String
            let value: String
            if let equals = piece.firstIndex(of: "=") {
                name = percentDecoded(String(piece[piece.startIndex..<equals]))
                value = percentDecoded(String(piece[piece.index(after: equals)...]))
            } else {
                name = percentDecoded(piece)
                value = ""
            }
            if name.isEmpty { continue }
            pairs.append((name, value))
        }
        return pairs
    }

    private static func value(
        of name: String,
        in pairs: [(name: String, value: String)]
    ) -> String? {
        pairs.first(where: { $0.name.lowercased() == name.lowercased() })?.value
    }

    private static func percentDecoded(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }

    // MARK: - SwiftSoup helpers

    /// `select` that returns `[]` instead of throwing (parsers.md §0.5.3).
    private static func select(_ scope: Element, _ query: String) -> [Element] {
        ((try? scope.select(query)) ?? Elements()).array()
    }

    private static func attribute(_ name: String, of element: Element) -> String {
        ((try? element.attr(name)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedText(_ element: Element) -> String {
        collapseWhitespace((try? element.text()) ?? "")
    }

    private static func firstNonEmptyText(in scope: Element, selectors: [String]) -> String? {
        for selector in selectors {
            for element in select(scope, selector) {
                let text = normalizedText(element)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    /// Collapses every run of Unicode whitespace — including the `&nbsp;` W4
    /// sprinkles through its chrome — to a single space, and trims.
    private static func collapseWhitespace(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
