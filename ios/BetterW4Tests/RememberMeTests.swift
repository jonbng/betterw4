//
//  RememberMeTests.swift
//  BetterW4Tests
//
//  "Remember this device" — the difference between signing in once and signing in every launch.
//
//  EVIDENCE, stated plainly because it shapes every test here:
//
//    * The live login page at `index.php?r=site/login` was fetched on 16 Aug 2026 and contains
//      FOUR inputs — LoginForm[deviceId] (hidden), LoginForm[username], LoginForm[password], and
//      the yt0 submit — with NO checkbox and no "remember" text anywhere. That is [V] verified.
//    * A remember/trust control therefore lives on the 2FA page (`site/verify2fa`), which cannot
//      be fetched without being mid-login. Its markup is [U] UNCAPTURED.
//
//  So discovery is deliberately broad (name, id, or label text) and confined to checkboxes, and
//  these tests verify OUR logic against markup we invented — not W4's actual form.
//

import XCTest
@testable import BetterW4

final class RememberMeTests: XCTestCase {

    // MARK: - [V] The real login page

    /// The captured login form has no checkbox, so nothing must be invented for it.
    func testRealLoginFormHasNoRememberField() throws {
        let html = """
        <form action="/index.php?r=site/login" method="post">
          <input name="LoginForm[deviceId]" id="LoginForm_deviceId" type="hidden" />
          <label for="LoginForm_username">Username</label>
          <input class="text_input" name="LoginForm[username]" id="LoginForm_username" type="text" maxlength="16" />
          <label for="LoginForm_password">Password</label>
          <input class="text_input" name="LoginForm[password]" id="LoginForm_password" type="password" />
          <input id="submit_button" type="submit" name="yt0" value="Login" />
        </form>
        """

        let parsed = try XCTUnwrap(W4Form.parse(html))
        XCTAssertNil(parsed.rememberField, "the captured login form has no checkbox to tick")
    }

    // MARK: - [U] Discovery, against invented markup

    /// Yii names fields after its model, so the human wording is only in the label.
    func testDiscoveryMatchesOnFieldName() throws {
        let parsed = try XCTUnwrap(W4Form.parse(Self.form(
            checkbox: #"<input type="checkbox" name="LoginForm[rememberMe]" id="LoginForm_rememberMe" value="1" />"#
        )))
        XCTAssertEqual(parsed.rememberField, W4Form.RememberField(name: "LoginForm[rememberMe]", value: "1"))
    }

    func testDiscoveryMatchesOnLabelTextWhenTheNameIsOpaque() throws {
        let parsed = try XCTUnwrap(W4Form.parse(Self.form(
            checkbox: #"<input type="checkbox" name="VerifyForm[t]" id="trust_box" value="yes" />"#
                + #"<label for="trust_box">Trust this device for 30 days</label>"#
        )))
        XCTAssertEqual(parsed.rememberField, W4Form.RememberField(name: "VerifyForm[t]", value: "yes"))
    }

    /// A browser posts "on" for a checkbox with no value attribute.
    func testCheckboxWithoutAValueDefaultsToOne() throws {
        let parsed = try XCTUnwrap(W4Form.parse(Self.form(
            checkbox: #"<input type="checkbox" name="rememberme" />"#
        )))
        XCTAssertEqual(parsed.rememberField?.value, "1")
    }

    /// The pattern is broad, so the checkbox-only restriction is what stops it doing damage:
    /// a text field must never be selected and posted as if it were a consent flag.
    func testOnlyCheckboxesAreEverSelected() throws {
        let parsed = try XCTUnwrap(W4Form.parse(Self.form(
            checkbox: #"<input type="text" name="rememberMyName" value="Alex" />"#
        )))
        XCTAssertNil(parsed.rememberField, "a text input must never be treated as a remember flag")
    }

    func testUnrelatedCheckboxesAreNotMistakenForRemember() throws {
        let parsed = try XCTUnwrap(W4Form.parse(Self.form(
            checkbox: #"<input type="checkbox" name="MailerForm[sendCC]" id="cc" />"#
                + #"<label for="cc">Send me a copy</label>"#
        )))
        XCTAssertNil(parsed.rememberField)
    }

    // MARK: - The cookie jar

    /// The point of ticking the box: W4 issues a cookie, and the app must keep it.
    func testJarKeepsANonSessionCookieAndSendsItBack() throws {
        let credentials = W4Credentials(sessionId: "abc")
        let response = try Self.response(setCookie: [
            "PHPSESSID=abc; path=/; secure",
            "w4_remember=trust-token-xyz; path=/; secure; Max-Age=2592000"
        ])

        let updated = try XCTUnwrap(
            CookieManager.shared.updateCredentials(from: response, currentCredentials: credentials),
            "a new remember cookie is a change and must be stored"
        )
        XCTAssertEqual(updated.additionalCookies["w4_remember"], "trust-token-xyz")

        let header = CookieManager.shared.cookieHeader(from: updated)
        XCTAssertTrue(header.contains("PHPSESSID=abc"))
        XCTAssertTrue(header.contains("w4_remember=trust-token-xyz"), "the cookie must go back out")
    }

    /// An empty PHPSESSID means "nothing to say on this hop" and must not wipe a live session,
    /// but an empty *remember* cookie is how a server revokes the token — honour that.
    func testBlankingRevokesARememberCookieButNeverTheSession() throws {
        let credentials = W4Credentials(
            sessionId: "live-session",
            additionalCookies: ["w4_remember": "trust-token-xyz"]
        )
        let response = try Self.response(setCookie: [
            "PHPSESSID=; path=/",
            "w4_remember=; path=/; Max-Age=0"
        ])

        let updated = try XCTUnwrap(
            CookieManager.shared.updateCredentials(from: response, currentCredentials: credentials)
        )
        XCTAssertEqual(updated.sessionId, "live-session", "an empty PHPSESSID must be ignored")
        XCTAssertNil(updated.additionalCookies["w4_remember"], "an emptied remember cookie is revoked")
    }

    func testLectioCookieNamesAreRefused() {
        let credentials = W4Credentials(
            sessionId: "abc",
            additionalCookies: ["autologinkeyV2": "nope", "ASP.NET_SessionId": "nope"] // legacy-name: the negative test for refusedNames
        )
        XCTAssertTrue(credentials.additionalCookies.isEmpty, "Lectio cookies can only come from a stale blob")
        XCTAssertEqual(CookieManager.shared.cookieHeader(from: credentials), "PHPSESSID=abc")
    }

    /// A Keychain record written before `additionalCookies` existed must still decode — throwing
    /// here would sign the student out on upgrade.
    func testCredentialsStoredBeforeThisFeatureStillDecode() throws {
        let legacy = Data(#"{"sessionId":"stored-earlier"}"#.utf8)
        let decoded = try JSONDecoder().decode(W4Credentials.self, from: legacy)

        XCTAssertEqual(decoded.sessionId, "stored-earlier")
        XCTAssertTrue(decoded.additionalCookies.isEmpty)
    }

    func testCookieHeaderIsEmptyWithNoSession() {
        XCTAssertEqual(CookieManager.shared.cookieHeader(from: .empty), "")
    }

    func testFormEncodingPreservesRepeatedCheckboxNames() {
        let data = W4Form.encode([
            ("StudentAbsenceForm[absences][]", "CLASS_A_08:15"),
            ("StudentAbsenceForm[absences][]", "CLASS_B_10:10")
        ])
        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            "StudentAbsenceForm%5Babsences%5D%5B%5D=CLASS_A_08%3A15&" +
                "StudentAbsenceForm%5Babsences%5D%5B%5D=CLASS_B_10%3A10"
        )
    }

    // MARK: - Helpers

    private static func form(checkbox: String) -> String {
        """
        <form action="/index.php?r=site/verify2fa" method="post">
          <input type="hidden" name="YII_CSRF_TOKEN" value="x" />
          <label for="code">Verification code</label>
          <input type="text" name="VerifyForm[code]" id="code" maxlength="6" />
          \(checkbox)
          <input type="submit" name="yt0" value="Verify" />
        </form>
        """
    }

    private static func response(setCookie: [String]) throws -> HTTPURLResponse {
        // `HTTPURLResponse` collapses repeated headers, so multiple Set-Cookie values are joined
        // with ", " exactly as URLSession surfaces them.
        let url = try XCTUnwrap(URL(string: "https://w4.uwcrcn.no/index.php?r=site/index"))
        return try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Set-Cookie": setCookie.joined(separator: ", ")]
        ))
    }
}
