//
//  MessageContentRenderer.swift
//  BetterLectio
//

import Foundation
import SwiftSoup
import SwiftUI

enum MessageContentRenderer {
    static func render(_ html: String) -> AttributedString {
        guard !html.isEmpty else { return AttributedString("") }
        do {
            let doc = try SwiftSoup.parseBodyFragment(html)
            guard let body = doc.body() else { return fallback(html) }
            var output = AttributedString()
            renderChildren(of: body, into: &output, style: Style())
            return collapseWhitespace(output)
        } catch {
            return fallback(html)
        }
    }

    private struct Style {
        var bold = false
        var italic = false
        var underline = false
        var link: URL?
    }

    private static func renderChildren(of node: Node, into out: inout AttributedString, style: Style) {
        for child in node.getChildNodes() {
            renderNode(child, into: &out, style: style)
        }
    }

    private static func renderNode(_ node: Node, into out: inout AttributedString, style: Style) {
        if let textNode = node as? TextNode {
            let raw = textNode.text()
            guard !raw.isEmpty else { return }
            let normalized = normalizeInlineWhitespace(raw)
            guard !normalized.isEmpty else { return }
            // HTML collapses whitespace after a line break or at the start of a block
            let trailingChar = out.characters.last
            let atBoundary = trailingChar == nil || trailingChar == "\n"
            let toAppend = atBoundary ? stripLeadingSpace(normalized) : normalized
            guard !toAppend.isEmpty else { return }
            out.append(makeAttributed(toAppend, style: style))
            return
        }

        guard let element = node as? Element else { return }

        let tag = element.tagNameNormal()

        switch tag {
        case "br":
            out.append(AttributedString("\n"))
            return
        case "a":
            var nextStyle = style
            if let href = try? element.attr("href"),
               !href.isEmpty,
               let url = URL(string: href) {
                nextStyle.link = url
            }
            renderChildren(of: element, into: &out, style: nextStyle)
            return
        default:
            break
        }

        var nextStyle = style
        let classes = (try? element.classNames()) ?? []
        if classes.contains("bb_b") { nextStyle.bold = true }
        if classes.contains("bb_i") { nextStyle.italic = true }
        if classes.contains("bb_u") { nextStyle.underline = true }

        renderChildren(of: element, into: &out, style: nextStyle)
    }

    private static func makeAttributed(_ string: String, style: Style) -> AttributedString {
        var attr = AttributedString(string)
        if style.bold && style.italic {
            attr.font = .system(size: 16, weight: .bold).italic()
        } else if style.bold {
            attr.font = .system(size: 16, weight: .bold)
        } else if style.italic {
            attr.font = .system(size: 16).italic()
        }
        if style.underline {
            attr.underlineStyle = .single
        }
        if let url = style.link {
            attr.link = url
            attr.foregroundColor = .blue
            attr.underlineStyle = .single
        }
        return attr
    }

    private static func normalizeInlineWhitespace(_ s: String) -> String {
        var result = ""
        var prevWasSpace = false
        for c in s {
            if c.isWhitespace {
                if !prevWasSpace {
                    result.append(" ")
                    prevWasSpace = true
                }
            } else {
                result.append(c)
                prevWasSpace = false
            }
        }
        return result
    }

    private static func stripLeadingSpace(_ s: String) -> String {
        s.hasPrefix(" ") ? String(s.dropFirst()) : s
    }

    private static func collapseWhitespace(_ input: AttributedString) -> AttributedString {
        let plain = String(input.characters)
        let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AttributedString("") }

        let leading = plain.prefix { $0.isWhitespace || $0.isNewline }.count
        let trailing = plain.reversed().prefix { $0.isWhitespace || $0.isNewline }.count

        var result = input
        if leading > 0 {
            let end = result.characters.index(result.startIndex, offsetBy: leading)
            result.removeSubrange(result.startIndex..<end)
        }
        if trailing > 0 {
            let start = result.characters.index(result.endIndex, offsetBy: -trailing)
            result.removeSubrange(start..<result.endIndex)
        }
        return collapseConsecutiveNewlines(result)
    }

    private static func collapseConsecutiveNewlines(_ input: AttributedString) -> AttributedString {
        var result = input
        while let range = result.range(of: "\n\n\n") {
            result.replaceSubrange(range, with: AttributedString("\n\n"))
        }
        return result
    }

    private static func fallback(_ html: String) -> AttributedString {
        if let doc = try? SwiftSoup.parse(html),
           let text = try? doc.body()?.text() {
            return AttributedString(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return AttributedString(html)
    }
}
