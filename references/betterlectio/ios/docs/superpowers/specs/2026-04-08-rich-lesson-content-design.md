# Rich Lesson Content Parsing & Rendering

**Date:** 2026-04-08

## Context

Lectio lesson detail pages contain rich HTML articles with headings at multiple levels, inline file/external links embedded within those headings, images (both hosted on Lectio's CDN and external), and plain-text body content. The current parser flattens everything into `body: String?` + a separate `links: [LessonLink]` array, losing the structure entirely. `h3` elements and images are silently dropped. The result is that complex homework descriptions lose their links, images, and visual hierarchy.

The goal is a fully faithful parse + native SwiftUI rendering that handles inline links, multi-level headings, inline and block images, dividers, and paragraphs.

---

## Data Model (`BetterLectio/ScheduleModels.swift`)

### New types

```swift
enum ContentBlock: Codable, Equatable {
    case heading(level: Int, inlines: [InlineElement])
    case paragraph(inlines: [InlineElement])
    case image(url: String, alt: String)
    case divider
}

enum InlineElement: Codable, Equatable {
    case text(String)
    case link(text: String, url: String, type: LessonLinkType)
    case image(url: String, alt: String)
}
```

### Updated `LessonContentItem`

Replace `body: String?` with `blocks: [ContentBlock]`. Keep all other fields.

```swift
struct LessonContentItem: Codable, Equatable, Identifiable {
    let id: String
    let title: String?
    let note: String?
    let blocks: [ContentBlock]   // replaces body: String?
    let links: [LessonLink]      // kept for title-as-link dedup
    let isHomework: Bool
}
```

Add a custom `init(from decoder:)` so old cached JSON (which has `body` but no `blocks`) decodes safely with `blocks = []`.

---

## Parser (`BetterLectio/ScheduleParser.swift`)

### New helper: `parseInlines(_ element: Element) throws -> [InlineElement]`

Walks the child nodes of any element:

| Node | Result |
|---|---|
| `TextNode` (non-empty after stripping NBSP) | `.text(string)` |
| `<a data-lc-display-linktype>` | `.link(text:, url:, type: .file or .external)` |
| `<img>` where `src` does NOT contain `/lectio/img/` | `.image(url:, alt:)` |
| `<span>`, `<strong>`, `<em>`, `<b>`, `<i>` | recurse into children |
| `<br>` | `.text("\n")` |
| anything else | recurse or skip |

### Updated `parseContentArticle`

Replace the `bodyParts` loop with a walk over the article's direct children:

| Element | Action |
|---|---|
| First `h1/h2[style*=doc-]` or `h2[id*=titleHeader]` | skip (already extracted as `title`) |
| `blockquote[data-lc-role=note]` | skip (already extracted as `note`) |
| `h1` | `.heading(level: 1, inlines: parseInlines(el))` |
| `h2` | `.heading(level: 2, inlines: parseInlines(el))` |
| `h3` | `.heading(level: 3, inlines: parseInlines(el))` |
| `<p>` whose only inline is a single `.image` | promote to `.image(url:, alt:)` block |
| `<p>` | `.paragraph(inlines: parseInlines(el))` |
| bare `<img>` (not a UI icon) | `.image(url:, alt:)` block |
| `<hr>` | `.divider` |
| effectively empty | skip |

`links` extraction is unchanged — still used by the view for title-as-link dedup.

---

## Views

### Shared component: `LessonContentItemView`

Extract the duplicated `contentItemView`, `linkRow`, and `openLink` from both `HomeworkView.swift` and `ScheduleView.swift` into a single `struct LessonContentItemView: View`. Both call sites replace their local method call with `LessonContentItemView(item: item)`.

Best placed in a new file: `BetterLectio/LessonContentItemView.swift`.

### Block rendering

Inside `LessonContentItemView`, replace `Text(body)` with `ForEach(Array(item.blocks.enumerated()), id: \.offset)`:

| Block | View |
|---|---|
| `.heading(1, inlines)` | `Text(attributedString(inlines)).font(.headline)` |
| `.heading(2, inlines)` | `Text(attributedString(inlines)).font(.subheadline).bold()` |
| `.heading(3, inlines)` | `Text(attributedString(inlines)).font(.footnote).bold()` |
| `.paragraph(inlines)` | `Text(attributedString(inlines)).font(.subheadline)` |
| `.image(url, alt)` | `AsyncImage` scaled to fit, max height 300, relative URLs prefixed with `https://www.lectio.dk` |
| `.divider` | `Divider()` |

### `attributedString(from inlines: [InlineElement]) -> AttributedString`

Private helper that builds a SwiftUI `AttributedString`:
- `.text(str)` → plain segment
- `.link(text, url, _)` → segment with `.link = URL(absoluteURL(url))` and `.foregroundColor = .blue` (SwiftUI `Text` renders these as tappable links natively)
- `.image` in inline position → skipped (the parser promotes standalone images to block-level; stray inline images in mixed content are rare and safely dropped)

The existing title-as-link dedup (checks `item.links` to decide whether to render the title as a tappable row) stays unchanged.

---

## Critical Files

- `BetterLectio/ScheduleModels.swift` — add `ContentBlock`, `InlineElement`; update `LessonContentItem`
- `BetterLectio/ScheduleParser.swift` — add `parseInlines`; update `parseContentArticle`
- `BetterLectio/LessonContentItemView.swift` — new shared view component
- `BetterLectio/HomeworkView.swift` — remove duplicated `contentItemView`/`linkRow`/`openLink`; use `LessonContentItemView`
- `BetterLectio/ScheduleView.swift` — same removals; use `LessonContentItemView`

---

## Verification

1. Run the app and open a lesson with file links embedded in headings — links should be tappable inline.
2. Open a lesson with external links (YouTube, quiz sites) — tapping should open Safari.
3. Open a lesson with images — images should render inline with `AsyncImage`.
4. Open a lesson with `h3` headings — they should appear in a smaller bold font than `h1`.
5. Open a lesson with `<hr>` separators — `Divider()` should appear.
6. Open a lesson with old cached data (no `blocks` in JSON) — should decode cleanly showing no body (blocks = []) until refreshed.
7. Build succeeds with no warnings.
