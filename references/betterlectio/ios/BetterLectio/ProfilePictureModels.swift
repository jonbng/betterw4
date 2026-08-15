import Foundation

struct ProfilePictureSubmission: Decodable, Equatable, Sendable {
    let id: String
    let status: String
    let createdAt: String
    let submittedAt: String?
    let reviewedAt: String?
    let rejectionReason: String?
    let reviewNote: String?
    let approvedURL: String?

    enum CodingKeys: String, CodingKey {
        case id, status, createdAt, submittedAt, reviewedAt, rejectionReason, reviewNote
        case approvedURL = "approvedUrl"
    }

    var isPending: Bool { status == "pending" || status == "uploading" }
    var wasRejected: Bool { status == "rejected" }
}

struct ProfilePictureState: Decodable, Equatable, Sendable {
    let unlocked: Bool
    let referralConversions: Int
    let unlockThreshold: Int
    let currentURL: String?
    let approvedAt: String?
    let nextEligibleAt: String?
    let canSubmit: Bool
    let submission: ProfilePictureSubmission?

    enum CodingKeys: String, CodingKey {
        case unlocked, referralConversions, unlockThreshold, approvedAt, nextEligibleAt, canSubmit, submission
        case currentURL = "currentUrl"
    }

    var isPending: Bool { submission?.isPending == true }
    var wasRejected: Bool { submission?.wasRejected == true }
    var currentImageURL: URL? {
        guard let currentURL,
              let url = URL(string: currentURL),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else { return nil }
        return url
    }

    static let demo = ProfilePictureState(
        unlocked: true,
        referralConversions: 3,
        unlockThreshold: 3,
        currentURL: nil,
        approvedAt: nil,
        nextEligibleAt: nil,
        canSubmit: true,
        submission: nil
    )
}

struct ProfilePictureSubmitResult: Decodable, Sendable {
    let ok: Bool
    let code: String?
    let error: String?
}

struct PreparedProfilePicture: Sendable, Equatable {
    let data: Data
    let mimeType: String
    let fileExtension: String
}

enum ProfilePictureValidationError: Error, Equatable, Sendable {
    case empty
    case tooLarge
    case unsupportedType
    case mismatchedContents
}

enum ProfilePictureValidator {
    nonisolated static let maximumBytes = 5 * 1024 * 1024

    nonisolated static func validate(_ picture: PreparedProfilePicture) throws {
        guard !picture.data.isEmpty else { throw ProfilePictureValidationError.empty }
        guard picture.data.count <= maximumBytes else { throw ProfilePictureValidationError.tooLarge }

        let mime = picture.mimeType.lowercased()
        let fileExtension = picture.fileExtension.lowercased()
        let validExtension: Bool
        switch mime {
        case "image/jpeg", "image/jpg": validExtension = fileExtension == "jpg" || fileExtension == "jpeg"
        case "image/png": validExtension = fileExtension == "png"
        case "image/webp": validExtension = fileExtension == "webp"
        default: throw ProfilePictureValidationError.unsupportedType
        }
        guard validExtension else { throw ProfilePictureValidationError.unsupportedType }
        guard detectedMIME(in: picture.data) == normalizedMIME(mime) else {
            throw ProfilePictureValidationError.mismatchedContents
        }
    }

    private nonisolated static func normalizedMIME(_ mime: String) -> String {
        mime == "image/jpg" ? "image/jpeg" : mime
    }

    private nonisolated static func detectedMIME(in data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 3, bytes[0] == 0xff, bytes[1] == 0xd8, bytes[2] == 0xff {
            return "image/jpeg"
        }
        if bytes.count >= 8,
           bytes[0...7].elementsEqual([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) {
            return "image/png"
        }
        if bytes.count >= 12,
           String(bytes: bytes[0...3], encoding: .ascii) == "RIFF",
           String(bytes: bytes[8...11], encoding: .ascii) == "WEBP" {
            return "image/webp"
        }
        return nil
    }
}
