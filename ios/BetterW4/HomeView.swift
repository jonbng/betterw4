//
//  HomeView.swift
//  BetterW4
//
//  `r=site/index` as a screen: the greeting, today's rotation day, both attendance meters,
//  birthdays, College Announcements and the ten configured Links (features.md §1.16, ui.md §4.24).
//
//  Everything on this screen comes from ONE response, composed by `HomeRepository`. The screen
//  makes no request of its own and knows nothing about parsers.
//
//  This file also carries the small set of components the six W4-only surfaces share — the
//  freshness caption, the empty rows, the authenticated in-app page sheet and the rich-text
//  renderer. They live here because Home is the anchor screen of the group; every one of them is
//  used by at least three of the screens in this vertical.
//

import SwiftUI
import UIKit

// MARK: - Shared surface components

/// "Updated 4 minutes ago" / "Demo data. Not connected to W4." — the honest provenance line.
///
/// A cached value never claims to be live: `W4Freshness` carries the moment W4 actually answered,
/// and a value past its TTL is coloured amber rather than hidden.
struct W4SurfaceFreshnessLabel: View {
    let freshness: W4Freshness?

    var body: some View {
        if let freshness, let caption = Self.caption(for: freshness) {
            Label(caption, systemImage: Self.symbol(for: freshness))
                .font(.caption)
                .foregroundStyle(Self.isStale(freshness) ? Color.orange : Color.secondary)
                .accessibilityLabel(caption)
        }
    }

    static func caption(for freshness: W4Freshness) -> String? {
        switch freshness {
        case .fresh:
            return "Updated just now"
        case .demo:
            return "Demo data. Not connected to W4."
        case .cached(let fetchedAt, _):
            let elapsed = TimeProvider.now.timeIntervalSince(fetchedAt)
            if elapsed < 60 { return "Updated just now" }
            return "Updated \(relativeFormatter.localizedString(for: fetchedAt, relativeTo: TimeProvider.now))"
        }
    }

    static func symbol(for freshness: W4Freshness) -> String {
        switch freshness {
        case .fresh: return "checkmark.circle"
        case .demo: return "info.circle"
        case .cached(_, let isStale): return isStale ? "clock.badge.exclamationmark" : "clock"
        }
    }

    static func isStale(_ freshness: W4Freshness) -> Bool {
        if case .cached(_, let isStale) = freshness { return isStale }
        return false
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.unitsStyle = .full
        return formatter
    }()
}

/// The "nothing here" line used inside a `List` section, where a full-screen
/// `ContentUnavailableView` would be too heavy.
struct W4SurfaceEmptyRow: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.tertiary)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

/// One authenticated W4 page to present as a sheet.
struct W4SurfaceSheetTarget: Identifiable, Equatable {
    let title: String
    let url: URL

    var id: String { url.absoluteString }

    init(title: String, url: URL) {
        self.title = title
        self.url = url
    }

    /// Convenience for a Yii route (`academics/trips`, `documents/index&page_id=870`, …).
    init(title: String, route: String) {
        self.init(title: title, url: W4Routes.url(route))
    }
}

/// A W4 page rendered in-app with the session cookie (plan D-24).
///
/// Used for the surfaces W4 only offers as a form — "Plan new trip", the four travel forms, and
/// any Home link that is a W4 route without a native screen. A demo session never loads a page:
/// there is no session to load it with, and reaching the network would break the demo's zero-traffic
/// promise.
struct W4SurfacePageSheet: View {
    let target: W4SurfaceSheetTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var session: SessionState = .resolving
    @State private var isLoading = false

    enum SessionState: Equatable {
        case resolving
        case live(W4Credentials)
        case demo
        case signedOut
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(target.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if case .live = session {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                openURL(target.url)
                            } label: {
                                Label("Open in Safari", systemImage: "safari")
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task {
            guard let context = W4RequestContext.current() else {
                session = .signedOut
                return
            }
            session = context.isDemo ? .demo : .live(context.credentials)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session {
        case .resolving:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .live(let credentials):
            ZStack(alignment: .top) {
                W4WebView(
                    url: target.url,
                    credentials: credentials,
                    onLoadingChanged: { isLoading = $0 }
                )
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
        case .demo:
            ContentUnavailableView(
                "Not available in the demo",
                systemImage: "lock",
                description: Text("Demo data. Not connected to W4.")
            )
        case .signedOut:
            ContentUnavailableView(
                "Signed out",
                systemImage: "person.crop.circle.badge.exclamationmark",
                description: Text("Log in again to open this page.")
            )
        }
    }
}

/// Renders the `[ContentBlock]` tree `HTMLContentRenderer` produces.
///
/// Images are shown as their alt text rather than fetched: W4 media needs the session cookie, and
/// a broken image well is worse than an honest caption.
struct W4SurfaceRichText: View {
    let blocks: [ContentBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let inlines):
                    Text(Self.attributed(inlines))
                        .font(Self.font(forHeadingLevel: level))
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .paragraph(let inlines):
                    Text(Self.attributed(inlines))
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .image(_, let alt):
                    if !alt.isEmpty {
                        Label(alt, systemImage: "photo")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .divider:
                    Divider()
                }
            }
        }
    }

    static func attributed(_ inlines: [InlineElement]) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            switch inline {
            case .text(let value):
                result.append(AttributedString(value))
            case .link(let text, let url, _):
                var piece = AttributedString(text.isEmpty ? url : text)
                // Only the Foundation `link` attribute is set: SwiftUI already tints and underlines
                // a link, and reaching for the SwiftUI/UIKit style attributes here would be
                // ambiguous in a file that imports both.
                if let link = URL(string: url) { piece.link = link }
                result.append(piece)
            case .image(_, let alt):
                if !alt.isEmpty { result.append(AttributedString(alt)) }
            }
        }
        return result
    }

    private static func font(forHeadingLevel level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.semibold)
        case 2: return .title3.weight(.semibold)
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }
}

// MARK: - Home

/// The Home screen (`index.php?r=site/index`).
struct HomeView: View {

    @StateObject private var viewModel = HomeViewModel()
    @Environment(\.openURL) private var openURL

    /// Only used to reset state when the signed-in student changes; the data itself comes from
    /// `HomeRepository`, which resolves the session for itself.
    var student: Student?

    @State private var sheetTarget: W4SurfaceSheetTarget?

    init(student: Student? = nil) {
        self.student = student
    }

    var body: some View {
        List {
            greetingSection
            attendanceSection
            birthdaysSection
            announcementsSection
            linksSection
            footerSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await viewModel.refresh(student: student) }
        .task { await viewModel.load(student: student) }
        .overlay { overlay }
        .sheet(item: $sheetTarget) { target in
            W4SurfacePageSheet(target: target)
        }
    }

    // MARK: Overlay states

    @ViewBuilder
    private var overlay: some View {
        if viewModel.isLoading, viewModel.snapshot == nil {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        } else if let message = viewModel.errorMessage, viewModel.snapshot == nil {
            ContentUnavailableView {
                Label("Home is unavailable", systemImage: "house.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") {
                    Task { await viewModel.refresh(student: student) }
                }
            }
            .background(.background)
        } else if viewModel.snapshot != nil, viewModel.isEmpty {
            ContentUnavailableView(
                "Nothing on Home",
                systemImage: "house",
                description: Text("W4 returned a Home page with nothing on it.")
            )
            .background(.background)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var greetingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.greeting)
                    .font(.title2.weight(.semibold))

                if let uwcId = viewModel.uwcId {
                    Text(uwcId)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack(spacing: 8) {
                    if let rotation = viewModel.todayRotationDay {
                        rotationChip(rotation)
                    }
                    if viewModel.isTodayNoClasses {
                        chip("No classes", systemImage: "moon.zzz", tint: .orange)
                    }
                }

                if let note = viewModel.todayExtraAcademicsNote {
                    Label(note, systemImage: "figure.outdoor.cycle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                W4SurfaceFreshnessLabel(freshness: viewModel.freshness)
            }
            .padding(.vertical, 4)
        }
    }

    private func rotationChip(_ rotation: String) -> some View {
        chip("Today · \(rotation)", systemImage: "calendar", tint: .accentColor)
    }

    private func chip(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private var attendanceSection: some View {
        Section("Attendance") {
            if viewModel.meters.isEmpty {
                W4SurfaceEmptyRow(text: "Home did not show your attendance meters.", systemImage: "questionmark.circle")
            } else {
                meterRow(title: "Academics", meter: viewModel.meters.academic)
                meterRow(title: "Extra Academics", meter: viewModel.meters.extraAcademic)
            }
        }
    }

    @ViewBuilder
    private func meterRow(title: String, meter: AttendanceMeter?) -> some View {
        if let meter {
            HStack {
                Text(title)
                Spacer()
                HStack(spacing: 12) {
                    meterValue(meter.absences, label: "absences", tint: meter.absences > 0 ? .red : .secondary)
                    meterValue(meter.latenesses, label: "latenesses", tint: meter.latenesses > 0 ? .orange : .secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title): \(meter.absences) absences, \(meter.latenesses) latenesses")
        }
    }

    private func meterValue(_ value: Int, label: String, tint: Color) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var birthdaysSection: some View {
        Section {
            if !viewModel.hasBirthdays {
                W4SurfaceEmptyRow(text: "No birthdays today.", systemImage: "birthday.cake")
            } else {
                if !viewModel.birthdaysToday.isEmpty {
                    birthdayRow(title: "Today", birthdays: viewModel.birthdaysToday)
                }
                if !viewModel.birthdaysTomorrow.isEmpty {
                    birthdayRow(title: "Tomorrow", birthdays: viewModel.birthdaysTomorrow)
                }
            }
            if let calendar = viewModel.birthdaysCalendarURL {
                Button {
                    sheetTarget = W4SurfaceSheetTarget(title: "Birthdays", url: calendar)
                } label: {
                    Label("Birthday calendar", systemImage: "calendar")
                }
            }
        } header: {
            Text("Birthdays")
        } footer: {
            if viewModel.hasBirthdays {
                Text("W4's Home page lists birthdays by photo and UWC id only.")
            }
        }
    }

    private func birthdayRow(title: String, birthdays: [HomeBirthday]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(birthdays) { birthday in
                        Button {
                            guard let url = birthday.profileURL else { return }
                            sheetTarget = W4SurfaceSheetTarget(title: birthday.uwcId, url: url)
                        } label: {
                            HomeBirthdayAvatar(birthday: birthday)
                        }
                        .buttonStyle(.plain)
                        .disabled(birthday.profileURL == nil)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var announcementsSection: some View {
        Section("Announcements") {
            if viewModel.announcements.isEmpty {
                // W4's own sentence when it has nothing, kept verbatim.
                W4SurfaceEmptyRow(
                    text: viewModel.announcementsEmptyText ?? "No announcements.",
                    systemImage: "megaphone"
                )
            } else {
                ForEach(viewModel.announcements) { announcement in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(announcement.title)
                            .font(.headline)
                        if let date = announcement.date {
                            Text(date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let body = announcement.bodyHTML {
                            W4SurfaceRichText(blocks: HTMLContentRenderer.blocks(fromHTML: body))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if let rss = viewModel.announcementsRSSURL {
                Button {
                    openURL(rss)
                } label: {
                    Label("Announcement feed", systemImage: "dot.radiowaves.up.forward")
                }
            }
        }
    }

    @ViewBuilder
    private var linksSection: some View {
        Section {
            if viewModel.links.isEmpty {
                W4SurfaceEmptyRow(text: "No links configured.", systemImage: "link")
            } else {
                ForEach(viewModel.links) { link in
                    linkRow(link)
                }
            }
        } header: {
            Text("Links")
        } footer: {
            Text("Links are configured in W4. External sites open in Safari.")
        }
    }

    @ViewBuilder
    private func linkRow(_ link: HomeLink) -> some View {
        switch viewModel.destination(for: link) {
        case .documents(let library, let route):
            NavigationLink {
                DocumentsView(library: library, route: route, showsUpLink: true)
            } label: {
                Label(link.title, systemImage: viewModel.symbol(for: link))
            }
        case .trips:
            NavigationLink {
                TripsView()
            } label: {
                Label(link.title, systemImage: viewModel.symbol(for: link))
            }
        case .w4Page(let url):
            Button {
                sheetTarget = W4SurfaceSheetTarget(title: link.title, url: url)
            } label: {
                Label(link.title, systemImage: viewModel.symbol(for: link))
            }
        case .external(let url):
            Button {
                openURL(url)
            } label: {
                HStack {
                    Label(link.title, systemImage: viewModel.symbol(for: link))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private var footerSection: some View {
        if let version = viewModel.serverVersion {
            Section {
                if let notes = viewModel.releaseNotesURL {
                    Button {
                        sheetTarget = W4SurfaceSheetTarget(title: "Release notes", url: notes)
                    } label: {
                        HStack {
                            Text("W4 version")
                            Spacer()
                            Text(version)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack {
                        Text("W4 version")
                        Spacer()
                        Text(version)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Birthday avatar

/// One birthday entry: the photo W4 rendered, or a placeholder, plus the UWC id.
///
/// The Home capture carries **no names** — a bare thumbnail wall — so this deliberately shows the
/// UWC id rather than inventing a name row.
struct HomeBirthdayAvatar: View {
    let birthday: HomeBirthday
    var size: CGFloat = 54

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(Circle())
                } else {
                    Image(systemName: birthday.isStaff ? "person.crop.circle" : "person.fill")
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)

            Text(birthday.uwcId)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: size + 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(birthday.isStaff ? "Staff \(birthday.uwcId)" : birthday.uwcId)
        .task(id: birthday.photoURL?.absoluteString) {
            guard let url = birthday.photoURL else {
                image = nil
                return
            }
            image = await W4ImageLoader.shared.loadImage(from: url)
        }
    }
}
