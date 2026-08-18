//
//  HTMLContentRenderer.swift
//  BetterW4
//
//  Generic HTML -> [ContentBlock] renderer, salvaged from the Lectio-era
//  `ScheduleParser.parseLessonContent` / `parseInlines` (port plan Wave 4,
//  item 4.1; parsers.md section 4 "Keep parseLessonContent / parseInlines").
//
//  This is the one piece of the old schedule parser worth keeping: it turns an
//  arbitrary chunk of W4 rich text into the `ContentBlock` / `InlineElement`
//  tree the SwiftUI content views already know how to draw. It is deliberately
//  generic — mail bodies (item 4.3), CMS pages (item 4.8) and lesson detail all
//  render the same way, so they can all call this instead of each growing their
//  own half-renderer.
//
//  The Lectio-specific parts of the original (`#homeworkContentContainer`,
//  `article.lc-display-fragment`, `data-lc-display-linktype`, the Danish
//  "Aktiviteten har ikke noget indhold" empty state, `h1.ls-paper-section-heading`
//  Lektier/Øvrigt indhold sectioning) are NOT ported: none of them exist in W4.
//  The old `ScheduleParser` keeps its own copy until its last caller is ported.
//
//  Nothing here throws and nothing here force-unwraps. Unparseable input
//  produces an empty block list plus a logged warning — evidence discipline:
//  no W4 rich-text body has ever been captured.
//

import Foundation
import OSLog
import SwiftSoup

/// Renders a fragment of W4 HTML into `[ContentBlock]`.
///
/// Pure and synchronous: safe to call from any actor, does no I/O.
nonisolated enum HTMLContentRenderer {

    private static let log = Logger(
        subsystem: "dk.jonathanb.w4",
        category: "HTMLContentRenderer"
    )

    /// How deep the walker will recurse before giving up. Guards against
    /// pathological nesting in scraped markup.
    private static let maxDepth = 24

    // MARK: - Entry points

    /// Parses an HTML fragment (or a whole document) and renders its body.
    ///
    /// - Parameters:
    ///   - html: raw markup. May be a fragment; it is parsed as a body fragment.
    ///   - baseURL: when given, relative `src`/`href` values are resolved
    ///     against it. Pass `nil` to keep them verbatim.
    static func blocks(fromHTML html: String, baseURL: URL? = nil) -> [ContentBlock] {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        do {
            let document = try SwiftSoup.parseBodyFragment(trimmed)
            guard let body = document.body() else {
                log.warning("parsed document has no body element")
                return []
            }
            return blocks(from: body, baseURL: baseURL)
        } catch {
            log.warning("could not parse HTML fragment: \(String(describing: error))")
            return []
        }
    }

    /// Renders the children of `element`.
    static func blocks(from element: Element, baseURL: URL? = nil) -> [ContentBlock] {
        var output: [ContentBlock] = []
        var pending: [InlineElement] = []
        walk(element, baseURL: baseURL, depth: 0, output: &output, pending: &pending)
        flush(&pending, into: &output)
        return output
    }

    /// Flattens the inline content of `element` (text, links, images).
    static func inlines(of element: Element, baseURL: URL? = nil) -> [InlineElement] {
        var result: [InlineElement] = []
        collectInlines(element, baseURL: baseURL, depth: 0, into: &result)
        return trimmedInlines(result)
    }

    /// True when `inlines` carry nothing a reader would see.
    static func isEffectivelyEmpty(_ inlines: [InlineElement]) -> Bool {
        for inline in inlines {
            switch inline {
            case .text(let value):
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            case .link, .image:
                return false
            }
        }
        return true
    }

    /// Best-effort plain text, for previews, search and accessibility labels.
    static func plainText(_ blocks: [ContentBlock]) -> String {
        var lines: [String] = []
        for block in blocks {
            switch block {
            case .heading(_, let inlines), .paragraph(let inlines):
                let text = plainText(inlines)
                if !text.isEmpty { lines.append(text) }
            case .image(_, let alt):
                if !alt.isEmpty { lines.append(alt) }
            case .divider:
                continue
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Best-effort plain text for a single run of inlines.
    static func plainText(_ inlines: [InlineElement]) -> String {
        var text = ""
        for inline in inlines {
            switch inline {
            case .text(let value): text += value
            case .link(let label, let url, _): text += label.isEmpty ? url : label
            case .image(_, let alt): text += alt
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Block walking

    private static func walk(
        _ element: Element,
        baseURL: URL?,
        depth: Int,
        output: inout [ContentBlock],
        pending: inout [InlineElement]
    ) {
        guard depth < maxDepth else {
            log.warning("stopped rendering at depth \(maxDepth)")
            return
        }

        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                appendText(textNode.getWholeText(), to: &pending)
                continue
            }
            guard let child = node as? Element else { continue }
            let tag = child.tagName().lowercased()

            if skippedTags.contains(tag) { continue }

            if let level = headingLevel(of: tag) {
                flush(&pending, into: &output)
                let content = inlines(of: child, baseURL: baseURL)
                if !isEffectivelyEmpty(content) {
                    output.append(.heading(level: level, inlines: content))
                }
                continue
            }

            switch tag {
            case "p", "li", "dt", "dd", "td", "th", "caption", "figcaption", "pre":
                flush(&pending, into: &output)
                let content = inlines(of: child, baseURL: baseURL)
                appendParagraph(content, to: &output)

            case "hr":
                flush(&pending, into: &output)
                output.append(.divider)

            case "br":
                pending.append(.text("\n"))

            case "img":
                if let image = imageInline(child, baseURL: baseURL) {
                    pending.append(image)
                }

            case "a", "span", "strong", "em", "b", "i", "u", "s", "small", "big",
                 "code", "sub", "sup", "font", "label", "abbr", "mark", "time",
                 "cite", "q", "var", "kbd", "samp":
                collectInlines(child, baseURL: baseURL, depth: depth + 1, into: &pending)

            default:
                // Everything else (div, section, article, ul, ol, table, tbody,
                // tr, blockquote, form, header, footer, …) is a container: flush
                // whatever inline text preceded it and recurse.
                flush(&pending, into: &output)
                walk(child, baseURL: baseURL, depth: depth + 1, output: &output, pending: &pending)
                flush(&pending, into: &output)
            }
        }
    }

    private static func headingLevel(of tag: String) -> Int? {
        switch tag {
        case "h1": return 1
        case "h2": return 2
        case "h3": return 3
        case "h4": return 4
        case "h5", "h6": return 5
        default: return nil
        }
    }

    /// Tags whose content is never user-visible prose.
    private static let skippedTags: Set<String> = [
        "script", "style", "noscript", "iframe", "svg", "canvas", "object",
        "embed", "video", "audio", "map", "area", "input", "button", "select",
        "option", "optgroup", "textarea", "head", "meta", "link", "title"
    ]

    private static func flush(_ pending: inout [InlineElement], into output: inout [ContentBlock]) {
        defer { pending.removeAll(keepingCapacity: true) }
        appendParagraph(trimmedInlines(pending), to: &output)
    }

    private static func appendParagraph(_ content: [InlineElement], to output: inout [ContentBlock]) {
        let trimmed = trimmedInlines(content)
        guard !isEffectivelyEmpty(trimmed) else { return }
        // A paragraph that is nothing but an image becomes a block-level image,
        // the way the salvaged Lectio renderer did it.
        if trimmed.count == 1, case .image(let url, let alt) = trimmed[0] {
            output.append(.image(url: url, alt: alt))
        } else {
            output.append(.paragraph(inlines: trimmed))
        }
    }

    // MARK: - Inline walking

    private static func collectInlines(
        _ element: Element,
        baseURL: URL?,
        depth: Int,
        into result: inout [InlineElement]
    ) {
        guard depth < maxDepth else { return }

        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                appendText(textNode.getWholeText(), to: &result)
                continue
            }
            guard let child = node as? Element else { continue }
            let tag = child.tagName().lowercased()
            if skippedTags.contains(tag) { continue }

            switch tag {
            case "br":
                result.append(.text("\n"))

            case "img":
                if let image = imageInline(child, baseURL: baseURL) {
                    result.append(image)
                }

            case "a":
                let href = resolved(attribute("href", of: child), baseURL: baseURL)
                let label = normalizedText(text(of: child))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let href, !href.isEmpty {
                    result.append(.link(
                        text: label.isEmpty ? href : label,
                        url: href,
                        type: linkType(for: href)
                    ))
                } else if !label.isEmpty {
                    appendText(label, to: &result)
                } else {
                    // An anchor wrapping only an image still has to render.
                    collectInlines(child, baseURL: baseURL, depth: depth + 1, into: &result)
                }

            default:
                collectInlines(child, baseURL: baseURL, depth: depth + 1, into: &result)
            }
        }
    }

    private static func imageInline(_ element: Element, baseURL: URL?) -> InlineElement? {
        guard let source = resolved(attribute("src", of: element), baseURL: baseURL),
              !source.isEmpty,
              !isDecorativeImage(source)
        else { return nil }
        return .image(url: source, alt: attribute("alt", of: element) ?? "")
    }

    /// Chrome icons carry no meaning in a rendered body.
    private static func isDecorativeImage(_ source: String) -> Bool {
        let lowered = source.lowercased()
        return lowered.contains("/lectio/img/")   // legacy, cannot appear on W4
            || lowered.contains("/images/icons/")
            || lowered.hasSuffix("/spacer.gif")
            || lowered.hasSuffix("/blank.gif")
    }

    /// Heuristic, and knowingly so: W4 has no `data-lc-display-linktype`
    /// equivalent, so a link is treated as a file when it points at one.
    private static func linkType(for href: String) -> LessonLinkType {
        let lowered = href.lowercased()
        if lowered.contains("download") || lowered.contains("/files/") {
            return .file
        }
        let fileExtensions = [
            ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
            ".zip", ".rtf", ".csv", ".txt", ".odt", ".ods", ".key", ".pages"
        ]
        // Compare against the path only, so a query string cannot fool it.
        let path = lowered.split(separator: "?", maxSplits: 1).first.map(String.init) ?? lowered
        return fileExtensions.contains(where: path.hasSuffix) ? .file : .external
    }

    // MARK: - Text helpers

    private static func appendText(_ raw: String, to result: inout [InlineElement]) {
        let value = normalizedText(raw)
        guard !value.isEmpty else { return }
        // Never let a lone separator space start a run.
        if value == " ", result.isEmpty { return }
        if value == " ", case .text(let previous)? = result.last, previous.hasSuffix(" ") { return }
        result.append(.text(value))
    }

    /// Collapses runs of whitespace to a single space and normalises NBSP,
    /// while preserving one leading/trailing space so that inline runs do not
    /// glue together ("Hello <b>world</b>" must not render as "Helloworld").
    private static func normalizedText(_ raw: String) -> String {
        let unified = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        guard !unified.isEmpty else { return "" }
        let leading = unified.hasPrefix(" ")
        let trailing = unified.hasSuffix(" ")
        let core = unified
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        if core.isEmpty { return unified.isEmpty ? "" : " " }
        return (leading ? " " : "") + core + (trailing ? " " : "")
    }

    private static func trimmedInlines(_ inlines: [InlineElement]) -> [InlineElement] {
        var result = inlines
        while let first = result.first, case .text(let value) = first {
            let trimmed = String(value.drop(while: { $0 == " " || $0 == "\n" }))
            if trimmed.isEmpty { result.removeFirst() } else {
                result[0] = .text(trimmed)
                break
            }
        }
        while let last = result.last, case .text(let value) = last {
            var trimmed = value
            while trimmed.hasSuffix(" ") || trimmed.hasSuffix("\n") { trimmed.removeLast() }
            if trimmed.isEmpty { result.removeLast() } else {
                result[result.count - 1] = .text(trimmed)
                break
            }
        }
        return result
    }

    private static func attribute(_ name: String, of element: Element) -> String? {
        guard let value = try? element.attr(name) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func text(of element: Element) -> String {
        (try? element.text()) ?? ""
    }

    private static func resolved(_ value: String?, baseURL: URL?) -> String? {
        guard let value else { return nil }
        guard let baseURL else { return value }
        if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("data:") {
            return value
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteString ?? value
    }
}
