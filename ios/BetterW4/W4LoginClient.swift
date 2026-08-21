//
//  W4LoginClient.swift
//  BetterW4
//
//  Native username / password (+ OTP) login against W4. No WebView, no ClientJS.
//  Ported from android/.../core/w4/auth/W4LoginClient.kt, W4Html.kt, YiiForm.kt, W4Form.kt.
//

import Foundation
import SwiftSoup

// MARK: - HTML classification (port of W4Html.kt)

/// Decode + classify W4 HTML. Session rules: README §4.5 / §5.6.
enum W4Html {
    /// UWC ids are `nc` + two-digit entry year + initials, e.g. `nc26abcd`.
    static let uwcIdPattern = "\\b(nc\\d{2}[a-z]+)\\b"

    static func isLoginHTML(_ html: String) -> Bool {
        html.range(of: "LoginForm[username]", options: .caseInsensitive) != nil
            || html.range(of: "Login Site", options: .caseInsensitive) != nil
    }

    /// Logged-in chrome. **Mid-login 2FA pages also render this**, so callers must check
    /// `W4Routes.isOTPURL` / the OTP form first or they will sail straight past the 2FA step.
    static func isAuthenticatedHTML(_ html: String) -> Bool {
        guard !isLoginHTML(html) else { return false }
        let hasWelcome = html.range(of: "Welcome,", options: .caseInsensitive) != nil
        let hasPanel = html.range(of: "id=\"user-panel\"", options: .caseInsensitive) != nil
            || html.range(of: "id='user-panel'", options: .caseInsensitive) != nil
        return hasWelcome || hasPanel
    }

    /// W4's own `init_ajax.js` rule: a 403 carrying this string is a dead session.
    static func isAjaxLoginRequired(_ body: String) -> Bool {
        body.range(of: "Login Required", options: .caseInsensitive) != nil
    }

    /// `Welcome, {display name}` inside `#user-panel` — identity comes from page chrome,
    /// there is no JSON profile endpoint.
    static func displayName(_ html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }

        if let right = try? doc.select("#user-panel .right").first(),
           let name = welcomeName(in: right.ownText()) {
            return name
        }
        guard let panel = try? doc.getElementById("user-panel") else { return nil }
        var text = panel.ownText()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = (try? panel.text()) ?? ""
        }
        guard let name = welcomeName(in: text) else { return nil }
        // The panel's flattened text runs "Welcome, Name Logout Profile Password".
        if let cut = name.range(of: "Logout") {
            let trimmed = String(name[name.startIndex..<cut.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return name
    }

    /// The signed-in student's own UWC id, from their public-profile link.
    ///
    /// `#hello` in the page chrome carries *this* student's link, so it is checked before the
    /// generic sweep — a birthdays list or a student table would otherwise hand back a
    /// classmate's id.
    static func uwcId(_ html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return firstUWCId(in: html) }

        let scoped = "#hello a[href*=uwc_id], #user-panel a[href*=uwc_id]"
        if let own = try? doc.select(scoped).first(),
           let href = try? own.attr("href"),
           let id = firstUWCId(in: href) {
            return id
        }

        let links = (try? doc.select("a[href*=people/students/student][href*=uwc_id]")) ?? Elements()
        let profileLink = links.array().first { element in
            ((try? element.text()) ?? "").lowercased().contains("profile")
        } ?? links.array().first

        if let profileLink, let href = try? profileLink.attr("href"), let id = firstUWCId(in: href) {
            return id
        }
        return firstUWCId(in: html)
    }

    static func contentInner(_ html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html),
              let element = try? doc.getElementById("content_inner") else { return nil }
        return try? element.html()
    }

    private static func welcomeName(in text: String) -> String? {
        guard let range = text.range(of: "Welcome,", options: .caseInsensitive) else { return nil }
        let tail = text[range.upperBound...]
        let stop = tail.firstIndex(where: { $0 == "|" || $0 == "<" }) ?? tail.endIndex
        let name = String(tail[tail.startIndex..<stop]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func firstUWCId(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: uwcIdPattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured]).lowercased()
    }
}

// MARK: - Yii form helper (port of YiiForm.kt)

/// Yii 1 forms are cookie-auth only — no CSRF token, no `__VIEWSTATE`. The only thing that
/// matters beyond the visible inputs is the clicked submit button (`yt0`, `yt1`, …).
enum YiiForm {
    struct Parsed {
        var action: String?
        var fields: [(name: String, value: String)]
        var submitButtons: [(name: String, value: String)]

        var fieldsDictionary: [String: String] {
            var result: [String: String] = [:]
            for field in fields { result[field.name] = field.value }
            return result
        }

        func submitValue(named name: String) -> String? {
            submitButtons.first { $0.name == name }?.value
        }
    }

    static func parse(_ html: String, formSelector: String? = nil) -> Parsed {
        guard let doc = try? SwiftSoup.parse(html) else {
            return Parsed(action: nil, fields: [], submitButtons: [])
        }
        let form: Element?
        if let formSelector, !formSelector.isEmpty {
            form = try? doc.select(formSelector).first()
        } else {
            form = try? doc.select("form").first()
        }
        guard let form else { return Parsed(action: nil, fields: [], submitButtons: []) }
        return parse(form: form)
    }

    static func parse(form: Element) -> Parsed {
        var fields: [(name: String, value: String)] = []
        var submits: [(name: String, value: String)] = []

        func put(_ name: String, _ value: String) {
            if let index = fields.firstIndex(where: { $0.name == name }) {
                fields[index] = (name, value)
            } else {
                fields.append((name, value))
            }
        }

        let elements = (try? form.select("input, select, textarea")) ?? Elements()
        for element in elements.array() {
            let name = ((try? element.attr("name")) ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            switch element.tagName().lowercased() {
            case "textarea":
                put(name, (try? element.text()) ?? "")
            case "select":
                let selected = (try? element.select("option[selected]").last())
                    ?? (try? element.select("option").first())
                if let option = selected {
                    let value = (try? option.attr("value")) ?? ""
                    put(name, value.isEmpty ? ((try? option.text()) ?? "") : value)
                } else {
                    put(name, "")
                }
            default:
                var type = ((try? element.attr("type")) ?? "").lowercased()
                if type.isEmpty { type = "text" }
                switch type {
                case "checkbox", "radio":
                    if element.hasAttr("checked") {
                        let value = (try? element.attr("value")) ?? ""
                        put(name, value.isEmpty ? "on" : value)
                    }
                case "submit", "button", "image":
                    let value = (try? element.attr("value")) ?? ""
                    if let index = submits.firstIndex(where: { $0.name == name }) {
                        submits[index] = (name, value)
                    } else {
                        submits.append((name, value))
                    }
                case "file":
                    break
                default:
                    put(name, (try? element.attr("value")) ?? "")
                }
            }
        }

        let rawAction = ((try? form.attr("action")) ?? "").trimmingCharacters(in: .whitespaces)
        return Parsed(
            action: rawAction.isEmpty ? nil : rawAction,
            fields: fields,
            submitButtons: submits
        )
    }

    /// Merge `extra` over the parsed fields and attach the Yii submit button.
    /// `submitName` defaults to `yt0`; the value comes from the form, then `submitValue`, then "".
    static func fieldsForSubmit(
        html: String,
        extra: [String: String] = [:],
        submitName: String = "yt0",
        submitValue: String? = nil,
        formSelector: String? = nil
    ) -> [String: String] {
        let parsed = parse(html, formSelector: formSelector)
        var merged = parsed.fieldsDictionary
        for (key, value) in extra { merged[key] = value }
        merged[submitName] = submitValue
            ?? parsed.submitValue(named: submitName)
            ?? parsed.submitButtons.first?.value
            ?? ""
        return merged
    }
}

// MARK: - Login / OTP form parsing (port of W4Form.kt)

enum W4Form {
    struct Parsed {
        var action: String?
        var fields: [String: String]
        var submitName: String?
        var submitValue: String?
        var otpFieldName: String?
        /// A "remember this device" checkbox, when the form has one.
        ///
        /// A browser posts a checkbox only when it is ticked, so an untouched box sends nothing
        /// and W4 forgets the device. We always want it on — it is the whole point of not having
        /// to sign in every launch — so it is discovered here and posted explicitly.
        var rememberField: RememberField?
    }

    /// The name and the value to post for a remember-me checkbox.
    struct RememberField: Equatable {
        let name: String
        /// The checkbox's own `value`, or `"1"` when it has none — that is what a browser sends.
        let value: String
    }

    /// `application/x-www-form-urlencoded` body. Keys are sorted so a request is reproducible
    /// in a bug report; W4 does not care about field order.
    static func encode(_ fields: [String: String]) -> Data {
        let body = fields.keys.sorted()
            .map { "\(escape($0))=\(escape(fields[$0] ?? ""))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    /// Browser-order form encoding that preserves repeated field names such as Yii's `items[]`.
    static func encode(_ fields: [(String, String)]) -> Data {
        Data(fields.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&").utf8)
    }

    static func parse(_ html: String, onKnownOTPPage: Bool = false) -> Parsed? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let candidate = (try? doc.select("form:has(input[name^=LoginForm])").first())
            ?? (try? doc.select("form[action*=otp], form[action*=verify2fa], form[action*=2fa]").first())
            ?? (try? doc.select("#content_inner form, #content form").first())
            ?? (try? doc.select("form").first())
        guard let form = candidate else { return nil }

        let yii = YiiForm.parse(form: form)
        let submit = yii.submitButtons.first
        let rawSubmitValue = submit?.value
        let submitValue: String? = (rawSubmitValue?.isEmpty == false) ? rawSubmitValue : nil
        return Parsed(
            action: yii.action,
            fields: yii.fieldsDictionary,
            submitName: submit?.name,
            submitValue: submitValue,
            otpFieldName: otpFieldName(in: form, onKnownOTPPage: onKnownOTPPage),
            rememberField: rememberField(in: form)
        )
    }

    private static let rememberNamePattern =
        "remember|rememberme|trust|trusted|keep.?me|keep.?signed|stay.?signed|stay.?logged|persist|autologin|husk"

    private static let rememberNameRegex = try? NSRegularExpression(
        pattern: rememberNamePattern,
        options: [.caseInsensitive]
    )

    private static func readsLikeRemember(_ text: String) -> Bool {
        guard let regex = rememberNameRegex, !text.isEmpty else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// Finds a "remember this device" checkbox.
    ///
    /// Matched on the field's `name`, its `id`, and the text of its `<label for=…>`, because a
    /// Yii form names things after its model (`LoginForm[rememberMe]`) while the human-readable
    /// wording lives in the label. Nothing about this control has been captured, so the match is
    /// deliberately broad — and it is confined to checkboxes, so a broad pattern cannot
    /// accidentally select a text field and post junk as a credential.
    static func rememberField(in form: Element) -> RememberField? {
        let checkboxes = (try? form.select("input[type=checkbox][name]")) ?? Elements()

        for input in checkboxes.array() {
            let name = ((try? input.attr("name")) ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let id = (try? input.attr("id")) ?? ""
            var labelText = ""
            if !id.isEmpty,
               let label = try? form.select("label[for=\(id)]").first(),
               let text = try? label.text() {
                labelText = text
            }

            guard readsLikeRemember(name) || readsLikeRemember(id) || readsLikeRemember(labelText) else {
                continue
            }

            let value = ((try? input.attr("value")) ?? "").trimmingCharacters(in: .whitespaces)
            return RememberField(name: name, value: value.isEmpty ? "1" : value)
        }
        return nil
    }

    /// W4's own rejection text, so the user reads the server's words and not ours.
    static func loginError(_ html: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        for selector in [".errorSummary li", ".errorSummary", ".flash-error", ".alert-error", ".errorMessage", "div.error"] {
            if let element = try? doc.select(selector).first(),
               let text = try? element.text() {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    /// `name:type, name:type, …` — for diagnosing an OTP page whose field we failed to find.
    /// Names only; never log values.
    static func inputInventory(_ html: String) -> String {
        guard let doc = try? SwiftSoup.parse(html),
              let inputs = try? doc.select("input[name]") else { return "" }
        return inputs.array().map { input in
            let name = (try? input.attr("name")) ?? ""
            var type = ((try? input.attr("type")) ?? "").lowercased()
            if type.isEmpty { type = "text" }
            return "\(name):\(type)"
        }.joined(separator: ", ")
    }

    /// Every form on the page and where it posts — pairs with `inputInventory` when the 2FA
    /// page turns out to carry more than one form.
    static func formActions(_ html: String) -> String {
        guard let doc = try? SwiftSoup.parse(html),
              let forms = try? doc.select("form") else { return "" }
        if forms.isEmpty() { return "(no forms)" }
        return forms.array().enumerated().map { index, form in
            let action = ((try? form.attr("action")) ?? "").trimmingCharacters(in: .whitespaces)
            let method = (((try? form.attr("method")) ?? "").uppercased()).isEmpty
                ? "GET" : ((try? form.attr("method")) ?? "").uppercased()
            return "[\(index)] \(method) \(action.isEmpty ? "(self)" : action)"
        }.joined(separator: " | ")
    }

    private static let otpNamePattern =
        "otp|totp|2fa|code|token|pin|sms|verify|verification|authenticator|one[-_]?time"

    private static let otpNameRegex = try? NSRegularExpression(
        pattern: otpNamePattern,
        options: [.caseInsensitive]
    )

    /// True when a field name reads like a one-time code.
    static func isOTPShapedName(_ name: String) -> Bool {
        guard let regex = otpNameRegex else { return false }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return regex.firstMatch(in: name, options: [], range: range) != nil
    }

    private static let skippedOTPInputTypes: Set<String> = [
        "hidden", "submit", "checkbox", "radio", "button", "file", "image"
    ]

    /// Credential fields — never a one-time code, whatever else the form carries.
    private static func isCredentialFieldName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("username") || lowered.contains("password")
            || lowered.hasSuffix("[user]") || lowered.hasSuffix("[pass]")
            || lowered.contains("deviceid")
    }

    /// The 2FA field names were never captured, so discover them instead of hardcoding.
    ///
    /// `onKnownOTPPage` matters. W4 is a Yii app and `site/verify2fa` sits in the same
    /// controller as `site/login`, so its code field may well be named `LoginForm[...]`.
    /// Excluding every `LoginForm` input is a sane guard when we are *guessing* whether an
    /// unknown page is a 2FA prompt, but on a page we already know is the 2FA prompt it throws
    /// away the very field we came for. There we exclude only username/password/deviceId.
    static func otpFieldName(in form: Element, onKnownOTPPage: Bool = false) -> String? {
        // The strict rule first — it is the one proven against the real W4 2FA page.
        if let hit = otpFieldName(in: form, includingLoginFormInputs: false) { return hit }
        // Only if that finds nothing, and only when we already know this IS the 2FA page, widen
        // to `LoginForm`-prefixed inputs. Yii reuses model names across a controller, so W4's
        // code field may legitimately be called LoginForm[…]; without this the login dead-ends.
        guard onKnownOTPPage else { return nil }
        return otpFieldName(in: form, includingLoginFormInputs: true)
    }

    private static func otpFieldName(in form: Element, includingLoginFormInputs: Bool) -> String? {
        let inputs = (try? form.select("input[name]")) ?? Elements()

        struct Candidate {
            let name: String
            let isOneTimeCodeAutocomplete: Bool
            let isNumericEntry: Bool
            let isShortField: Bool
        }

        let candidates: [Candidate] = inputs.array().compactMap { input in
            let name = ((try? input.attr("name")) ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            guard !isCredentialFieldName(name) else { return nil }
            if !includingLoginFormInputs, name.lowercased().hasPrefix("loginform") { return nil }
            var type = ((try? input.attr("type")) ?? "").lowercased()
            if type.isEmpty { type = "text" }
            guard !skippedOTPInputTypes.contains(type) else { return nil }

            let autocomplete = ((try? input.attr("autocomplete")) ?? "").lowercased()
            let inputMode = ((try? input.attr("inputmode")) ?? "").lowercased()
            let maxLength = Int(((try? input.attr("maxlength")) ?? "").trimmingCharacters(in: .whitespaces))
            return Candidate(
                name: name,
                isOneTimeCodeAutocomplete: autocomplete.contains("one-time-code"),
                isNumericEntry: type == "tel" || type == "number" || inputMode == "numeric",
                isShortField: (maxLength ?? 99) <= 10
            )
        }

        guard !candidates.isEmpty else { return nil }
        // Strongest signal first: the browser-standard hint, then a code-shaped name, then the
        // shape of the input itself (numeric keypad / short maxlength), then the sole candidate.
        if let hit = candidates.first(where: { $0.isOneTimeCodeAutocomplete }) { return hit.name }
        if let hit = candidates.first(where: { isOTPShapedName($0.name) }) { return hit.name }
        if let hit = candidates.first(where: { $0.isNumericEntry && $0.isShortField }) { return hit.name }
        if let hit = candidates.first(where: { $0.isShortField }) { return hit.name }
        return candidates.first?.name
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}

// MARK: - Login steps

/// Everything needed to answer the 2FA page, captured while we are still standing on it.
/// Losing this is how a client ends up "never captured the 2FA form".
struct W4OTPChallenge: Equatable {
    let credentials: W4Credentials
    let formAction: URL
    let hiddenFields: [String: String]
    let otpFieldName: String
    let submitName: String?
    let submitValue: String?
    /// A "remember this device" checkbox on the 2FA form, when it has one.
    ///
    /// This is the likeliest home for it: the login page has none (verified against the live
    /// page, which ships four inputs and no checkbox), and "trust this device" conventionally
    /// appears next to the code field — which is also what W4's `LoginForm[deviceId]` exists to
    /// support.
    let rememberField: W4Form.RememberField?

    init(
        credentials: W4Credentials,
        formAction: URL,
        hiddenFields: [String: String],
        otpFieldName: String,
        submitName: String?,
        submitValue: String?,
        rememberField: W4Form.RememberField? = nil
    ) {
        self.credentials = credentials
        self.formAction = formAction
        self.hiddenFields = hiddenFields
        self.otpFieldName = otpFieldName
        self.submitName = submitName
        self.submitValue = submitValue
        self.rememberField = rememberField
    }
}

enum W4LoginStep {
    case authenticated(W4Credentials, String, URL)
    case needsOTP(W4OTPChallenge)
    case failed(message: String?, invalidOTP: Bool)
}

// MARK: - Login client

/// Native W4 login (README §4.4). Three steps, no WebView:
/// GET `r=site/login` with an empty jar to get a `PHPSESSID`, POST the form W4 actually
/// rendered, then classify what came back.
enum W4LoginClient {
    private static let client = W4HTTPClient()

    static func submitPassword(username: String, password: String) async throws -> W4LoginStep {
        let loginURL = W4Routes.url(W4Routes.R.login)

        // Empty jar on purpose: Yii sessions are sticky to the id it hands out here, and a
        // stale id from a previous account would be sent straight back at it.
        let opened = try await client.performRequest(
            url: loginURL,
            method: "GET",
            credentials: .empty,
            studentId: nil,
            contextForLogging: W4Routes.R.login,
            priority: .important,
            allowLoginPage: true
        )
        let openedCredentials = opened.updatedCredentials ?? .empty
        let loginHTML = client.decodeHTML(from: opened.data)

        // Parse the real form rather than hardcoding: whatever hidden inputs W4 ships ride
        // along, and the submit button keeps whatever name/value it actually has.
        let parsed = W4Form.parse(loginHTML)
        var submitName = "yt0"
        var submitValue = "Login"
        if let parsed {
            if let name = parsed.submitName, !name.isEmpty { submitName = name }
            if let value = parsed.submitValue, !value.isEmpty { submitValue = value }
        }

        var extra: [String: String] = [
            "LoginForm[username]": W4Username.normalize(username),
            "LoginForm[password]": password,
            "LoginForm[deviceId]": W4DeviceID.current()
        ]

        // Tick "remember this device" if the form offers it. A browser posts a checkbox only when
        // it is ticked, so leaving it out is what makes W4 forget the device and challenge every
        // launch. Paired with the stable per-install deviceId, this is what keeps a student
        // signed in.
        if let remember = parsed?.rememberField {
            extra[remember.name] = remember.value
            print("🔒 W4 login: remembering this device (\(remember.name))")
        }

        let fields = YiiForm.fieldsForSubmit(
            html: loginHTML,
            extra: extra,
            submitName: submitName,
            submitValue: submitValue,
            formSelector: "form:has(input[name^=LoginForm])"
        )

        let posted = try await client.performRequest(
            url: loginURL,
            method: "POST",
            body: W4Form.encode(fields),
            headers: [
                "Content-Type": W4UserAgent.formURLEncoded,
                "Referer": loginURL.absoluteString
            ],
            credentials: openedCredentials,
            studentId: nil,
            contextForLogging: W4Routes.R.login,
            priority: .important,
            allowLoginPage: true
        )

        return classify(
            credentials: posted.updatedCredentials ?? openedCredentials,
            html: client.decodeHTML(from: posted.data),
            finalURL: posted.finalURL,
            expectingOTP: false
        )
    }

    static func submitOTP(_ challenge: W4OTPChallenge, code: String) async throws -> W4LoginStep {
        var fields = challenge.hiddenFields
        fields[challenge.otpFieldName] = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let submitName = challenge.submitName ?? "yt0"
        if fields[submitName] == nil {
            fields[submitName] = challenge.submitValue ?? "Verify"
        }

        // "Remember this device" lives on the 2FA form far more often than on the login form, and
        // this is the step that decides whether W4 challenges the next launch. Post it ticked.
        if let remember = challenge.rememberField {
            fields[remember.name] = remember.value
            print("🔒 W4 2FA: remembering this device (\(remember.name))")
        }

        let posted = try await client.performRequest(
            url: challenge.formAction,
            method: "POST",
            body: W4Form.encode(fields),
            headers: [
                "Content-Type": W4UserAgent.formURLEncoded,
                "Referer": challenge.formAction.absoluteString
            ],
            credentials: challenge.credentials,
            studentId: nil,
            contextForLogging: W4Routes.R.verify2FA,
            priority: .important,
            allowLoginPage: true
        )

        return classify(
            credentials: posted.updatedCredentials ?? challenge.credentials,
            html: client.decodeHTML(from: posted.data),
            finalURL: posted.finalURL,
            expectingOTP: true
        )
    }

    // MARK: - Classification

    private static func classify(
        credentials: W4Credentials,
        html: String,
        finalURL: URL,
        expectingOTP: Bool
    ) -> W4LoginStep {
        #if DEBUG
        print("🔑 W4 login classify route=\(W4Routes.route(of: finalURL) ?? "?") "
              + "otpURL=\(W4Routes.isOTPURL(finalURL)) "
              + "authHTML=\(W4Html.isAuthenticatedHTML(html)) "
              + "loginHTML=\(W4Html.isLoginHTML(html))")
        #endif

        guard !credentials.isEmpty else {
            print("⚠️ W4 login: no PHPSESSID after response")
            return .failed(message: nil, invalidOTP: expectingOTP)
        }

        // 2FA pages still ship logged-in chrome ("Welcome," / #user-panel), so a naive
        // isAuthenticatedHTML check sails straight past them. OTP is checked FIRST.
        let isKnownOTPRoute = W4Routes.isOTPURL(finalURL)
        if isKnownOTPRoute || looksLikeOTP(html: html, finalURL: finalURL) {
            // The 2FA form has never been captured, so log exactly what W4 rendered. This is the
            // one line to read when 2FA misbehaves — it names every field the page offers.
            print("""
                🔎 W4 2FA DIAGNOSTIC
                   route:  \(W4Routes.route(of: finalURL) ?? "?")
                   known:  \(isKnownOTPRoute)
                   inputs: \(W4Form.inputInventory(html))
                   forms:  \(W4Form.formActions(html))
                """)
            guard let form = W4Form.parse(html, onKnownOTPPage: isKnownOTPRoute),
                  let otpField = form.otpFieldName, !otpField.isEmpty else {
                print("⚠️ W4 OTP page but no code field found — see the diagnostic above")
                return .failed(
                    message: W4Form.loginError(html)
                        ?? "Could not find the verification-code field on W4's 2FA page.",
                    invalidOTP: expectingOTP
                )
            }
            var hidden = form.fields
            hidden.removeValue(forKey: otpField)
            let action = resolveAction(form.action, fallback: finalURL)
            print("🔐 W4 login: OTP required at r=\(W4Routes.route(of: finalURL) ?? "?") field=\(otpField)")
            return .needsOTP(
                W4OTPChallenge(
                    credentials: credentials,
                    formAction: action,
                    hiddenFields: hidden,
                    otpFieldName: otpField,
                    submitName: form.submitName,
                    submitValue: form.submitValue,
                    rememberField: form.rememberField
                )
            )
        }

        if W4Html.isLoginHTML(html) || W4Routes.isLoginURL(finalURL) {
            let message = W4Form.loginError(html)
            print("⚠️ W4 login rejected: \(message ?? "(no server message)")")
            return .failed(message: message, invalidOTP: expectingOTP)
        }

        if W4Html.isAuthenticatedHTML(html) || W4Routes.isHomeURL(finalURL) {
            return .authenticated(credentials, html, finalURL)
        }

        print("⚠️ W4 login: unexpected page at r=\(W4Routes.route(of: finalURL) ?? "?")")
        return .failed(message: W4Form.loginError(html), invalidOTP: expectingOTP)
    }

    /// W4 can serve the 2FA form from a route we do not recognise; a form carrying a
    /// code-shaped field and no `LoginForm` inputs is the tell.
    ///
    /// The name must actually *read* like a one-time code here. `W4Form.otpFieldName` falls
    /// back to "the only remaining text input", which is right once we know we are on a 2FA
    /// page but would read an ordinary page — a search box, the campus "other location"
    /// field — as a 2FA prompt and strand the user on an OTP screen forever.
    private static func looksLikeOTP(html: String, finalURL: URL) -> Bool {
        if W4Routes.isOTPURL(finalURL) { return true }
        if W4Routes.isHomeURL(finalURL) { return false }
        if W4Html.isLoginHTML(html) { return false }
        guard let form = W4Form.parse(html), let name = form.otpFieldName else { return false }
        return W4Form.isOTPShapedName(name)
    }

    /// Yii usually renders `action="index.php?r=…"`, which is relative to the page we are on.
    /// An absent action means "post back here".
    private static func resolveAction(_ action: String?, fallback: URL) -> URL {
        guard let action else { return fallback }
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if let absolute = URL(string: trimmed), absolute.scheme != nil, absolute.host != nil {
            return absolute
        }
        return URL(string: trimmed, relativeTo: fallback)?.absoluteURL ?? fallback
    }
}
