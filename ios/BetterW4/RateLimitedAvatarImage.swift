//
//  RateLimitedAvatarImage.swift
//  BetterW4
//
//  The portrait views. Every one of them goes through `W4ImageLoader`, which rate-limits and
//  deduplicates, so a 200-row directory cannot flood W4's single Apache box.
//
//  There is no `gymId` anywhere here: W4 is one school, and a portrait is addressed by uwc id
//  alone (`W4PeopleParser.photoURL(forUWCId:)`).
//

import SwiftUI

/// A W4 portrait, loaded through the rate-limited image loader.
/// Falls back to `placeholder` when the URL is nil or the fetch fails.
struct RateLimitedAvatarImage<Placeholder: View>: View {
    let url: URL?
    let size: CGFloat
    /// When false the image is square with sharp corners instead of circular.
    var clipsToCircle: Bool = true
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
            if clipsToCircle {
                core.clipShape(Circle())
            } else {
                core
            }
        }
        .task(id: url?.absoluteString) {
            guard let url else {
                loadedImage = nil
                return
            }
            loadedImage = await W4ImageLoader.shared.loadImage(from: url)
        }
    }

    private var core: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder()
            }
        }
        .frame(width: size, height: size, alignment: .top)
        .clipped()
    }
}

/// A W4 portrait with an initials fallback — the avatar used across the app.
struct W4AvatarView: View {
    let url: URL?
    let name: String
    let size: CGFloat

    static let avatarColors: [Color] = [
        .blue, .purple, .orange, .pink, .green, .red,
        .teal, .indigo, .cyan, .brown, .mint, .yellow
    ]

    var body: some View {
        RateLimitedAvatarImage(url: url, size: size) {
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(color)
                .clipShape(Circle())
        }
        .accessibilityLabel(Text(name))
    }

    private var initials: String {
        Self.initials(for: name)
    }

    private var color: Color {
        Self.color(for: name)
    }

    /// First letter of the first and last name, uppercased. Never empty for a non-empty name.
    static func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts.first!.prefix(1))\(parts.last!.prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// A stable colour per name so the same person keeps the same tile between launches.
    static func color(for name: String) -> Color {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(name.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return avatarColors[Int(hash % UInt64(avatarColors.count))]
    }

    static func initialsPlaceholder(name: String, size: CGFloat) -> some View {
        Text(initials(for: name))
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(color(for: name))
            .clipShape(Circle())
    }

    /// W4's portrait convention: `/files/user_photos/{uwc_id}_photo.jpg`.
    static func portraitURL(forUWCId uwcId: String) -> URL? {
        W4PeopleParser.photoURL(forUWCId: uwcId)
    }
}

/// A larger, aspect-fit portrait for context-menu previews.
struct RateLimitedPreviewImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder()
            }
        }
        .task(id: url?.absoluteString) {
            guard let url else {
                loadedImage = nil
                return
            }
            loadedImage = await W4ImageLoader.shared.loadImage(from: url)
        }
    }
}
