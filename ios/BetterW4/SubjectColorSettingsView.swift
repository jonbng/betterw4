//
//  SubjectColorSettingsView.swift
//  BetterW4
//
//  Created by Kilo Code on 04/03/2026.
//

import SwiftUI

struct SubjectSettingsView: View {
    @StateObject private var settingsStore = SettingsStore.shared
    @State private var selectedSubject: SubjectMapper.SubjectInfo?
    @State private var showResetConfirmation = false
    let student: Student?
    var eventTitles: [String] = []

    private var subjects: [SubjectMapper.SubjectInfo] {
        SubjectMapper.allSubjects(including: eventTitles)
    }

    var body: some View {
        List {
            Section {
                ForEach(subjects) { subject in
                    SubjectRow(
                        subject: subject,
                        displayName: currentDisplayName(for: subject),
                        currentColor: currentColor(for: subject),
                        isCustom: settingsStore.hasCustomColor(for: subject.code) || settingsStore.hasCustomName(for: subject.code)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSubject = subject
                    }
                }
            } header: {
                Text("Subjects")
            } footer: {
                Text("Tap a subject to change its name and colour.")
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Label("Reset all customisations", systemImage: "arrow.counterclockwise")
                }
                .disabled(!hasAnyCustomizations)
            } footer: {
                Text("This removes all your custom names and colours.")
            }
        }
        .navigationTitle("Subject settings")
        .sheet(item: $selectedSubject) { subject in
            SubjectEditSheet(
                subject: subject,
                currentColor: currentColor(for: subject),
                currentName: settingsStore.customName(for: subject.code) ?? "",
                defaultName: currentDefaultName(for: subject),
                onSave: { name, color in
                    settingsStore.saveCustomization(name: name, color: color, for: subject.code)
                },
                onReset: {
                    settingsStore.resetMapping(for: subject.code)
                }
            )
        }
        .alert("Reset all customisations?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settingsStore.resetAllLessonMappings()
            }
        } message: {
            Text("Are you sure you want to remove all custom names and colours?")
        }
        .task {
            if let student = student {
                settingsStore.activateScope(studentId: student.studentId)
            }
        }
    }

    private func currentColor(for subject: SubjectMapper.SubjectInfo) -> Color {
        settingsStore.color(for: subject.code)
            ?? settingsStore.defaultColor(for: subject.code)
            ?? SubjectMapper.defaultColor(for: subject.code)
    }

    private func currentDisplayName(for subject: SubjectMapper.SubjectInfo) -> String {
        settingsStore.displayName(for: subject.code) ?? currentDefaultName(for: subject)
    }

    private func currentDefaultName(for subject: SubjectMapper.SubjectInfo) -> String {
        settingsStore.defaultName(for: subject.code)
            ?? SubjectMapper.defaultName(for: subject.code, fallback: subject.name)
    }

    private var hasAnyCustomizations: Bool {
        subjects.contains { subject in
            settingsStore.hasCustomColor(for: subject.code) || settingsStore.hasCustomName(for: subject.code)
        }
    }
}

// MARK: - Subject Row

private struct SubjectRow: View {
    let subject: SubjectMapper.SubjectInfo
    let displayName: String
    let currentColor: Color
    let isCustom: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: SubjectMapper.iconName(for: subject.code))
                .font(.title3)
                .foregroundColor(currentColor)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(currentColor.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                if isCustom {
                    Text("Customised")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Circle()
                .fill(currentColor)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Subject Edit Sheet

private struct SubjectEditSheet: View {
    let subject: SubjectMapper.SubjectInfo
    let currentColor: Color
    let currentName: String
    let defaultName: String
    let onSave: (String?, Color?) -> Void
    let onReset: () -> Void

    @State private var selectedColor: Color
    @State private var customName: String
    @Environment(\.dismiss) private var dismiss

    private let presetColors: [Color] = [
        .red, .orange, .yellow, .green,
        .mint, .teal, .cyan, .blue,
        .indigo, .purple, .pink, .brown
    ]

    init(subject: SubjectMapper.SubjectInfo, currentColor: Color, currentName: String, defaultName: String, onSave: @escaping (String?, Color?) -> Void, onReset: @escaping () -> Void) {
        self.subject = subject
        self.currentColor = currentColor
        self.currentName = currentName
        self.defaultName = defaultName
        self._selectedColor = State(initialValue: currentColor)
        self._customName = State(initialValue: currentName)
        self.onSave = onSave
        self.onReset = onReset
    }

    private var previewName: String {
        customName.isEmpty ? defaultName : customName
    }

    var body: some View {
        NavigationStack {
            Form {
                // Preview section
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: SubjectMapper.iconName(for: subject.code))
                                .font(.system(size: 50))
                                .foregroundColor(selectedColor)
                                .frame(width: 100, height: 100)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(selectedColor.opacity(0.2))
                                )

                            Text(previewName)
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)

                // Name section
                Section("Name") {
                    TextField(defaultName, text: $customName)
                        .autocorrectionDisabled()
                }

                // Preset colors
                Section("Colours") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(presetColors, id: \.self) { color in
                            ColorButton(
                                color: color,
                                isSelected: colorDescription(color) == colorDescription(selectedColor)
                            ) {
                                selectedColor = color
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Custom color picker
                Section("Custom colour") {
                    ColorPicker("Pick a colour", selection: $selectedColor)
                }

                // Reset button
                Section {
                    Button(role: .destructive) {
                        onReset()
                        dismiss()
                    } label: {
                        Label("Restore defaults", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle(defaultName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(customName.isEmpty ? nil : customName, selectedColor)
                        dismiss()
                    }
                }
            }
        }
    }

    private func colorDescription(_ color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%.3f-%.3f-%.3f", red, green, blue)
    }
}

// MARK: - Color Button

private struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 44, height: 44)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : Color.gray.opacity(0.3), lineWidth: isSelected ? 3 : 1)
                )
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.primary : Color.clear, lineWidth: isSelected ? 1 : 0)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        SubjectSettingsView(student: nil)
    }
}
