//
//  MyClassesView.swift
//  BetterW4
//
//  More ▸ My classes — the student's IB classes from `academics/classes/myclasses`.
//  Tap a class for teachers, students, room and HL/SL.
//

import SwiftUI
import UIKit

struct MyClassesView: View {
    @StateObject private var viewModel = MyClassesViewModel()
    @StateObject private var directory = DirectoryViewModel()

    var body: some View {
        List {
            if viewModel.classes.isEmpty, !viewModel.isLoading {
                ContentUnavailableView {
                    Label("No classes", systemImage: "books.vertical")
                } description: {
                    Text(viewModel.errorMessage ?? "W4 did not list any classes.")
                } actions: {
                    Button("Try again") {
                        Task { await viewModel.refresh() }
                    }
                }
            } else {
                ForEach(viewModel.classes) { item in
                    NavigationLink {
                        MyClassDetailView(
                            classId: item.id,
                            seed: viewModel.class(id: item.id) ?? item,
                            directory: directory,
                            nextLesson: viewModel.nextLesson(for: item.id),
                            selfUwcId: viewModel.selfUwcId
                        )
                    } label: {
                        classRow(item)
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
        .navigationTitle("My classes")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
        .overlay {
            if viewModel.isLoading, viewModel.classes.isEmpty {
                ProgressView("Loading classes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
            }
        }
    }

    private func classRow(_ item: MyClass) -> some View {
        HStack(spacing: 12) {
            ClassSubjectIcon(subject: item.subject)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.subject)
                    .font(.body.weight(.medium))
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let meta = listMeta(item) {
                    Text(meta)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            if !item.displayLevel.isEmpty {
                ClassLevelBadge(level: item.level, label: item.displayLevel, compact: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func listMeta(_ item: MyClass) -> String? {
        if let next = viewModel.nextLesson(for: item.id) {
            return next.dayTimeLabel(now: TimeProvider.now)
        }
        return item.meta
    }
}

// MARK: - Class detail

struct MyClassDetailView: View {
    let classId: String
    var seed: MyClass?
    @ObservedObject var directory: DirectoryViewModel
    var nextLesson: ClassNextLesson? = nil
    var selfUwcId: String? = nil

    @State private var item: MyClass?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var resolvedNextLesson: ClassNextLesson?

    private var shown: MyClass? { item ?? seed }

    var body: some View {
        List {
            if let shown {
                headerSection(shown)

                if let next = resolvedNextLesson ?? nextLesson {
                    Section {
                        infoRow(
                            systemImage: "clock",
                            title: next.detailLabel(now: TimeProvider.now),
                            subtitle: "Next lesson"
                        )
                    }
                }

                if let room = shown.room {
                    Section {
                        infoRow(
                            systemImage: "door.left.hand.closed",
                            title: room.name,
                            subtitle: "Room"
                        )
                    }
                }

                if !shown.teachers.isEmpty {
                    Section(shown.teachers.count == 1 ? "Teacher" : "Teachers") {
                        ForEach(shown.teachers) { member in
                            memberRow(member)
                        }
                    }
                }

                Section {
                    if !shown.loaded, shown.students.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading students…")
                                .foregroundStyle(.secondary)
                        }
                    } else if shown.students.isEmpty {
                        W4SurfaceEmptyRow(
                            text: "No students listed.",
                            systemImage: "person.2.slash"
                        )
                    } else {
                        ForEach(shown.students) { member in
                            memberRow(member)
                        }
                    }
                } header: {
                    Text(
                        shown.loaded
                            ? (shown.students.count == 1 ? "1 student" : "\(shown.students.count) students")
                            : "Students"
                    )
                }
            } else if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else {
                ContentUnavailableView {
                    Label("Class not found", systemImage: "books.vertical")
                } description: {
                    Text(errorMessage ?? "W4 did not return this class.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(shown?.subject ?? "Class")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await load(forceRefresh: true) }
        .task(id: classId) { await load() }
    }

    @ViewBuilder
    private func headerSection(_ item: MyClass) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.subject)
                    .font(.title3.weight(.semibold))
                FlowChips {
                    if !item.displayLevel.isEmpty {
                        ClassChip(text: item.displayLevel, color: item.level.color)
                    }
                    if let year = item.year, !year.isEmpty {
                        ClassChip(text: "Year \(year)")
                    }
                    if let block = item.block, !block.isEmpty {
                        ClassChip(text: "Block \(block)")
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func memberRow(_ member: ClassMember) -> some View {
        if member.canOpenProfile {
            NavigationLink {
                StudentProfileView(person: member.person, directory: directory)
            } label: {
                memberLabel(member)
            }
        } else {
            memberLabel(member)
        }
    }

    private func infoRow(systemImage: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func memberLabel(_ member: ClassMember) -> some View {
        HStack(spacing: 12) {
            W4AvatarView(
                url: member.photoURL,
                name: member.name,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.subheadline.weight(.semibold))
                if isSelf(member) {
                    Text("You")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if member.kind == .staff {
                    Text("Teacher")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if !member.level.badge.isEmpty {
                ClassLevelBadge(level: member.level, label: member.level.badge, compact: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func isSelf(_ member: ClassMember) -> Bool {
        guard let selfUwcId, !selfUwcId.isEmpty else { return false }
        return member.id.caseInsensitiveCompare(selfUwcId) == .orderedSame
    }

    private func load(forceRefresh: Bool = false) async {
        if shown == nil { isLoading = true }
        defer { isLoading = false }

        if resolvedNextLesson == nil, let cachedWeek = await TimetableRepository.shared.cachedWeek(containing: TimeProvider.now) {
            resolvedNextLesson = ClassNextLessons.next(
                in: cachedWeek.value,
                classId: classId,
                now: TimeProvider.now
            )
        }

        if item == nil, let cached = await MyClassRepository.shared.cachedClass(id: classId) {
            item = merge(cached.value)
            errorMessage = nil
        }

        do {
            let loaded = try await MyClassRepository.shared.loadClass(
                id: classId,
                forceRefresh: forceRefresh
            )
            item = merge(loaded.value)
            errorMessage = nil
        } catch {
            if error is CancellationError { return }
            (error as? W4Error)?.notifyIfSessionExpired()
            if shown == nil {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func merge(_ detail: MyClass) -> MyClass {
        let base = item ?? seed
        guard let base else { return detail }
        return W4ClassParser.merge(base: base, detail: detail)
    }
}

// MARK: - Chrome

private extension ClassLevel {
    var color: Color {
        switch self {
        case .higher: return Color(red: 107 / 255, green: 63 / 255, blue: 160 / 255)
        case .standard: return Color(red: 15 / 255, green: 122 / 255, blue: 99 / 255)
        case .combined: return Color(red: 177 / 255, green: 92 / 255, blue: 0 / 255)
        case .none, .unknown: return Color(red: 95 / 255, green: 99 / 255, blue: 104 / 255)
        }
    }
}

private struct ClassLevelBadge: View {
    let level: ClassLevel
    var label: String
    var compact: Bool = false

    var body: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(level.color)
            .padding(.horizontal, compact ? 7 : 8)
            .padding(.vertical, compact ? 3 : 6)
            .background(level.color.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
            .accessibilityLabel(label)
    }
}

private struct ClassChip: View {
    let text: String
    var color: Color = Color.accentColor

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }
}

private struct ClassSubjectIcon: View {
    let subject: String
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        let color = settings.useSubjectColors
            ? SubjectMapper.color(for: subject)
            : Color.secondary
        Image(systemName: SubjectMapper.iconName(for: subject))
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct FlowChips<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 52), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            content
        }
    }
}

#Preview("My classes") {
    NavigationStack {
        MyClassesView()
    }
}
