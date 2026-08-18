//
//  W4Routes.swift
//  BetterW4
//
//  Yii 1 URL builder + session URL classification for https://w4.uwcrcn.no/.
//  Ported from android/.../core/w4/W4Urls.kt and W4Session.kt.
//

import Foundation

/// Builds and classifies `https://w4.uwcrcn.no/index.php?r={route}&k=v` URLs.
///
/// Extra params are **sibling** query keys, never part of `r`
/// (`people/students/student&uwc_id=nc26abcd` → `r=people/students/student&uwc_id=nc26abcd`).
enum W4Routes {
    static let host = "w4.uwcrcn.no"
    static let origin = "https://w4.uwcrcn.no"
    static let index = "index.php"

    static let originURL = URL(string: origin)!

    /// True for the single W4 host (and any subdomain of it). W4 is one school, one host.
    static func isW4Host(_ host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        return host == Self.host || host.hasSuffix(".\(Self.host)")
    }

    // MARK: - Building

    /// `W4Routes.url("academics/deadlines", ["month": "8"])`
    /// → `https://w4.uwcrcn.no/index.php?r=academics/deadlines&month=8`
    ///
    /// `/` stays unencoded inside `r` so the URLs match W4's own links.
    /// A route may carry inline siblings (`"people/students/student&uwc_id=nc26abcd"`);
    /// those are split out and appended as real query keys.
    static func url(_ route: String, _ query: [String: String] = [:]) -> URL {
        let split = splitRouteAndQuery(route)

        var orderedKeys: [String] = []
        var values: [String: String] = [:]
        for pair in split.query where pair.name != "r" {
            if values[pair.name] == nil { orderedKeys.append(pair.name) }
            values[pair.name] = pair.value
        }
        for key in query.keys.sorted() where key != "r" {
            if values[key] == nil { orderedKeys.append(key) }
            values[key] = query[key]
        }

        var string = "\(origin)/\(index)?r=\(encodeRoute(split.route))"
        for key in orderedKeys {
            string += "&\(escape(key))=\(escape(values[key] ?? ""))"
        }
        return URL(string: string) ?? originURL
    }

    /// Accepts an absolute URL, a path (`/index.php?r=…`), `index.php?r=…`,
    /// or a bare Yii route (`academics/timetable/mytimetable`, possibly with inline siblings).
    static func resolve(_ pathOrURL: String, query: [String: String] = [:]) -> URL {
        let trimmed = pathOrURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return url("", query) }

        var base: URL?
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            base = URL(string: trimmed)
        } else if trimmed.hasPrefix("/") {
            base = URL(string: origin + trimmed)
        } else if trimmed.hasPrefix(index) || trimmed.hasPrefix("?r=") {
            base = URL(string: "\(origin)/\(trimmed)")
        }

        guard let resolved = base else { return url(trimmed, query) }
        guard !query.isEmpty,
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else {
            return resolved
        }
        var items = components.queryItems ?? []
        for key in query.keys.sorted() where key != "r" {
            items.append(URLQueryItem(name: key, value: query[key]))
        }
        components.queryItems = items
        return components.url ?? resolved
    }

    /// Public-profile URL for a UWC id.
    static func student(_ uwcId: String) -> URL {
        url(R.studentProfile, ["uwc_id": uwcId])
    }

    // MARK: - Reading

    /// The decoded `r` value of a W4 URL (`site%2Flogin` → `site/login`), or nil.
    static func route(of url: URL) -> String? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let item = components.queryItems?.first(where: { $0.name.lowercased() == "r" }),
           let value = item.value {
            return normalizeRoute(value)
        }
        return route(ofURLString: url.absoluteString)
    }

    /// Same as `route(of:)` but tolerant of strings that are not valid `URL`s.
    static func route(ofURLString string: String) -> String? {
        let decoded = string.removingPercentEncoding ?? string
        guard let match = firstRouteQueryValue(in: decoded) else { return nil }
        return normalizeRoute(match)
    }

    // MARK: - Classification (README §4.5 / §5.4)

    /// A 302 whose target is `r=site/login` is the single most reliable session-death signal.
    static func isLoginURL(_ url: URL) -> Bool {
        route(of: url)?.lowercased() == R.login
    }

    static func isLoginURL(string: String) -> Bool {
        route(ofURLString: string)?.lowercased() == R.login
    }

    /// The mid-login 2FA page. `site/verify2fa` is the captured route; `site/otp` exists too.
    static func isOTPURL(_ url: URL) -> Bool {
        isOTPRoute(route(of: url))
    }

    static func isOTPURL(string: String) -> Bool {
        isOTPRoute(route(ofURLString: string))
    }

    /// Home — `r=site/index`, or the bare `site` module.
    static func isHomeURL(_ url: URL) -> Bool {
        guard let route = route(of: url)?.lowercased() else { return false }
        return route == R.home || route == "site"
    }

    static func isHomeURL(string: String) -> Bool {
        guard let route = route(ofURLString: string)?.lowercased() else { return false }
        return route == R.home || route == "site"
    }

    /// Follow this redirect; it is login-in-progress, not a dead session.
    static func isAuthProgressURL(_ url: URL) -> Bool {
        isOTPURL(url) || isHomeURL(url)
    }

    private static func isOTPRoute(_ raw: String?) -> Bool {
        guard let route = raw?.lowercased() else { return false }
        if route == R.otp || route == R.verify2FA { return true }
        guard route.hasPrefix("site/") else { return false }
        return route.contains("otp") || route.contains("2fa") || route.contains("verify")
    }

    // MARK: - Routes

    /// Yii `r=` values. Captured 14 Aug 2026 from the student navigation (README §6).
    enum R {
        // site
        static let home = "site/index"
        static let login = "site/login"
        static let logout = "site/logout"
        /// Research guessed this; unauthenticated GETs 302 to login.
        static let otp = "site/otp"
        /// Live mid-login 2FA page after the password POST.
        static let verify2FA = "site/verify2fa"
        static let forgotPassword = "site/forgotpass"
        static let profile = "site/profile"
        static let password = "site/password"
        static let rss = "site/rss"
        static let setStatus = "site/setstatus"
        static let releaseNotes = "site/relnotes"

        // academics
        static let assessments = "academics/deadlines"
        static let myTimetable = "academics/timetable/mytimetable"
        static let myTimetableIndex = "academics/timetable/mytimetable/index"
        static let myClasses = "academics/classes/myclasses"
        static let allClasses = "academics/classes/allclasses"
        static let allAssessments = "academics/classes/assessments/all"
        static let grades = "academics/grades/grades"
        static let satACT = "academics/grades/grades/sat"
        static let transcripts = "academics/transcripts/transcripts"
        static let recordsOfProgress = "academics/rop"
        static let extendedEssay = "academics/ee"
        static let testimonial = "academics/testimonial"
        static let feeds = "academics/feeds"
        static let subjectPages = "academics/subjects/pages"
        static let trips = "academics/trips"
        static let travel = "academics/travel/travel.list"
        static let resources = "academics/resources/resources"
        static let roomTimetable = "academics/timetable/room"

        // extra academics
        static let eaTimetable = "extraacademics/timetable/mytimetable"
        static let eaTimetableIndex = "extraacademics/timetable/mytimetable/index"
        static let eaActivities = "extraacademics/activities/myactivities"
        static let eaDiary = "extraacademics/activities/myactivities/diary"
        static let eaPortfolio = "extraacademics/activities/myportfolio"
        static let eaInterviews = "extraacademics/activities/interviews"
        static let eaSafetyNet = "extraacademics/safetynet/mysafetynet"
        static let eaAll = "extraacademics/activities/ea"
        static let eaDocuments = "extraacademics/documents"

        // people
        static let absences = "people/students/absences"
        static let absencesRegister = "people/students/absences/register"
        static let eaAbsences = "people/students/eaabsences"
        static let studentProfile = "people/students/student"
        static let studentsAll = "people/students/all"
        static let studentsFirstYear = "people/students/firstyear"
        static let studentsSecondYear = "people/students/secondyear"
        static let staff = "people/students/staff"
        static let staffCurrent = "people/staff/current"
        static let staffProfile = "people/staff/staff"
        static let letterOfAttendance = "people/students/letter/attendance"
        static let birthdays = "people/birthdays"

        // mailer
        static let mailerInbox = "mailer/inbox"
        static let mailerArchive = "mailer/archive"
        static let mailerSent = "mailer/archive"
        static let mailerView = "mailer/view"
        static let mailerSend = "mailer/send"
        static let mailerExtra = "mailer/extra"

        // documents / admissions
        static let documents = "documents/index"
        static let admissionsApplicants = "admissions/browse/admissions"

        // notifications (jQuery AJAX, README §5.3)
        static let notificationsRead = "notifications/read"
        static let notificationsReadGroup = "notifications/readgroup"
        static let notificationsReadAll = "notifications/readall"
        static let notificationsReadAllEmails = "notifications/readallemails"
        static let notificationsClear = "notifications/clear"
        static let notificationsClearGroup = "notifications/cleargroup"
        static let notificationsClearAll = "notifications/clearall"
        static let notificationsRefresh = "notifications/refresh"
    }

    // MARK: - Internals

    /// `people/students/student&uwc_id=nc26abcd` → route + sibling keys.
    /// Extra params must **not** be stuffed inside `r`.
    static func splitRouteAndQuery(
        _ raw: String
    ) -> (route: String, query: [(name: String, value: String)]) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix("/") { trimmed.removeFirst() }
        guard let ampIndex = trimmed.firstIndex(of: "&") else { return (trimmed, []) }

        let routeName = String(trimmed[trimmed.startIndex..<ampIndex])
        let rest = String(trimmed[trimmed.index(after: ampIndex)...])
        var pairs: [(name: String, value: String)] = []
        for part in rest.split(separator: "&", omittingEmptySubsequences: true) {
            let piece = String(part)
            let name: String
            let value: String
            if let eq = piece.firstIndex(of: "=") {
                name = decode(String(piece[piece.startIndex..<eq]))
                value = decode(String(piece[piece.index(after: eq)...]))
            } else {
                name = decode(piece)
                value = ""
            }
            if name.isEmpty || name == "r" { continue }
            pairs.append((name, value))
        }
        return (routeName, pairs)
    }

    private static func normalizeRoute(_ raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value.isEmpty ? nil : value
    }

    /// First `?r=`/`&r=` value in a (already percent-decoded) string.
    private static func firstRouteQueryValue(in string: String) -> String? {
        var searchStart = string.startIndex
        while searchStart < string.endIndex {
            guard let rIndex = string.range(of: "r=", range: searchStart..<string.endIndex) else {
                return nil
            }
            let before = rIndex.lowerBound
            if before > string.startIndex {
                let previous = string[string.index(before: before)]
                if previous == "?" || previous == "&" {
                    let tail = string[rIndex.upperBound...]
                    if let end = tail.firstIndex(where: { $0 == "&" || $0 == "#" }) {
                        return String(tail[tail.startIndex..<end])
                    }
                    return String(tail)
                }
            }
            searchStart = rIndex.upperBound
        }
        return nil
    }

    /// Percent-encodes each segment but keeps `/` literal, so `r=site/login`
    /// matches the links W4 itself renders.
    private static func encodeRoute(_ route: String) -> String {
        route
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { escape(String($0)) }
            .joined(separator: "/")
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static func decode(_ value: String) -> String {
        value.removingPercentEncoding ?? value
    }
}
