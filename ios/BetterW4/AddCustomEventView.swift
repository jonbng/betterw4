//
//  AddCustomEventView.swift
//  BetterW4
//
//  Create or edit a device-local timetable event. Nothing is posted to W4.
//

import SwiftUI

struct CustomEventEditor: Identifiable, Equatable {
    let id: String
    var existingId: String?
    var title: String
    var notes: String
    var start: Date
    var end: Date
    var isAllDay: Bool

    var isNew: Bool { existingId == nil }

    static func blank(on date: Date, now: Date = TimeProvider.now) -> CustomEventEditor {
        at(CustomEvents.defaultStart(on: date, now: now))
    }

    static func at(_ start: Date) -> CustomEventEditor {
        CustomEventEditor(
            id: UUID().uuidString,
            existingId: nil,
            title: "",
            notes: "",
            start: start,
            end: start.addingTimeInterval(3600),
            isAllDay: false
        )
    }

    static func editing(_ event: TimetableEvent) -> CustomEventEditor {
        var end = event.end ?? event.start ?? event.date
        if event.isAllDay {
            end = W4Dates.adding(days: -1, to: W4Dates.startOfDay(end))
        }
        return CustomEventEditor(
            id: event.id,
            existingId: event.id,
            title: event.title,
            notes: event.notes ?? "",
            start: event.start ?? event.date,
            end: end < (event.start ?? event.date) ? (event.start ?? event.date) : end,
            isAllDay: event.isAllDay
        )
    }
}

struct AddCustomEventView: View {
    let editor: CustomEventEditor
    var onSaved: (TimetableEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    @State private var title: String
    @State private var notes: String
    @State private var start: Date
    @State private var end: Date
    @State private var isAllDay: Bool
    @State private var confirmDelete = false

    init(editor: CustomEventEditor, onSaved: @escaping (TimetableEvent) -> Void) {
        self.editor = editor
        self.onSaved = onSaved
        _title = State(initialValue: editor.title)
        _notes = State(initialValue: editor.notes)
        _start = State(initialValue: editor.start)
        _end = State(initialValue: editor.end)
        _isAllDay = State(initialValue: editor.isAllDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What’s happening?", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onSubmit { if canSave { save() } }
                    Toggle("All day", isOn: $isAllDay)
                } footer: {
                    Text("Saved on this device. W4 never sees it.")
                }

                Section("When") {
                    DatePicker(
                        "Starts",
                        selection: $start,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                    DatePicker(
                        "Ends",
                        selection: $end,
                        in: start...,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )
                }

                Section("Note") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if !editor.isNew {
                    Section {
                        Button("Delete event", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .environment(\.timeZone, W4Dates.zone)
            .environment(\.calendar, W4Dates.calendar)
            .navigationTitle(editor.isNew ? "New event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { titleFocused = true }
            .onChange(of: start) { oldStart, newStart in
                let duration = max(end.timeIntervalSince(oldStart), 15 * 60)
                end = newStart.addingTimeInterval(duration)
            }
            .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete event", role: .destructive) {
                    if let id = editor.existingId {
                        CustomEventsStore.shared.delete(id: id)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && end >= start
    }

    private func save() {
        let event = CustomEventsStore.shared.save(
            title: title,
            notes: notes,
            start: start,
            end: end,
            isAllDay: isAllDay,
            replacing: editor.existingId
        )
        onSaved(event)
        dismiss()
    }
}

struct CustomEventDetailSheet: View {
    let event: TimetableEvent
    var onEdit: (TimetableEvent) -> Void
    var onDelete: (TimetableEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(event.displayTitle)
                    .font(.title2.weight(.bold))

                if event.isAllDay {
                    Label("All day", systemImage: "clock")
                        .foregroundStyle(.secondary)
                } else if let range = event.timeRangeText {
                    Label(range, systemImage: "clock")
                        .foregroundStyle(.secondary)
                }

                Label(W4Dates.format(event.date), systemImage: "calendar")
                    .foregroundStyle(.secondary)

                Text("On this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .padding(.top, 4)
                }

                Spacer(minLength: 8)

                Button {
                    let editing = event
                    dismiss()
                    DispatchQueue.main.async { onEdit(editing) }
                } label: {
                    Text("Edit event")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text("Delete event")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 15, weight: .heavy))
                    }
                }
            }
            .confirmationDialog("Delete this event?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete event", role: .destructive) {
                    let deleting = event
                    dismiss()
                    onDelete(deleting)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
