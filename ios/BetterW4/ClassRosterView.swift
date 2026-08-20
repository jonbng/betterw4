//
//  ClassRosterView.swift
//  BetterW4
//
//  People on `academics/classes/class&class_id=` — teachers then students.
//

import SwiftUI
import UIKit

struct ClassRosterView: View {
    let classId: String
    let title: String
    @ObservedObject var directory: DirectoryViewModel

    @State private var people: [DirectoryPerson] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading && people.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if people.isEmpty {
                ContentUnavailableView {
                    Label("No one listed", systemImage: "person.2.slash")
                } description: {
                    Text(errorMessage ?? "W4 did not list anyone in this class.")
                }
            } else {
                let staff = people.filter { $0.kind == .staff }
                let students = people.filter { $0.kind == .student }
                if !staff.isEmpty {
                    Section("Teachers") {
                        ForEach(staff) { person in
                            personRow(person)
                        }
                    }
                }
                if !students.isEmpty {
                    Section("Students") {
                        ForEach(students) { person in
                            personRow(person)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: classId) { await load() }
        .refreshable { await load(forceRefresh: true) }
    }

    private func personRow(_ person: DirectoryPerson) -> some View {
        NavigationLink {
            StudentProfileView(person: person, directory: directory)
        } label: {
            HStack(spacing: 12) {
                W4AvatarView(
                    url: person.photoURL ?? W4PeopleParser.photoURL(forUWCId: person.uwcId),
                    name: person.displayName,
                    size: 36
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle = person.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func load(forceRefresh: Bool = false) async {
        isLoading = people.isEmpty
        defer { isLoading = false }
        do {
            let loaded = try await ClassRosterRepository.shared.people(
                classId: classId,
                forceRefresh: forceRefresh
            )
            people = loaded.value
            errorMessage = nil
        } catch {
            if error is CancellationError { return }
            (error as? W4Error)?.notifyIfSessionExpired()
            if people.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}