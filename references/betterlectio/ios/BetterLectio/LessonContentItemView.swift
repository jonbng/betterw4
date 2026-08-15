//
//  LessonContentItemView.swift
//  BetterLectio
//

import SwiftUI

struct LessonContentItemView: View {
    let item: LessonContentItem

    var body: some View {
        let linkTitles = Set(item.links.map { $0.title })
        let titleMatchesLink = item.title.map { linkTitles.contains($0) } ?? false

        VStack(alignment: .leading, spacing: 6) {
            // Title
            if let title = item.title, !title.isEmpty {
                if titleMatchesLink, let matchingLink = item.links.first(where: { $0.title == title }) {
                    linkRow(matchingLink, font: .subheadline, fontWeight: .semibold)
                } else {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }

            // Note (blockquote)
            if let note = item.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Rich blocks
            ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }

            // Standalone links (skip any already shown as the title)
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
            let absoluteURL = url.hasPrefix("http") ? url : "https://www.lectio.dk\(url)"
            if let imageURL = URL(string: absoluteURL) {
                AsyncImage(url: imageURL) { phase in
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
            }

        case .divider:
            Divider()
        }
    }

    // MARK: - Attributed string for inline content

    private func attributedString(from inlines: [InlineElement]) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            switch inline {
            case .text(let str):
                result += AttributedString(str)
            case .link(let text, let url, _):
                var part = AttributedString(text)
                let absolute = url.hasPrefix("http") ? url : "https://www.lectio.dk\(url)"
                if let u = URL(string: absolute) {
                    part.link = u
                }
                part.foregroundColor = .blue
                result += part
            case .image:
                break // inline images promoted to blocks by parser; safe to skip
            }
        }
        return result
    }

    // MARK: - Link row

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
        .onTapGesture {
            openLink(link)
        }
    }

    private func openLink(_ link: LessonLink) {
        let urlString = link.url.hasPrefix("http") ? link.url : "https://www.lectio.dk\(link.url)"
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}
