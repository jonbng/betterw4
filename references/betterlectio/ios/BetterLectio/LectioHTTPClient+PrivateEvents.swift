//
//  LectioHTTPClient+PrivateEvents.swift
//  BetterLectio
//

import Foundation

extension LectioHTTPClient {

    /// Creates a private calendar event ("privat aftale") for the logged-in user.
    /// Mirrors lectioDartWrapper's `PrivateCalendarEventController.create`: GET `privat_aftale.aspx`
    /// to capture the ASP.NET form state, then POST it back with the save button as `__EVENTTARGET`.
    func createPrivateEvent(
        credentials: LectioCredentials,
        studentId: String,
        schoolId: Int,
        title: String,
        start: Date,
        end: Date,
        note: String,
        priority: FetchPriority = .important
    ) async throws {
        let urlString = "https://www.lectio.dk/lectio/\(schoolId)/privat_aftale.aspx"
        guard let url = URL(string: urlString) else {
            throw LectioError.invalidURL
        }

        // 1. GET the page so we can extract VIEWSTATE / EVENTVALIDATION etc.
        let (pageData, _, _) = try await performRequest(
            url: url,
            credentials: credentials,
            studentId: studentId,
            contextForLogging: "GET privat_aftale.aspx",
            priority: priority
        )
        let pageHtml = decodeHTML(from: pageData)
        let formFields = try BaseParser.parseAllFormFields(from: pageHtml)

        // 2. Build the POST body with all hidden fields, plus the user's input.
        let saveTarget = "m$Content$savebuttonsCtrl$svbtn"
        let overrides: [String: String] = [
            "m$Content$titelTextBox$tb": title,
            "m$Content$startdateCtrl$_date$tb": Self.privateEventDateFormatter.string(from: start),
            "m$Content$startdateCtrl$startdateCtrl_time$tb": Self.privateEventTimeFormatter.string(from: start),
            "m$Content$enddateCtrl$_date$tb": Self.privateEventDateFormatter.string(from: end),
            "m$Content$enddateCtrl$enddateCtrl_time$tb": Self.privateEventTimeFormatter.string(from: end),
            "m$Content$commentTextBox$tb": note
        ]

        let skipFieldNames: Set<String> = Set(["__EVENTTARGET", "__EVENTARGUMENT"]).union(overrides.keys)

        var formParts: [String] = []
        formParts.append("__EVENTTARGET=\(formURLEncode(saveTarget))")
        formParts.append("__EVENTARGUMENT=")

        for field in formFields {
            if skipFieldNames.contains(field.name) { continue }
            formParts.append("\(formURLEncode(field.name))=\(formURLEncode(field.value))")
        }

        for (key, value) in overrides {
            formParts.append("\(formURLEncode(key))=\(formURLEncode(value))")
        }

        let bodyString = formParts.joined(separator: "&")
        let headers = [
            "Referer": urlString,
            "Origin": "https://www.lectio.dk",
            "Content-Type": "application/x-www-form-urlencoded"
        ]

        let (data, _, _) = try await performRequest(
            url: url,
            method: "POST",
            body: bodyString.data(using: .utf8),
            headers: headers,
            credentials: credentials,
            studentId: studentId,
            contextForLogging: "POST create private event",
            priority: priority
        )

        // Lectio re-renders the form with field-level errors instead of returning a non-200, so
        // we have to detect failure by inspecting the response. Success redirects back to the
        // calendar overview (no `titelTextBox` on that page); the error page still has it.
        let responseHtml = decodeHTML(from: data)
        if responseHtml.contains("id=\"m_Content_titelTextBox_tb\"") &&
           (responseHtml.contains("field-validation-error") || responseHtml.contains("class=\"error\"")) {
            throw LectioError.parsingError("Lectio afviste den private aftale")
        }
    }

    // Lectio expects Danish-style date formatting; lock the locale so user device settings can't shift it.
    private static let privateEventDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        df.dateFormat = "dd/MM-yyyy"
        return df
    }()

    private static let privateEventTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "Europe/Copenhagen")
        df.dateFormat = "HH:mm"
        return df
    }()
}
