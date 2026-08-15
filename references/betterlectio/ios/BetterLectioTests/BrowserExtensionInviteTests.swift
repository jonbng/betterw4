import UIKit
import XCTest
@testable import BetterLectio

@MainActor
final class BrowserExtensionInviteTests: XCTestCase {
    func testCanonicalDownloadURLIsHTTPS() {
        XCTAssertEqual(BetterLectioLinks.downloadURL.absoluteString, "https://betterlectio.dk/download")
        XCTAssertEqual(BetterLectioLinks.downloadURL.scheme, "https")
    }

    func testCopyPlacesCanonicalURLOnPasteboard() {
        let pasteboard = UIPasteboard.withUniqueName()

        BrowserExtensionClipboard.copyDownloadURL(to: pasteboard)

        XCTAssertEqual(pasteboard.url, BetterLectioLinks.downloadURL)
        pasteboard.setItems([])
    }

    func testMessageSignatureUsesCanonicalDownloadURL() {
        XCTAssertTrue(MessageSignature.bbcode.contains(BetterLectioLinks.downloadURL.absoluteString))
    }
}
