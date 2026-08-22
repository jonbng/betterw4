import Combine
import SwiftUI

@MainActor
private final class RegisterAbsenceViewModel: ObservableObject {
    @Published var form: AbsenceRegistrationForm?
    @Published var selectedValues: Set<String> = []
    @Published var wholeDay = false
    @Published var reason = ""
    @Published var selectedDate = W4Dates.startOfDay(TimeProvider.now)
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var useWebFallback = false

    private let repository: AttendanceRepository

    init(repository: AttendanceRepository = .shared) {
        self.repository = repository
    }

    var canSubmit: Bool {
        guard let form, form.canSubmit else { return false }
        return !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (wholeDay || !selectedValues.isEmpty)
            && !isLoading
    }

    func load(date: Date? = nil) async {
        if let date { selectedDate = W4Dates.startOfDay(date) }
        isLoading = true
        errorMessage = nil
        do {
            let raw = W4Dates.format(selectedDate)
            let loaded = try await repository.loadRegistrationForm(date: raw, forceRefresh: true)
            guard !loaded.value.isEmpty else {
                useWebFallback = true
                isLoading = false
                return
            }
            form = loaded.value
            if let parsed = W4Dates.parseDate(loaded.value.date) { selectedDate = parsed }
            reason = loaded.value.reason
            selectedValues = Set(loaded.value.slots.filter(\.checked).map(\.value))
            wholeDay = false
        } catch {
            if error is CancellationError { return }
            (error as? W4Error)?.notifyIfSessionExpired()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            useWebFallback = true
        }
        isLoading = false
    }

    func toggle(_ value: String) {
        wholeDay = false
        if !selectedValues.insert(value).inserted { selectedValues.remove(value) }
    }

    func submit() async -> Bool {
        guard let form, canSubmit else { return false }
        isLoading = true
        errorMessage = nil
        do {
            try await repository.submitRegistration(
                form: form,
                selectedValues: Array(selectedValues),
                wholeDay: wholeDay,
                reason: reason
            )
            isLoading = false
            return true
        } catch {
            if error is CancellationError { return false }
            (error as? W4Error)?.notifyIfSessionExpired()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            useWebFallback = true
            isLoading = false
            return false
        }
    }
}

struct RegisterAbsenceView: View {
    let student: Student
    var onSubmitted: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = RegisterAbsenceViewModel()
    @State private var credentials: W4Credentials = .empty

    var body: some View {
        Group {
            if student.isDemo {
                ContentUnavailableView(
                    "Not available in demo mode.",
                    systemImage: "wifi.slash",
                    description: Text("Registering an absence needs a live W4 session.")
                )
            } else if viewModel.useWebFallback {
                webFallback
            } else {
                nativeForm
            }
        }
        .navigationTitle("Register absences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task(id: student.studentId) {
            credentials = (try? W4RequestContext.require())?.credentials ?? .empty
            if !student.isDemo { await viewModel.load() }
        }
    }

    private var nativeForm: some View {
        Form {
            DatePicker(
                "Date",
                selection: $viewModel.selectedDate,
                displayedComponents: .date
            )
            .onChange(of: viewModel.selectedDate) { _, date in
                Task { await viewModel.load(date: date) }
            }

            if viewModel.isLoading, viewModel.form == nil {
                ProgressView("Loading classes…")
            } else if let form = viewModel.form {
                if let message = form.emptyDayMessage {
                    Text(message).foregroundStyle(.secondary)
                } else {
                    Section("Classes and activities") {
                        Toggle("Whole day", isOn: $viewModel.wholeDay)
                        ForEach(form.slots) { slot in
                            Button {
                                viewModel.toggle(slot.value)
                            } label: {
                                HStack {
                                    Image(systemName: viewModel.wholeDay || viewModel.selectedValues.contains(slot.value)
                                        ? "checkmark.square.fill" : "square")
                                    Text(slot.label)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(slot.disabled || viewModel.wholeDay)
                        }
                    }

                    Section("Reason") {
                        TextField("Required", text: $viewModel.reason)
                            .onChange(of: viewModel.reason) { _, value in
                                if value.count > 60 { viewModel.reason = String(value.prefix(60)) }
                            }
                        Text("\(viewModel.reason.count)/60")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Button("Register absences") {
                            Task {
                                if await viewModel.submit() {
                                    await onSubmitted()
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!viewModel.canSubmit)
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red)
                    Button("Open W4 instead") { viewModel.useWebFallback = true }
                }
            }
        }
        .overlay { if viewModel.isLoading, viewModel.form != nil { ProgressView() } }
    }

    private var webFallback: some View {
        Group {
            if credentials.isEmpty {
                ProgressView()
            } else {
                W4WebView(
                    url: W4Routes.url(
                        W4Routes.R.absencesRegister,
                        ["date": W4Dates.format(viewModel.selectedDate)]
                    ),
                    credentials: credentials
                )
            }
        }
    }
}
