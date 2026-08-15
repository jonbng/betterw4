//
//  LectioQrMintService.swift
//  BetterLectio
//
//  Mints a Lectio login QR from studentIndstillinger (same flow as the extension)
//  so Supabase auth can call lectio-auth without transferring Lectio cookies.
//

import Foundation
import UIKit
import Vision

struct LectioQrCredentials: Sendable {
    let qrId: String
    let userId: String
}

enum LectioQrMintError: Error, LocalizedError {
    case missingForm
    case missingQrImage
    case decodeFailed
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .missingForm: return "Could not load Lectio settings form for QR mint"
        case .missingQrImage: return "Lectio QR image not found in settings response"
        case .decodeFailed: return "Failed to decode Lectio login QR"
        case .invalidPayload: return "Lectio QR payload missing userId/QrId"
        }
    }
}

enum LectioQrMintService {
    private static let eventTarget = "s$m$Content$Content$getQRcodeBtn"
    private static let initializePattern = try! NSRegularExpression(
        pattern: #"LectioQRCode\.Initialize\(\s*'[^']*'\s*,\s*'([^']*)'\s*,\s*'([^']*)'"#,
        options: []
    )

    static func mint(
        credentials: LectioCredentials,
        studentId: String,
        gymId: Int,
        httpClient: LectioHTTPClient = LectioHTTPClient()
    ) async throws -> LectioQrCredentials {
        let pageURL = URL(string: "https://www.lectio.dk/lectio/\(gymId)/indstillinger/studentIndstillinger.aspx")!
        let (pageData, _, _) = try await httpClient.performRequest(
            url: pageURL,
            credentials: credentials,
            studentId: studentId,
            contextForLogging: "qr-mint-get"
        )
        let pageHTML = httpClient.decodeHTML(from: pageData)
        let formFields = try BaseParser.parseAllFormFields(from: pageHTML)

        var parts: [String] = ["__EVENTTARGET=\(httpClient.formURLEncode(eventTarget))", "__EVENTARGUMENT="]
        let skip: Set<String> = ["__EVENTTARGET", "__EVENTARGUMENT"]
        for field in formFields where !skip.contains(field.name) {
            parts.append("\(httpClient.formURLEncode(field.name))=\(httpClient.formURLEncode(field.value))")
        }
        let body = parts.joined(separator: "&").data(using: .utf8)

        let (postData, _, _) = try await httpClient.performRequest(
            url: pageURL,
            method: "POST",
            body: body,
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            credentials: credentials,
            studentId: studentId,
            contextForLogging: "qr-mint-post"
        )
        let postHTML = httpClient.decodeHTML(from: postData)
        let imageRef = try extractQrImageURL(from: postHTML)
        let imageData: Data
        if imageRef.hasPrefix("data:") {
            guard let decoded = decodeDataURIIfNeeded(Data(imageRef.utf8)) else {
                throw LectioQrMintError.missingQrImage
            }
            imageData = decoded
        } else if let rawBase64 = Data(base64Encoded: imageRef), !rawBase64.isEmpty {
            imageData = rawBase64
        } else {
            let imageURL = try absolutize(imageRef, gymId: gymId)
            let (fetched, _, _) = try await httpClient.performRequest(
                url: imageURL,
                credentials: credentials,
                studentId: studentId,
                contextForLogging: "qr-mint-image"
            )
            imageData = fetched
        }
        guard let payload = await decodeQRPayload(from: imageData) else {
            throw LectioQrMintError.decodeFailed
        }
        return try parseQrCredentials(from: payload)
    }

    private static func extractQrImageURL(from html: String) throws -> String {
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        if let match = initializePattern.firstMatch(in: html, options: [], range: range),
           match.numberOfRanges >= 3 {
            for index in 1...2 {
                if let swiftRange = Range(match.range(at: index), in: html) {
                    let candidate = String(html[swiftRange])
                    if !candidate.isEmpty { return candidate }
                }
            }
        }

        // Fallback: img inside .qrKode-container
        if let srcRange = html.range(
            of: #"class=["'][^"']*qrKode-container[^"']*["'][^>]*>[\s\S]*?<img[^>]+src=["']([^"']+)["']"#,
            options: .regularExpression
        ) {
            let snippet = String(html[srcRange])
            if let srcMatch = snippet.range(of: #"src=["']([^"']+)["']"#, options: .regularExpression) {
                let attr = String(snippet[srcMatch])
                if let valueRange = attr.range(of: #"(?<=src=["'])[^"']+"#, options: .regularExpression) {
                    let src = String(attr[valueRange])
                    if src != "about:blank" { return src }
                }
            }
        }
        throw LectioQrMintError.missingQrImage
    }

    private static func absolutize(_ raw: String, gymId: Int) throws -> URL {
        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }
        if raw.hasPrefix("/") {
            return URL(string: "https://www.lectio.dk\(raw)")!
        }
        return URL(string: "https://www.lectio.dk/lectio/\(gymId)/\(raw)")!
    }

    private static func decodeQRPayload(from data: Data) async -> String? {
        if let dataURIPayload = decodeDataURIIfNeeded(data) {
            return await decodeQRImageData(dataURIPayload)
        }
        return await decodeQRImageData(data)
    }

    private static func decodeDataURIIfNeeded(_ data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8),
              text.hasPrefix("data:"),
              let comma = text.firstIndex(of: ",") else { return nil }
        let meta = text[..<comma]
        let payload = String(text[text.index(after: comma)...])
        if meta.contains(";base64") {
            return Data(base64Encoded: payload)
        }
        return payload.data(using: .utf8)
    }

    private static func decodeQRImageData(_ data: Data) async -> String? {
        guard let image = UIImage(data: data)?.cgImage else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNDetectBarcodesRequest()
                request.symbologies = [.qr]
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                do {
                    try handler.perform([request])
                    let value = request.results?.compactMap { $0.payloadStringValue }.first
                    continuation.resume(returning: value)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func parseQrCredentials(from payload: String) throws -> LectioQrCredentials {
        guard let url = URL(string: payload),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw LectioQrMintError.invalidPayload
        }
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            guard let value = item.value else { return nil }
            return (item.name.lowercased(), value)
        })
        let qrId = items["qrid"]
        let userId = items["userid"]
        guard let qrId, let userId, !qrId.isEmpty, !userId.isEmpty else {
            throw LectioQrMintError.invalidPayload
        }
        return LectioQrCredentials(qrId: qrId, userId: userId)
    }
}
