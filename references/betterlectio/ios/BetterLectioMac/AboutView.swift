//
//  AboutView.swift
//  BetterLectioMac
//
//  Version info, links, and the iOS cross-promo — which is the point of putting
//  both platforms under one Universal Purchase record: the iPhone app already
//  shows as owned for anyone who has this one.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: BL.Space.l) {
                header
                crossPromoCard
                linksCard
                colophon
            }
            .frame(maxWidth: 560)
            .padding(BL.Space.xl)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: BL.Space.s) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            } else {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
            }

            Text("BetterLectio")
                .font(BL.wordmark(size: 30))

            Text("Version \(AppVersion.marketing) (\(AppVersion.build))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let info = ExtensionBuildInfo.bundled {
                Text("Udvidelse \(info.extensionVersion)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .padding(.bottom, BL.Space.s)
    }

    // MARK: - iOS cross-promo

    private var crossPromoCard: some View {
        HStack(spacing: BL.Space.m) {
            IconChip(systemName: "iphone.gen3", size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text("BetterLectio til iPhone")
                    .font(.headline)
                Text("Skema, lektier og beskeder i lommen. Den er allerede købt. Samme app i App Store.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: BL.Space.m)

            Button("Hent") {
                NSWorkspace.shared.open(BL.iosAppURL)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(BL.Space.m)
        .blCard(radius: BL.Radius.prominent)
    }

    // MARK: - Links

    private var linksCard: some View {
        VStack(spacing: 0) {
            LinkRow(icon: "chevron.left.forwardslash.chevron.right",
                    title: "Kildekode på GitHub",
                    url: BL.githubURL)

            Divider().padding(.leading, 60)

            LinkRow(icon: "hand.raised.fill",
                    title: "Privatlivspolitik",
                    url: BL.privacyURL)

            Divider().padding(.leading, 60)

            LinkRow(icon: "ladybug.fill",
                    title: "Rapportér et problem",
                    url: BL.feedbackURL)
        }
        .blCard()
    }

    // MARK: - Colophon

    private var colophon: some View {
        VStack(spacing: BL.Space.xs) {
            Text("Lavet af elever, til elever.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("BetterLectio er ikke tilknyttet MaCom A/S eller Lectio.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, BL.Space.s)
    }
}

// MARK: - Link row

private struct LinkRow: View {
    let icon: String
    let title: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            DetailRow(icon: icon, title: title, value: nil, showsChevron: true)
        }
        .buttonStyle(.plain)
    }
}
