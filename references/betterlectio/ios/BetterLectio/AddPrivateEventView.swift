//
//  AddPrivateEventView.swift
//  BetterLectio
//

import SwiftUI

struct AddPrivateEventView: View {
    let student: Student
    let schoolId: Int
    let initialDate: Date
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var note: String = ""
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let httpClient = LectioHTTPClient()
    private let keychainManager = KeychainManager.shared

    init(student: Student, schoolId: Int, initialDate: Date, onCreated: @escaping () -> Void) {
        self.student = student
        self.schoolId = schoolId
        self.initialDate = initialDate
        self.onCreated = onCreated

        let calendar = Calendar.current
        let defaultStart = calendar.date(
            bySettingHour: 12, minute: 0, second: 0, of: initialDate
        ) ?? initialDate
        let defaultEnd = calendar.date(byAdding: .hour, value: 1, to: defaultStart) ?? defaultStart
        _startDate = State(initialValue: defaultStart)
        _endDate = State(initialValue: defaultEnd)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $title)
                }

                Section("Tidspunkt") {
                    DatePicker("Start", selection: $startDate)
                    DatePicker("Slut", selection: $endDate, in: startDate...)
                }

                Section("Note") {
                    TextEditor(text: $note)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Ny privat aftale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annuller") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Gem") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .alert("Fejl", isPresented: .constant(errorMessage != nil)) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay {
                if isSaving {
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
            }
            .onChange(of: startDate) { _, newStart in
                if endDate < newStart {
                    endDate = newStart.addingTimeInterval(3600)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && endDate >= startDate
    }

    private func save() async {
        guard let credentials = keychainManager.loadCredentials(for: student.studentId) else {
            errorMessage = LectioError.invalidCredentials.errorDescription
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await httpClient.createPrivateEvent(
                credentials: credentials,
                studentId: student.studentId,
                schoolId: schoolId,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                start: startDate,
                end: endDate,
                note: note
            )
            onCreated()
            dismiss()
        } catch let error as LectioError {
            error.notifyIfSessionExpired()
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
