//
//  LessonContentItemView.swift
//  BetterW4
//
//  Renders one block of rich lesson/assessment content: a title, an optional note, a few
//  paragraphs and any attachments.
//
//  Relative hrefs and image sources are resolved against W4 through `W4Routes.resolve(_:)`, which
//  also accepts a bare Yii route. Nothing here builds a host by hand.
//

import SwiftUI
import UIKit

struct LessonContentItemView: View {
    let item: LessonContentItem

    var body: some View {
        let linkTitles = Set(item.links.map(\.title))
        let titleMatchesLink = item.title.map { linkTitles.contains($0) } ?? false

        VStack(alignment: .leading, spacing: 6) {
            if let title = item.title, !title.isEmpty {
                if titleMatchesLink, let matchingLink = item.links.first(where: { $0.title == title }) {
                    linkRow(matchingLink, font: .subheadline, fontWeight: .semibold)
                } else {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }

            if let note = item.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }

            ForEach(Array(item.links.enumerated()), id: \.offset) { _, link in
                if !(titleMatchesLink && link.title == item.title) {
                    linkRow(link)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func blockView(_ block: ContentBlock) -> some View {
        switch block {
        case .heading(let level, let inlines):
            Text(attributedString(from: inlines))
                .font(level == 1 ? .headline : (level == 2 ? .subheadline : .footnote))
                .fontWeight(level == 1 ? nil : .semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let inlines):
            Text(attributedString(from: inlines))
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .image(let url, _):
            AsyncImage(url: Self.absoluteURL(url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .failure:
                    EmptyView()
                default:
                    ProgressView()
                        .frame(height: 60)
                }
            }

        case .divider:
            Divider()
        }
    }

    // MARK: - Inline content

    private func attributedString(from inlines: [InlineElement]) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            switch inline {
            case .text(let string):
                result += AttributedString(string)
            case .link(let text, let url, _):
                var part = AttributedString(text)
                part.link = Self.absoluteURL(url)
                part.foregroundColor = .blue
                result += part
            case .image:
                break // inline images are promoted to blocks by the parser
            }
        }
        return result
    }

    // MARK: - Links

    private func linkRow(_ link: LessonLink, font: Font = .caption, fontWeight: Font.Weight? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: link.type == .file ? "doc" : "link")
                .font(font)
                .foregroundColor(.blue)
                .frame(width: 16)

            Text(link.title)
                .font(font)
                .fontWeight(fontWeight)
                .foregroundColor(.blue)
                .lineLimit(2)

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = Self.absoluteURL(link.url) {
                UIApplication.shared.open(url)
            }
        }
    }

    /// Absolute URL for an href W4 emitted. Absolute inputs are kept verbatim; everything else —
    /// `/index.php?r=…`, `index.php?r=…`, or a bare Yii route — is resolved against W4's origin.
    private static func absoluteURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return W4Routes.resolve(trimmed)
    }
}
