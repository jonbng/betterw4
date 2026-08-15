import Combine
import SwiftUI
import UIKit

@MainActor
final class ReferralViewModel: ObservableObject {
    @Published var stats: ReferralStats?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var copied = false

    let student: Student
    private let coordinator: ReferralCoordinator

    init(student: Student, coordinator: ReferralCoordinator = .shared) {
        self.student = student
        self.coordinator = coordinator
        self.stats = student.isDemo ? .demo : coordinator.cachedStats(for: student)
    }

    var shareURL: URL? {
        student.isDemo ? nil : ReferralLink.shareURL(studentID: student.studentId)
    }

    var progress: ReferralProgress {
        ReferralProgress(conversions: stats?.conversions ?? 0)
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        if let result = await coordinator.refreshStats(for: student) {
            stats = result
        } else {
            errorMessage = "Kunne ikke hente henvisninger. Prøv igen."
        }
        isLoading = false
    }

    func copyLink() {
        guard let shareURL else { return }
        UIPasteboard.general.url = shareURL
        copied = true
        UIAccessibility.post(notification: .announcement, argument: "Link kopieret")
        Analytics.capture("referral_shared", properties: ["method": "copy"])
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    func didShare() {
        Analytics.capture("referral_share_sheet_opened")
    }
}

struct ReferralView: View {
    @StateObject private var viewModel: ReferralViewModel
    @State private var showingProfilePictureEditor = false

    init(student: Student) {
        _viewModel = StateObject(wrappedValue: ReferralViewModel(student: student))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                rewardCard
                profilePictureTeaser
                shareCard
                statistics
                recentReferrals
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Inviter venner")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.refresh() }
        .refreshable { await viewModel.refresh() }
        .sheet(isPresented: $showingProfilePictureEditor) {
            ProfilePictureEditorView(student: viewModel.student)
        }
    }

    private var rewardCard: some View {
        let progress = viewModel.progress
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(progress.unlocked ? "Profilbillede låst op" : "Lås profilbillede op")
                    .font(.headline)
                Spacer()
                Text(viewModel.isLoading && viewModel.stats == nil ? "…" : "\(progress.current)/\(progress.target)")
                    .font(.title2.bold())
                    .foregroundStyle(Color.accentColor)
            }
            ProgressView(value: progress.fraction)
                .tint(progress.unlocked ? .green : .accentColor)
            Text(progress.unlocked
                 ? "Du kan nu vælge dit eget profilbillede. Det bliver vist, når det er godkendt."
                 : "Inviter \(progress.remaining) mere for at låse dit eget profilbillede op.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var profilePictureTeaser: some View {
        Button {
            if viewModel.progress.unlocked { showingProfilePictureEditor = true }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: viewModel.progress.unlocked ? "person.crop.circle.badge.checkmark" : "lock.fill")
                    .font(.title3)
                    .foregroundStyle(viewModel.progress.unlocked ? Color.accentColor : .secondary)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dit eget profilbillede").font(.headline)
                    Text(viewModel.progress.unlocked ? "Tryk for at vælge et billede" : "Inviter 3 klassekammerater for at låse op")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.progress.unlocked {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.progress.unlocked)
    }

    private var shareCard: some View {
        VStack(spacing: 10) {
            if let url = viewModel.shareURL {
                ShareLink(item: url, subject: Text("Prøv BetterLectio"), message: Text("Prøv BetterLectio. Lectio der faktisk virker på mobilen.")) {
                    Label("Del med din klasse", systemImage: "square.and.arrow.up")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .simultaneousGesture(TapGesture().onEnded { _ in viewModel.didShare() })

                Button(action: viewModel.copyLink) {
                    Label(viewModel.copied ? "Kopieret" : "Kopiér link", systemImage: viewModel.copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                Text(url.absoluteString.replacingOccurrences(of: "https://", with: ""))
                    .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Label("Deling er slået fra i demo", systemImage: "info.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var statistics: some View {
        if let errorMessage = viewModel.errorMessage, viewModel.stats == nil {
            ContentUnavailableView {
                Label("Kunne ikke hente henvisninger", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Prøv igen") { Task { await viewModel.refresh() } }
            }
        } else {
            HStack(spacing: 12) {
                statistic(value: viewModel.stats?.conversions, label: "Inviterede", accent: true)
                statistic(value: viewModel.stats?.totalClicks, label: "Klik", accent: false)
            }
        }
    }

    private func statistic(value: Int?, label: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.map { String($0) } ?? "…")
                .font(.title.bold()).foregroundStyle(accent ? Color.accentColor : .primary)
                .monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var recentReferrals: some View {
        let referrals = viewModel.stats?.recentReferrals ?? []
        if !referrals.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Senest inviterede").font(.headline)
                ForEach(referrals) { referral in
                    HStack(spacing: 11) {
                        LectioAvatarView.initialsPlaceholder(name: referral.name ?? "Anonym", size: 36)
                        Text(referral.name ?? "Anonym")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

struct ReferralNudgeView: View {
    let student: Student
    @ObservedObject private var coordinator = ReferralCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 42, weight: .semibold)).foregroundStyle(Color.accentColor)
            Text("Del med din klasse").font(.title2.bold())
            Text("\(ReferralProgress(conversions: coordinator.cachedStats(for: student)?.conversions ?? 0).remaining) tilbage til dit eget profilbillede.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let url = ReferralLink.shareURL(studentID: student.studentId) {
                ShareLink(item: url, message: Text("Prøv BetterLectio. Lectio der faktisk virker på mobilen.")) {
                    Label("Del nu", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Ikke nu") {
                coordinator.dismissNudge(for: student)
                dismiss()
            }
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
