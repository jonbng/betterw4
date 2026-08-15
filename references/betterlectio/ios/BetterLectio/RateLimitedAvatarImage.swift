//
//  RateLimitedAvatarImage.swift
//  BetterLectio
//

import SwiftUI

/// Displays a Lectio profile image with rate-limited loading to avoid blank images.
/// Falls back to the provided placeholder when URL is nil or loading fails.
struct RateLimitedAvatarImage<Placeholder: View>: View {
    let url: URL?
    let size: CGFloat
    /// When false (e.g. QR codes), the image is square with sharp corners instead of circular.
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
            loadedImage = await LectioImageLoader.shared.loadImage(from: url)
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

/// Reusable avatar view that shows a Lectio profile picture with initials fallback.
/// Consolidates avatar rendering logic used across the app.
struct LectioAvatarView: View {
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
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts.first!.prefix(1))\(parts.last!.prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var color: Color {
        let index = Int(UInt(bitPattern: name.hashValue) % UInt(Self.avatarColors.count))
        return Self.avatarColors[index]
    }

    static func initialsPlaceholder(name: String, size: CGFloat) -> some View {
        let parts = name.split(separator: " ")
        let initials: String = if parts.count >= 2 {
            "\(parts.first!.prefix(1))\(parts.last!.prefix(1))".uppercased()
        } else {
            String(name.prefix(2)).uppercased()
        }
        let index = Int(UInt(bitPattern: name.hashValue) % UInt(avatarColors.count))
        let color = avatarColors[index]
        return Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(Circle())
    }

    static func pictureURL(for senderName: String, gymId: Int) -> URL? {
        DirectoryStore.shared.pictureURL(forName: senderName, gymId: gymId)
    }
}

/// Rate-limited image for larger previews (e.g. context menu). Uses .fit content mode.
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
            loadedImage = await LectioImageLoader.shared.loadImage(from: url)
        }
    }
}
