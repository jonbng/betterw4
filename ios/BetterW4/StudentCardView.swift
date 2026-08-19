//
//  StudentCardView.swift
//  BetterW4
//
//  The signed-in student's own W4 identity card.
//
//  **Design decision.** W4's analogue of the old study card is the Letter of Attendance
//  (`people/students/letter/attendance`) — a ~600 KB generated HTML document with no stable
//  structure worth parsing, and no QR code. So this screen is the *profile card*: name, UWC id,
//  year, house, country and the member photo, all from `site/profile` via `ProfileRepository`,
//  which means it renders instantly from cache, works offline and works in demo mode. The Letter
//  of Attendance itself is one tap away, rendered by the authenticated `W4WebView` rather than
//  reparsed.
//

import Combine
import SwiftUI
import UIKit

struct StudentCardView: View {
    let student: Student

    @StateObject private var model = MyProfileModel()
    @State private var didCopyEmail = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                card
                if !student.isDemo {
                    letterOfAttendanceLink
                }
                footer
            }
            .padding(20)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("ID card")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.load(forceRefresh: true)
        }
        .task(id: student.studentId) {
            await model.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterW4CachesDidClear)) { _ in
            Task { await model.load(forceRefresh: true) }
        }
    }

    // MARK: - The card

    private var card: some View {
        VStack(spacing: 0) {
            W4AvatarView(url: photoURL, name: displayName, size: 132)
                .padding(.top, 32)

            VStack(spacing: 6) {
                Text("UWC RED CROSS NORDIC")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .kerning(1.5)
                    .padding(.bottom, 6)

                Text(displayName)
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let subtitle = model.profile?.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)

            Divider()
                .padding(.horizontal, 24)
                .padding(.top, 22)

            VStack(spacing: 14) {
                cardField("UWC ID", value: uwcIdLabel, monospaced: true)
                if let year = model.profile?.year {
                    cardField("YEAR", value: year)
                }
                if let house = model.profile?.house {
                    cardField("HOUSE", value: houseFlagLabel(house))
                }
                if let country = model.profile?.country {
                    cardField("COUNTRY", value: country)
                }
                Button {
                    copyEmail()
                } label: {
                    cardField(
                        didCopyEmail ? "EMAIL (COPIED)" : "EMAIL",
                        value: emailLabel,
                        monospaced: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy email address")
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(UIColor.separator).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 8)
        .overlay(alignment: .center) {
            if model.isLoading {
                ProgressView()
            }
        }
    }

    private func cardField(_ label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(0.85))
                .kerning(0.6)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 15, weight: .medium, design: monospaced ? .monospaced : .default))
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Letter of attendance

    private var letterOfAttendanceLink: some View {
        NavigationLink {
            W4PageScreen(
                title: "Letter of attendance",
                url: W4Routes.url(W4Routes.R.letterOfAttendance)
            )
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "doc.text.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Letter of attendance")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("The document W4 generates for travel and visas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var footer: some View {
        if let message = model.errorMessage, model.profile == nil {
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        } else {
            Text(freshnessLabel)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Values

    private var displayName: String {
        if let profile = model.profile, !profile.displayName.isEmpty, profile.displayName != profile.uwcId {
            return profile.displayName
        }
        let stored = student.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? "Student" : stored
    }

    private var uwcIdLabel: String {
        model.profile?.uwcId ?? student.studentId
    }

    private var emailLabel: String {
        model.profile?.email ?? "\(student.studentId)@uwcrcn.no"
    }

    private var photoURL: URL? {
        model.profile?.photoURL ?? W4PeopleParser.photoURL(forUWCId: student.studentId)
    }

    private func copyEmail() {
        UIPasteboard.general.string = emailLabel
        didCopyEmail = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            didCopyEmail = false
        }
    }

    private var freshnessLabel: String {
        switch model.freshness {
        case .fresh:
            return "Up to date"
        case .demo:
            return "Demo data"
        case .cached(let fetchedAt, let isStale):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let when = formatter.localizedString(for: fetchedAt, relativeTo: TimeProvider.now)
            return isStale ? "Offline copy from \(when)" : "Updated \(when)"
        case nil:
            return ""
        }
    }
}

// MARK: - My profile

/// `site/profile`, cache-first. Nothing here ever clears a card that is already on screen.
@MainActor
final class MyProfileModel: ObservableObject {

    @Published private(set) var profile: StudentProfile?
    @Published private(set) var freshness: W4Freshness?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    private let repository: ProfileRepository
    private var generation = 0

    init(repository: ProfileRepository = .shared) {
        self.repository = repository
    }

    func load(forceRefresh: Bool = false) async {
        generation += 1
        let token = generation

        // A spinner only while the card is blank.
        isLoading = profile == nil
        defer { if token == generation { isLoading = false } }

        do {
            let loaded = try await repository.myProfile(forceRefresh: forceRefresh)
            guard token == generation else { return }
            profile = StudentProfile(profile: loaded.value)
            freshness = loaded.freshness
            errorMessage = nil
        } catch {
            guard token == generation else { return }
            if error is CancellationError { return }
            (error as? W4Error)?.notifyIfSessionExpired()
            if profile == nil {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

// MARK: - Authenticated page host

/// Renders one W4 page inside the app with the signed-in session.
///
/// Used for the two documents that are cheaper to show than to reparse: the Letter of Attendance
/// and a person's own public profile page.
struct W4PageScreen: View {
    let title: String
    let url: URL

    @State private var credentials: W4Credentials = .empty
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else if credentials.isEmpty {
                // Never hand `W4WebView` an empty session: the very first request would 302 to
                // `r=site/login` and be read as a dead cookie (README §4.5).
                ProgressView()
            } else {
                W4WebView(
                    url: url,
                    credentials: credentials,
                    onLoadingChanged: { isLoading = $0 },
                    onError: { error in
                        errorMessage = (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                    }
                )
                .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let context = W4RequestContext.current(), !context.isDemo else {
                isLoading = false
                errorMessage = "This page needs a live W4 session."
                return
            }
            credentials = context.credentials
        }
    }
}

#Preview {
    NavigationStack {
        StudentCardView(student: .demo)
    }
}
