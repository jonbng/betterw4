//
//  DesignSystem.swift
//  BetterLectioMac
//
//  Shared visual tokens. Deliberately small — the goal is to match the iOS app's
//  look (see BetterLectio/LoginView.swift), which is stock system materials with a
//  consistent corner-radius scale and SF Symbols, not a bespoke theme.
//

import SwiftUI

enum BL {

    // MARK: - Identifiers

    /// Bundle identifier of the embedded Safari Web Extension appex.
    /// Must stay in sync with PRODUCT_BUNDLE_IDENTIFIER on the
    /// BetterLectioSafariExtension target.
    static let extensionBundleID = "dk.echolabs.betterlectio.app.safari"

    static let lectioURL = URL(string: "https://www.lectio.dk/")!
    static let githubURL = URL(string: "https://github.com/jonbng/betterlectio")!
    static let privacyURL = URL(string: "https://betterlectio.dk/privatliv")!
    static let feedbackURL = URL(string: "https://github.com/jonbng/betterlectio/issues")!

    /// iOS app. Goes through betterlectio.dk's App Store redirect rather than a
    /// hardcoded Apple ID — the same endpoint the extension uses
    /// (`APP_STORE_REDIRECT_BASE` in the extension's lib/mobile-app.ts).
    /// Same App Store record as this app (Universal Purchase), so anyone who has
    /// the Mac app sees the iOS app as already owned.
    static let iosAppURL = URL(string: "https://betterlectio.dk/download/ios")!

    // MARK: - Corner radii

    /// Matches the iOS app's `.continuous` scale: 12 small tiles, 14 icon chips,
    /// 16 cards, 18 prominent cards.
    enum Radius {
        static let small: CGFloat = 12
        static let chip: CGFloat = 14
        static let card: CGFloat = 16
        static let prominent: CGFloat = 18
    }

    // MARK: - Spacing

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: - Colors

    /// macOS analogues of the iOS system-grouped background family.
    enum Palette {
        static let windowBackground = Color(nsColor: .windowBackgroundColor)
        static let cardBackground = Color(nsColor: .controlBackgroundColor)
        static let nestedBackground = Color(nsColor: .underPageBackgroundColor)
        static let hairline = Color(nsColor: .separatorColor)
    }

    // MARK: - Type

    /// The wordmark. `.rounded` is used *only* for the app name, matching
    /// LoginView.swift — everywhere else uses semantic text styles.
    static func wordmark(size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

// MARK: - Shared building blocks

/// A 52pt rounded-rect glyph chip — the iOS app's list-row icon treatment.
struct IconChip: View {
    let systemName: String
    var tint: Color = .accentColor
    var size: CGFloat = 52

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BL.Radius.chip, style: .continuous)
                .fill(tint.opacity(0.15))
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }
}

/// Standard card surface: filled, hairline-bordered, continuous corners.
struct CardBackground: ViewModifier {
    var radius: CGFloat = BL.Radius.card

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(BL.Palette.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(BL.Palette.hairline.opacity(0.55), lineWidth: 0.5)
            )
    }
}

extension View {
    func blCard(radius: CGFloat = BL.Radius.card) -> some View {
        modifier(CardBackground(radius: radius))
    }
}

/// Small status pill used in onboarding and the status screen.
struct StatusPill: View {
    let isOn: Bool
    let onText: String
    let offText: String

    var body: some View {
        HStack(spacing: BL.Space.s) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isOn ? Color.green : Color.secondary)
                .font(.system(size: 14, weight: .semibold))
            Text(isOn ? onText : offText)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isOn ? Color.green : Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, BL.Space.s)
        .background(
            Capsule().fill((isOn ? Color.green : Color.secondary).opacity(0.12))
        )
        .animation(.snappy(duration: 0.28), value: isOn)
        .accessibilityElement(children: .combine)
    }
}
