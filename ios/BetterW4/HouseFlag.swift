//
//  HouseFlag.swift
//  BetterW4
//
//  Country flags for the five UWC RCN boarding houses. Drawn as Nordic crosses
//  so they stay the same size on every list row; the emoji is for titles.
//

import SwiftUI

enum HouseFlagKind: String, Equatable, Sendable {
    case denmark
    case finland
    case iceland
    case norway
    case sweden
    case graduated

    var emoji: String {
        switch self {
        case .denmark: return "🇩🇰"
        case .finland: return "🇫🇮"
        case .iceland: return "🇮🇸"
        case .norway: return "🇳🇴"
        case .sweden: return "🇸🇪"
        case .graduated: return "🎓"
        }
    }

    static func of(_ houseIdOrName: String?) -> HouseFlagKind? {
        let raw = houseIdOrName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        let folded = raw.lowercased()
            .replacingOccurrences(of: "å", with: "a")
        let key = folded.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        switch key {
        case "denmark", "dk": return .denmark
        case "finland", "fi": return .finland
        case "iceland", "is": return .iceland
        case "norway", "no": return .norway
        case "sweden", "se": return .sweden
        case "grad", "graduated": return .graduated
        default: return nil
        }
    }
}

extension House {
    var flagKind: HouseFlagKind? { HouseFlagKind.of(id) ?? HouseFlagKind.of(name) }

    var flaggedName: String {
        if let emoji = flagKind?.emoji { return "\(emoji) \(name)" }
        return name
    }
}

func houseFlagLabel(_ name: String, houseId: String? = nil) -> String {
    let kind = HouseFlagKind.of(houseId) ?? HouseFlagKind.of(name)
    guard let kind else { return name }
    return "\(kind.emoji) \(name)"
}

/// Drawn Nordic flag (or a mortarboard tile for Graduated).
struct HouseFlagView: View {
    let kind: HouseFlagKind
    var width: CGFloat = 36

    init(kind: HouseFlagKind, width: CGFloat = 36) {
        self.kind = kind
        self.width = width
    }

    init?(houseIdOrName: String, width: CGFloat = 36) {
        guard let kind = HouseFlagKind.of(houseIdOrName) else { return nil }
        self.kind = kind
        self.width = width
    }

    var body: some View {
        Canvas { context, size in
            context.drawHouseFlag(kind, in: CGRect(origin: .zero, size: size))
        }
        .frame(width: width, height: width * 16 / 21)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .accessibilityLabel(kind.emoji)
    }
}

private extension GraphicsContext {
    func drawHouseFlag(_ kind: HouseFlagKind, in rect: CGRect) {
        switch kind {
        case .denmark:
            nordicCross(in: rect, field: Color(red: 0.784, green: 0.063, blue: 0.180), cross: .white)
        case .finland:
            nordicCross(in: rect, field: .white, cross: Color(red: 0.000, green: 0.184, blue: 0.424))
        case .sweden:
            nordicCross(
                in: rect,
                field: Color(red: 0.000, green: 0.416, blue: 0.655),
                cross: Color(red: 0.996, green: 0.800, blue: 0.000)
            )
        case .norway:
            nordicCross(
                in: rect,
                field: Color(red: 0.729, green: 0.047, blue: 0.184),
                cross: .white,
                inner: Color(red: 0.000, green: 0.125, blue: 0.357)
            )
        case .iceland:
            nordicCross(
                in: rect,
                field: Color(red: 0.008, green: 0.322, blue: 0.612),
                cross: .white,
                inner: Color(red: 0.863, green: 0.118, blue: 0.208)
            )
        case .graduated:
            fill(Path(rect), with: .color(Color(red: 0.361, green: 0.388, blue: 0.439)))
            let cap = Color(red: 0.910, green: 0.894, blue: 0.851)
            let cx = rect.midX
            let cy = rect.midY
            let w = rect.width * 0.42
            fill(
                Path(CGRect(x: cx - w / 2, y: cy - rect.height * 0.06, width: w, height: rect.height * 0.08)),
                with: .color(cap)
            )
            fill(
                Path(ellipseIn: CGRect(
                    x: cx - rect.height * 0.07,
                    y: cy - rect.height * 0.21,
                    width: rect.height * 0.14,
                    height: rect.height * 0.14
                )),
                with: .color(cap)
            )
        }
    }

    func nordicCross(in rect: CGRect, field: Color, cross: Color, inner: Color? = nil) {
        fill(Path(rect), with: .color(field))
        let t = rect.height / 5
        let vx = rect.width * 0.30 - t / 2
        fill(Path(CGRect(x: vx, y: 0, width: t, height: rect.height)), with: .color(cross))
        fill(Path(CGRect(x: 0, y: rect.height / 2 - t / 2, width: rect.width, height: t)), with: .color(cross))
        if let inner {
            let ti = t * 0.48
            let vxi = vx + (t - ti) / 2
            fill(Path(CGRect(x: vxi, y: 0, width: ti, height: rect.height)), with: .color(inner))
            fill(
                Path(CGRect(x: 0, y: rect.height / 2 - ti / 2, width: rect.width, height: ti)),
                with: .color(inner)
            )
        }
    }
}
