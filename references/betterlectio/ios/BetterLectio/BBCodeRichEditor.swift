import SwiftUI
import UIKit

struct BBCodeRichEditor: View {
    @Binding var text: String
    var isEnabled = true
    @State private var textView: UITextView?
    @State private var isLinkPromptPresented = false
    @State private var pendingLinkRange = NSRange(location: 0, length: 0)
    @State private var linkURL = "https://"

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                formatButton("bold", trait: .traitBold)
                formatButton("italic", trait: .traitItalic)
                Button { toggleUnderline() } label: { Image(systemName: "underline") }
                Button { prepareLink() } label: { Image(systemName: "link") }
                Spacer()
            }
            .buttonStyle(.bordered)
            .disabled(!isEnabled)

            BBCodeTextView(text: $text, textView: $textView, isEnabled: isEnabled)
                .frame(minHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.22)))
        }
        .alert(String(localized: "message.edit_link_title"), isPresented: $isLinkPromptPresented) {
            TextField(String(localized: "message.edit_link_placeholder"), text: $linkURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "message.edit_link_apply")) { applyLink() }
                .disabled(linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func formatButton(_ icon: String, trait: UIFontDescriptor.SymbolicTraits) -> some View {
        Button { toggleTrait(trait) } label: { Image(systemName: icon) }
    }

    private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let view = textView else { return }
        let range = view.selectedRange
        if range.length == 0 {
            var font = (view.typingAttributes[.font] as? UIFont) ?? .preferredFont(forTextStyle: .body)
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: font.pointSize)
            }
            view.typingAttributes[.font] = font
        } else {
            view.textStorage.enumerateAttribute(.font, in: range) { value, subrange, _ in
                let font = (value as? UIFont) ?? .preferredFont(forTextStyle: .body)
                var traits = font.fontDescriptor.symbolicTraits
                if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
                if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                    view.textStorage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: subrange)
                }
            }
        }
        view.delegate?.textViewDidChange?(view)
    }

    private func toggleUnderline() {
        guard let view = textView else { return }
        let range = view.selectedRange
        if range.length == 0 {
            let active = (view.typingAttributes[.underlineStyle] as? Int ?? 0) != 0
            view.typingAttributes[.underlineStyle] = active ? 0 : NSUnderlineStyle.single.rawValue
        } else {
            let active = (view.textStorage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0) != 0
            view.textStorage.addAttribute(.underlineStyle, value: active ? 0 : NSUnderlineStyle.single.rawValue, range: range)
        }
        view.delegate?.textViewDidChange?(view)
    }

    private func prepareLink() {
        guard let view = textView, view.selectedRange.length > 0 else { return }
        let selected = (view.text as NSString).substring(with: view.selectedRange)
        pendingLinkRange = view.selectedRange
        linkURL = selected.contains(".")
            ? (selected.contains("://") ? selected : "https://\(selected)")
            : "https://"
        isLinkPromptPresented = true
    }

    private func applyLink() {
        guard let view = textView, pendingLinkRange.length > 0,
              NSMaxRange(pendingLinkRange) <= view.textStorage.length else { return }
        view.textStorage.addAttribute(
            .link,
            value: linkURL.trimmingCharacters(in: .whitespacesAndNewlines),
            range: pendingLinkRange
        )
        view.delegate?.textViewDidChange?(view)
    }
}

private struct BBCodeTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var textView: UITextView?
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .secondarySystemGroupedBackground
        view.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        view.adjustsFontForContentSizeCategory = true
        view.isScrollEnabled = true
        view.attributedText = BBCodeCodec.decode(text)
        DispatchQueue.main.async { textView = view }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.isEditable = isEnabled
        if context.coordinator.lastExported != text {
            view.attributedText = BBCodeCodec.decode(text)
            context.coordinator.lastExported = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: BBCodeTextView
        var lastExported: String
        init(_ parent: BBCodeTextView) { self.parent = parent; self.lastExported = parent.text }
        func textViewDidChange(_ textView: UITextView) {
            let value = BBCodeCodec.encode(textView.attributedText)
            lastExported = value
            parent.text = value
        }
    }
}

enum BBCodeCodec {
    static func decode(_ source: String) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        var index = source.startIndex
        var traits: UIFontDescriptor.SymbolicTraits = []
        var underline = false
        var link: String?
        var stack: [(String, UIFontDescriptor.SymbolicTraits, Bool, String?)] = []

        while index < source.endIndex {
            guard source[index] == "[", let close = source[index...].firstIndex(of: "]") else {
                append(String(source[index]), to: output, traits: traits, underline: underline, link: link)
                index = source.index(after: index)
                continue
            }
            let token = String(source[source.index(after: index)..<close])
            let lower = token.lowercased()
            let supported = ["b", "i", "u", "/b", "/i", "/u", "url", "/url"].contains(lower) || lower.hasPrefix("url=")
            guard supported else {
                append(String(source[index...close]), to: output, traits: traits, underline: underline, link: link)
                index = source.index(after: close)
                continue
            }
            if lower.hasPrefix("/") {
                if let saved = stack.popLast() {
                    traits = saved.1
                    underline = saved.2
                    link = saved.3
                }
            } else {
                stack.append((lower, traits, underline, link))
                if lower == "b" { traits.insert(.traitBold) }
                if lower == "i" { traits.insert(.traitItalic) }
                if lower == "u" { underline = true }
                if lower.hasPrefix("url=") { link = String(token.dropFirst(4)) }
                if lower == "url" {
                    let contentStart = source.index(after: close)
                    if let end = source.range(of: "[/url]", options: [.caseInsensitive], range: contentStart..<source.endIndex)?.lowerBound {
                        link = String(source[contentStart..<end])
                    }
                }
            }
            index = source.index(after: close)
        }
        return output
    }

    private static func append(_ string: String, to output: NSMutableAttributedString, traits: UIFontDescriptor.SymbolicTraits, underline: Bool, link: String?) {
        let base = UIFont.preferredFont(forTextStyle: .body)
        let font = base.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: base.pointSize) } ?? base
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.label]
        if underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if let link, !link.isEmpty { attrs[.link] = link }
        output.append(NSAttributedString(string: string, attributes: attrs))
    }

    static func encode(_ attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        var result = ""
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
            var chunk = attributed.attributedSubstring(from: range).string
            let font = attrs[.font] as? UIFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            if traits.contains(.traitBold) { chunk = "[b]\(chunk)[/b]" }
            if traits.contains(.traitItalic) { chunk = "[i]\(chunk)[/i]" }
            if (attrs[.underlineStyle] as? Int ?? 0) != 0 && attrs[.link] == nil { chunk = "[u]\(chunk)[/u]" }
            if let value = attrs[.link] {
                let href: String
                if let url = value as? URL {
                    href = url.absoluteString
                } else if let url = value as? NSURL {
                    href = url.absoluteString ?? ""
                } else {
                    href = value as? String ?? String(describing: value)
                }
                chunk = href == chunk ? "[url]\(chunk)[/url]" : "[url=\(href)]\(chunk)[/url]"
            }
            result += chunk
        }
        return result
    }
}
