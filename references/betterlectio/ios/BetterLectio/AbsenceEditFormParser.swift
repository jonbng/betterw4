import Foundation
import SwiftSoup

struct AbsenceEditForm {
    let fields: [(name: String, value: String)]
    let reasonFieldName: String
    let noteFieldName: String
    let saveTarget: String
    let reasons: [AbsenceReasonOption]
    let selectedReasonValue: String?
    let note: String
}

enum AbsenceEditFormParser {
    static func parse(_ html: String) throws -> AbsenceEditForm {
        let doc = try SwiftSoup.parse(html)
        guard let reasonSelect = try doc.select("select[name*=StudentReasonDD]").first() else {
            throw LectioError.parsingError("Fraværsårsagerne blev ikke fundet")
        }

        let reasonFieldName = try reasonSelect.attr("name")
        let options = try reasonSelect.select("option").compactMap { option -> AbsenceReasonOption? in
            let value = try option.attr("value").trimmingCharacters(in: .whitespacesAndNewlines)
            let label = try option.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let isPrompt = label.lowercased(with: Locale(identifier: "da_DK")).hasPrefix("vælg")
            guard !value.isEmpty, !label.isEmpty, !isPrompt,
                  (try option.hasAttr("disabled")) == false else { return nil }
            return AbsenceReasonOption(value: value, label: label)
        }
        guard !options.isEmpty else {
            throw LectioError.parsingError("Lectio returnerede ingen gyldige fraværsårsager")
        }

        let selectedReasonValue = try reasonSelect.select("option[selected]").first()?.attr("value").nilIfEmpty
        let noteElement = try doc.select(
            "textarea[name*=cancelStudentNote], input[name*=cancelStudentNote]"
        ).first()
        let noteFieldName = try noteElement?.attr("name").nilIfEmpty
            ?? "s$m$Content$Content$cancelStudentNote$tb"
        let note: String
        if let noteElement {
            if noteElement.tagName() == "textarea" {
                note = try noteElement.text()
            } else {
                note = try noteElement.attr("value")
            }
        } else {
            note = ""
        }

        let saveElement = try doc.select(
            "input[name*=savecancelapplyBtn][name$=svbtn], button[name*=savecancelapplyBtn][name$=svbtn], input[name$=savebtn]"
        ).first()
        let saveTarget = try saveElement?.attr("name").nilIfEmpty
            ?? "s$m$Content$Content$savecancelapplyBtn$svbtn"

        return AbsenceEditForm(
            fields: try BaseParser.parseAllFormFields(from: html),
            reasonFieldName: reasonFieldName,
            noteFieldName: noteFieldName,
            saveTarget: saveTarget,
            reasons: options,
            selectedReasonValue: selectedReasonValue,
            note: note
        )
    }

    static func postBody(form: AbsenceEditForm, reasonValue: String, note: String) -> Data? {
        let overrides = [form.reasonFieldName: reasonValue, form.noteFieldName: note]
        let skipped = Set(["__EVENTTARGET", "__EVENTARGUMENT"]).union(overrides.keys)
        var parts = [
            "__EVENTTARGET=\(urlEncode(form.saveTarget))",
            "__EVENTARGUMENT="
        ]
        parts += form.fields.compactMap { field in
            guard !skipped.contains(field.name) else { return nil }
            return "\(urlEncode(field.name))=\(urlEncode(field.value))"
        }
        parts += overrides.map { "\(urlEncode($0.key))=\(urlEncode($0.value))" }
        return parts.joined(separator: "&").data(using: .utf8)
    }

    static func validationMessage(in html: String) throws -> String? {
        let doc = try SwiftSoup.parse(html)
        let selectors = ".field-validation-error, .validation-summary-errors, span.error, div.error"
        let messages = try doc.select(selectors).array()
            .map { try $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return messages.first
    }

    static func validateUpdateResponse(html: String, finalURL: URL) throws {
        if let message = try validationMessage(in: html) {
            throw LectioError.parsingError(message)
        }
        if finalURL.path.lowercased().contains("fravaer_aarsag.aspx"),
           html.contains("StudentReasonDD") {
            throw LectioError.parsingError("Lectio afviste ændringen")
        }
    }

    private static func urlEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}
