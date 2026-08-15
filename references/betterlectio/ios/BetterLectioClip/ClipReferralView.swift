import StoreKit
import SwiftUI
import UIKit

struct ClipReferralView: View {
    @State private var saved = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var invocationURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("B")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 82, height: 82)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.28), radius: 18, y: 9)
                .accessibilityHidden(true)

            Text(saved ? "Invitationen er gemt" : "Du er inviteret")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text(saved
                 ? "Hent BetterLectio og log ind. Vi knytter invitationen automatisk til din første installation."
                 : "Vi gør invitationen klar, så den følger med over i BetterLectio.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Button("Prøv igen") { beginCapture(invocationURL) }
                    .buttonStyle(.bordered)
            }

            Button {
                presentInstallOverlay()
            } label: {
                Label("Hent BetterLectio", systemImage: "arrow.down.app.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!saved)
            .frame(maxWidth: 360)
            Spacer()
        }
        .padding(24)
        .background(Color(uiColor: .systemGroupedBackground))
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            beginCapture(activity.webpageURL)
        }
        .onOpenURL(perform: beginCapture)
        .overlay {
            if isSaving {
                ProgressView("Gemmer invitation…")
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityAddTraits(.isModal)
            }
        }
    }

    private func beginCapture(_ url: URL?) {
        guard !isSaving, !saved else { return }
        invocationURL = url
        isSaving = true
        Task { await capture(url) }
    }

    @MainActor
    private func capture(_ url: URL?) async {
        defer { isSaving = false }
        guard let url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "betterlectio.dk",
              url.pathComponents.count == 3,
              url.pathComponents[1] == "r" else {
            errorMessage = "Invitationen mangler en gyldig kode. Åbn det oprindelige link igen."
            return
        }
        let studentID = url.pathComponents[2]
        let allowedStudentCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard !studentID.isEmpty,
              studentID.count <= 48,
              studentID.unicodeScalars.allSatisfy(allowedStudentCharacters.contains) else {
            errorMessage = "Invitationen mangler en gyldig kode. Åbn det oprindelige link igen."
            return
        }
        let tokenValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "bl_ref" })?.value
        let suppliedToken = tokenValue.flatMap(UUID.init(uuidString:))
        if tokenValue != nil && suppliedToken == nil {
            errorMessage = "Invitationen er ugyldig eller udløbet. Bed afsenderen om et nyt link."
            return
        }
        let token: UUID
        do {
            if let suppliedToken {
                guard try await ReferralClickClient.validate(suppliedToken, studentID: studentID) else {
                    errorMessage = "Invitationen er ugyldig eller udløbet. Bed afsenderen om et nyt link."
                    return
                }
                token = suppliedToken
            } else {
                token = try await ReferralClickClient.register(studentID: studentID)
            }
        } catch {
            errorMessage = "Invitationen kunne ikke gemmes. Kontrollér forbindelsen og prøv igen."
            return
        }
        let defaults = UserDefaults(suiteName: "group.dk.echolabs.betterlectio.app.referral") ?? .standard
        let key = "referral.pending.v1"
        guard defaults.data(forKey: key) == nil else {
            saved = true
            return
        }
        let pending = ClipPendingReferral(token: token, capturedAt: Date())
        do {
            defaults.set(try JSONEncoder().encode(pending), forKey: key)
            saved = true
            errorMessage = nil
            UIAccessibility.post(notification: .announcement, argument: "Invitationen er gemt")
        } catch {
            errorMessage = "Invitationen kunne ikke gemmes. Prøv igen."
        }
    }

    private func presentInstallOverlay() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let configuration = SKOverlay.AppClipConfiguration(position: .bottomRaised)
        SKOverlay(configuration: configuration).present(in: scene)
    }
}

private enum ReferralClickClient {
    private static func endpoint() throws -> URL {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let base = URL(string: value) else { throw URLError(.badURL) }
        return base.appending(path: "functions/v1/referral-click")
    }

    static func register(studentID: String) async throws -> UUID {
        let payload = try await request(studentID: studentID, delivery: "json")
        guard let value = payload.cookieId, let token = UUID(uuidString: value) else { throw URLError(.badServerResponse) }
        return token
    }

    static func validate(_ token: UUID, studentID: String) async throws -> Bool {
        let payload = try await request(studentID: studentID, delivery: "validate", token: token)
        return payload.valid == true
    }

    private static func request(studentID: String, delivery: String, token: UUID? = nil) async throws -> ClipClickResponse {
        var components = URLComponents(url: try endpoint(), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "ref", value: studentID),
            URLQueryItem(name: "delivery", value: delivery),
        ]
        if let token {
            queryItems.append(URLQueryItem(name: "token", value: token.uuidString.lowercased()))
        }
        components.queryItems = queryItems
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ClipClickResponse.self, from: data)
    }
}

private struct ClipClickResponse: Decodable {
    let cookieId: String?
    let valid: Bool?
}

private struct ClipPendingReferral: Codable {
    let token: UUID
    let capturedAt: Date
}
