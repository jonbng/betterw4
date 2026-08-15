//
//  SchoolPickerView.swift
//  BetterLectio
//

import SwiftUI

struct SchoolPickerView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    Section {
                        schoolRow(School.demo)
                    } header: {
                        Text("Demo")
                    }
                }

                Section {
                    if viewModel.isLoadingSchools && realSchools.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Henter skoler…")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else if filteredSchools.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(searchText.isEmpty ? "Ingen skoler fundet" : "Ingen match for '\(searchText)'")
                                .foregroundColor(.secondary)
                            if let error = viewModel.schoolLoadError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        ForEach(filteredSchools) { school in
                            schoolRow(school)
                        }
                    }
                } header: {
                    Text("Alle skoler")
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Søg efter skole")
            .navigationTitle("Vælg skole")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuller") { dismiss() }
                }
            }
            .task { await viewModel.loadSchoolsFromSupabase() }
        }
    }

    private var realSchools: [School] {
        viewModel.schools.filter { !$0.isDemo }
    }

    private var filteredSchools: [School] {
        guard !searchText.isEmpty else { return realSchools }
        return realSchools.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    @ViewBuilder
    private func schoolRow(_ school: School) -> some View {
        Button {
            viewModel.selectedSchool = school
            dismiss()
            if school.isDemo {
                viewModel.loginWithMitID(source: "demo")
            } else {
                viewModel.loginWithMitID(source: "school_picker")
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: school.isDemo ? "sparkles" : "building.columns")
                    .font(.body)
                    .foregroundColor(school.isDemo ? .orange : .blue)
                    .frame(width: 24)

                Text(school.name)
                    .foregroundColor(.primary)

                Spacer()

                if viewModel.selectedSchool?.id == school.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
    }
}

#Preview {
    SchoolPickerView(viewModel: AuthenticationViewModel())
}
