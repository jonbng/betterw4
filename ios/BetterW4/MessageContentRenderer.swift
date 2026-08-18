//
//  MessageContentRenderer.swift
//  BetterW4
//
//  Turns a W4 mail body into something SwiftUI can draw.
//
//  W4's compose field is TinyMCE, so `MailMessageDetail.bodyHTML` is **HTML** — not markdown and
//  not BBCode. (BBCode was Lectio's; `BBCodeRichEditor` and its `bb_b` / `bb_i` / `bb_u` classes
//  died with plan §1.4.) There is exactly one HTML → blocks renderer in this app,
//  `HTMLContentRenderer`, and this file does not become a second one: it delegates the parse and
//  owns only the last mile, `[InlineElement] → AttributedString`.
//
//  Two rules that the last mile has to get right:
//
//    * **Relative hrefs are resolved against `https://w4.uwcrcn.no`.** W4 emits
//      `/index.php?r=…`, and a `Text` link that keeps that verbatim opens nothing.
//    * **`mailto:` and `tel:` are left alone.** They are already absolute and must never be run
//      through the W4 resolver, which would turn `mailto:x@uwcrcn.no` into a broken page URL.
//
//  Nothing here throws, does I/O or force-unwraps: an unreadable body renders as no blocks, and
//  the screen says so.
//

import Foundation
import SwiftUI

enum MessageContentRenderer {

    // MARK: - Blocks

    /// Parses a mail body into drawable blocks, with every relative link and image resolved
    /// against W4.
    static func blocks(fromHTML html: String) -> [ContentBlock] {
        HTMLContentRenderer.blocks(fromHTML: html, baseURL: W4Routes.originURL)
    }

    /// Best-effort plain text, for previews and accessibility.
    static func plainText(fromHTML html: String) -> String {
        HTMLContentRenderer.plainText(blocks(fromHTML: html))
    }

    // MARK: - Inline runs

    /// One run of inline content as an `AttributedString`, with links live and tappable.
    ///
    /// Images are skipped here on purpose: `HTMLContentRenderer` promotes a standalone image to a
    /// block, and an inline image inside a paragraph has no `AttributedString` representation —
    /// `MailMessageView` draws blocks, so nothing is lost.
    static func attributedString(from inlines: [InlineElement]) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            switch inline {
            case .text(let value):
                result += AttributedString(value)

            case .link(let text, let url, _):
                let label = text.isEmpty ? url : text
                var run = AttributedString(label)
                if let resolved = absoluteURL(url) {
                    run.link = resolved
                    run.foregroundColor = .accentColor
                    run.underlineStyle = .single
                }
                result += run

            case .image:
                continue
            }
        }
        return result
    }

    // MARK: - Links

    /// Resolves an href out of a W4 page into something openable.
    ///
    /// Returns `nil` rather than a guess when the string is not a usable address — a dead link is
    /// better rendered as plain text than as a tap that does nothing.
    static func absoluteURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("mailto:") || lowered.hasPrefix("tel:") || lowered.hasPrefix("sms:") {
            return URL(string: trimmed)
        }
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        // Anything else is a W4-relative path (`/index.php?r=…`, `index.php?r=…`, a bare route).
        return W4Routes.resolve(trimmed)
    }
}
