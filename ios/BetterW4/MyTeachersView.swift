//
//  MyTeachersView.swift
//  BetterW4
//
//  More ▸ My teachers — the student's staff from `people/students/staff`.
//  Tap a row for the public staff profile.
//

import SwiftUI
import UIKit

struct MyTeachersView: View {
    @StateObject private var viewModel = MyTeachersViewModel()
    @StateObject private var directory = DirectoryViewModel()

    var body: some View {
        List {
            if viewModel.teachers.isEmpty, !viewModel.isLoading {
                ContentUnavailableView {
                    Label("No teachers", systemImage: "person.3")
                } description: {
                    Text(viewModel.errorMessage ?? "W4 did not list any teachers.")
                } actions: {
                    Button("Try again") {
                        Task { await viewModel.refresh() }
                    }
                }
            } else {
                ForEach(viewModel.teachers) { teacher in
                    NavigationLink {
                        StudentProfileView(person: teacher.person, directory: directory)
                    } label: {
                        teacherRow(teacher)
                    }
                }
            }

            if viewModel.freshness != nil {
                Section {
                    W4SurfaceFreshnessLabel(freshness: viewModel.freshness)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My teachers")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
        .overlay {
            if viewModel.isLoading, viewModel.teachers.isEmpty {
                ProgressView("Loading teachers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
            }
        }
    }

    private func teacherRow(_ teacher: MyTeacher) -> some View {
        HStack(spacing: 12) {
            W4AvatarView(
                url: teacher.photoURL,
                name: teacher.name,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(teacher.name)
                    .font(.body.weight(.medium))
                if let role = teacher.role, !role.isEmpty {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if !teacher.displayLevel.isEmpty {
                TeacherLevelBadge(level: teacher.level, label: teacher.displayLevel)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct TeacherLevelBadge: View {
    let level: ClassLevel
    var label: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(level.teacherColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(level.teacherColor.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(label)
    }
}

private extension ClassLevel {
    var teacherColor: Color {
        switch self {
        case .higher: return Color(red: 107 / 255, green: 63 / 255, blue: 160 / 255)
        case .standard: return Color(red: 15 / 255, green: 122 / 255, blue: 99 / 255)
        case .combined: return Color(red: 177 / 255, green: 92 / 255, blue: 0 / 255)
        case .none, .unknown: return Color(red: 95 / 255, green: 99 / 255, blue: 104 / 255)
        }
    }
}

#Preview("My teachers") {
    NavigationStack {
        MyTeachersView()
    }
}
