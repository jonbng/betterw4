//
//  StudentSearchView.swift
//  BetterLectio
//

import Combine
import SwiftUI

enum DirectoryPresentation: Hashable {
    case full
    case classmates
    case teachers
    case classes
    case holds
    case rooms
    case groups
    case resources
}

private enum DirectoryRoute: Hashable {
    case entity(String)
}

private func directoryIconName(for entity: DirectoryEntity) -> String {
    switch entity.kind {
    case .student: return "person.fill"
    case .teacher: return "person.text.rectangle.fill"
    case .classSynthetic, .classLectio: return "person.2.fill"
    case .hold: return "person.3.fill"
    case .room: return "door.left.hand.closed"
    case .resource: return "shippingbox.fill"
    case .group: return "person.3.sequence.fill"
    case .other: return "square.grid.2x2.fill"
    }
}

/// Fetches picture ID in local `@State` so `DirectoryViewModel` is not republished for every row.
private struct DirectoryPersonRemoteView: View {
    enum Style {
        case avatar(CGFloat)
        case preview
    }

    let entity: DirectoryEntity
    let authenticatedStudent: Student
    let style: Style

    @State private var url: URL?
    @State private var betterLectioURL: URL?

    private var lectioURL: URL? { url ?? DirectoryStore.shared.pictureURL(for: entity) }

    var body: some View {
        Group {
            switch style {
            case .avatar(let size):
                if betterLectioURL != nil {
                    PublicProfileAvatarView(
                        url: betterLectioURL,
                        name: entity.name,
                        size: size,
                        lectioFallbackURL: lectioURL
                    )
                } else {
                    LectioAvatarView(url: lectioURL, name: entity.name, size: size)
                }
            case .preview:
                PublicProfilePreviewImage(url: betterLectioURL, lectioFallbackURL: lectioURL) {
                    LectioAvatarView.initialsPlaceholder(name: entity.name, size: 160)
                }
                .frame(maxWidth: .infinity, minHeight: 320)
                .frame(width: 320)
            }
        }
        .task(id: entity.id) {
            await loadImages(forceRefresh: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .profilePictureDidChange)) { notification in
            guard entity.kind == .student else { return }
            let changedID = notification.userInfo?["studentId"] as? String
            guard changedID == nil || changedID == entity.numericID else { return }
            Task { await loadImages(forceRefresh: true) }
        }
    }

    private func loadImages(forceRefresh: Bool) async {
        let store = DirectoryStore.shared
        var resolvedURL = store.pictureURL(for: entity)
        if resolvedURL == nil, entity.hasAvatar {
            await store.fetchPictureIDIfNeeded(
                for: entity,
                authenticatedStudentID: authenticatedStudent.studentId
            )
            resolvedURL = store.pictureURL(for: entity)
        }
        guard !Task.isCancelled else { return }
        url = resolvedURL
        if entity.kind == .student {
            let profile = try? await SupabaseStudentProfileService.shared.profile(
                studentID: entity.numericID,
                viewer: authenticatedStudent,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else { return }
            betterLectioURL = profile?.pictureURL(fallback: nil)
        }
    }
}

private struct DirectoryPersonMenu: View {
    let entity: DirectoryEntity
    let studentId: String
    @ObservedObject var viewModel: DirectoryViewModel
    @Binding var navigationPath: NavigationPath

    var body: some View {
        Section {
            Button {
                navigationPath.append(DirectoryRoute.entity(entity.id))
            } label: {
                Label(
                    entity.kind == .student ? "Åbn profil" : "Åbn skema",
                    systemImage: entity.kind == .student ? "person.crop.circle" : "calendar"
                )
            }
            Button {
                viewModel.togglePin(for: entity, currentStudentID: studentId)
            } label: {
                Label(viewModel.isPinned(entity) ? "Frigør" : "Fastgør", systemImage: viewModel.isPinned(entity) ? "pin.slash" : "pin")
            }
        } header: {
            Text(entity.name)
        }
        if let classCode = entity.classCode,
           let classEntity = viewModel.classes.first(where: { $0.classCode?.caseInsensitiveCompare(classCode) == .orderedSame }) {
            Section {
                Button {
                    navigationPath.append(DirectoryRoute.entity(classEntity.id))
                } label: {
                    Label("Alle i \(classCode)", systemImage: "person.2")
                }
            } header: {
                Text("Klasse")
            }
        }
    }
}

private struct DirectoryEntityRow: View {
    let entity: DirectoryEntity
    let authenticatedStudent: Student
    @ObservedObject var viewModel: DirectoryViewModel
    @Binding var navigationPath: NavigationPath
    var subtitleOverride: String? = nil

    var body: some View {
        NavigationLink(value: DirectoryRoute.entity(entity.id)) {
            HStack(spacing: 12) {
                if entity.isPerson {
                    DirectoryPersonRemoteView(entity: entity, authenticatedStudent: authenticatedStudent, style: .avatar(44))
                } else {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: directoryIconName(for: entity))
                            .foregroundColor(.accentColor)
                            .font(.system(size: 18, weight: .medium))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if let subtitle = subtitleOverride ?? entity.displaySubtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if entity.isPerson {
                DirectoryPersonMenu(
                    entity: entity,
                    studentId: authenticatedStudent.studentId,
                    viewModel: viewModel,
                    navigationPath: $navigationPath
                )
            } else if entity.kind == .classSynthetic {
                Button {
                    navigationPath.append(DirectoryRoute.entity(entity.id))
                } label: {
                    Label("Vis klasse", systemImage: "person.2.fill")
                }
            } else if entity.kind == .hold {
                Button {
                    navigationPath.append(DirectoryRoute.entity(entity.id))
                } label: {
                    Label("Vis hold", systemImage: "person.3.fill")
                }
            }
        } preview: {
            if entity.isPerson {
                DirectoryPersonRemoteView(entity: entity, authenticatedStudent: authenticatedStudent, style: .preview)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: directoryIconName(for: entity))
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(.accentColor)
                    Text(entity.name).font(.headline)
                    if let subtitle = entity.displaySubtitle {
                        Text(subtitle).font(.subheadline).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 260)
                .frame(width: 320)
            }
        }
    }
}

struct StudentSearchView: View {
    let student: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @Binding var navigationPath: NavigationPath
    var presentation: DirectoryPresentation = .full
    @StateObject private var viewModel = DirectoryViewModel()
    @State private var showEntireDirectory = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.entities.isEmpty {
                loadingView
            } else if presentation == .full {
                contentView
            } else {
                focusedContentView
            }
        }
        .navigationTitle(focusedNavigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchQuery, prompt: "Søg efter personer, klasser, hold, lokaler og ressourcer...")
        .task(id: student.studentId) {
            await viewModel.loadDirectory(for: student)
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterLectioCachesDidClear)) { _ in
            Task {
                await viewModel.refreshDirectory(for: student)
            }
        }
        .refreshable {
            await viewModel.refreshDirectory(for: student)
        }
        .navigationDestination(for: DirectoryRoute.self) { route in
            switch route {
            case .entity(let id):
                if let entity = viewModel.entity(id: id) {
                    destinationView(for: entity)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)

            Text("Indlæser katalog…")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var contentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if viewModel.isSearching {
                    searchResultsSection
                } else {
                    if !viewModel.pinnedPeople.isEmpty {
                        pinnedPeopleSection
                    }

                    classmatesSection
                    teachersSection
                    showFullDirectoryToggle

                    if showEntireDirectory {
                        classesSection
                        holdsSection
                        roomsSection
                        resourcesSection
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var focusedNavigationTitle: String {
        switch presentation {
        case .full: return "Elever"
        case .classmates: return "Klassekammerater"
        case .teachers: return "Lærere"
        case .classes: return "Klasser"
        case .holds: return "Hold"
        case .rooms: return "Lokaler"
        case .groups: return "Grupper"
        case .resources: return "Ressourcer"
        }
    }

    private var focusedContentView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if viewModel.isSearching {
                    searchResultsSection
                } else {
                    switch presentation {
                    case .full:
                        EmptyView()
                    case .classmates:
                        classmatesSection
                    case .teachers:
                        teachersSection
                    case .classes:
                        classesSection
                    case .holds:
                        holdsSection
                    case .rooms:
                        roomsSection
                    case .groups:
                        groupsSection
                    case .resources:
                        resourcesSection
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    @ViewBuilder
    private func destinationView(for entity: DirectoryEntity) -> some View {
        if entity.kind == .student {
            StudentProfileView(
                entity: entity,
                authenticatedStudent: student,
                authViewModel: authViewModel,
                directoryViewModel: viewModel,
                lectioImageURL: viewModel.pictureURL(for: entity),
                onOpenClass: { classEntity in
                    navigationPath.append(DirectoryRoute.entity(classEntity.id))
                }
            )
        } else if let target = entity.schedulableTarget {
            ScheduleView(
                authenticatedStudent: student,
                authViewModel: authViewModel,
                target: target,
                targetImageURL: viewModel.pictureURL(for: entity)
            )
        } else if entity.kind == .classSynthetic {
            DirectoryClassView(
                classEntity: entity,
                authenticatedStudent: student,
                authViewModel: authViewModel,
                viewModel: viewModel,
                navigationPath: $navigationPath
            )
        } else if entity.kind == .hold {
            DirectoryHoldView(
                holdEntity: entity,
                authenticatedStudent: student,
                authViewModel: authViewModel,
                viewModel: viewModel,
                navigationPath: $navigationPath
            )
        } else {
            DirectoryGroupView(
                entity: entity,
                viewModel: viewModel,
                navigationPath: $navigationPath
            )
        }
    }

    private var pinnedPeopleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Fastgjort")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                ForEach(viewModel.pinnedPeople) { entity in
                    NavigationLink(value: DirectoryRoute.entity(entity.id)) {
                        VStack(spacing: 6) {
                            DirectoryPersonRemoteView(entity: entity, authenticatedStudent: student, style: .avatar(56))
                            Text(entity.name.split(separator: " ").first.map(String.init) ?? entity.name)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            if let subtitle = entity.displaySubtitle {
                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        DirectoryPersonMenu(
                            entity: entity,
                            studentId: student.studentId,
                            viewModel: viewModel,
                            navigationPath: $navigationPath
                        )
                    } preview: {
                        DirectoryPersonRemoteView(entity: entity, authenticatedStudent: student, style: .preview)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var classmatesSection: some View {
        let classmates = viewModel.classmates(for: student)

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Klassekammerater")

            if classmates.isEmpty {
                emptySection("Ingen klassekammerater fundet")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(classmates) { entity in
                        directoryRow(entity)
                    }
                }
            }
        }
    }

    private var teachersSection: some View {
        let mine = viewModel.myTeachers(for: student)
        let teachers = mine.isEmpty ? Array(viewModel.teachers.prefix(20)) : mine

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader(mine.isEmpty ? "Lærere" : "Mine lærere")
            if teachers.isEmpty {
                emptySection("Ingen lærere fundet")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(teachers) { entity in
                        directoryRow(entity)
                    }
                }
            }
        }
    }

    private var showFullDirectoryToggle: some View {
        Button {
            showEntireDirectory.toggle()
        } label: {
            HStack {
                Text(showEntireDirectory ? "Skjul klasser, hold og lokaler" : "Vis hele kataloget")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: showEntireDirectory ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.accentColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var classesSection: some View {
        let classes = viewModel.classes

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Klasser")

            if classes.isEmpty {
                emptySection("Ingen klasser fundet")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(classes) { entity in
                        NavigationLink(value: DirectoryRoute.entity(entity.id)) {
                            directoryCard(entity, subtitle: "\(viewModel.memberCount(of: entity)) elever")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var holdsSection: some View {
        let holds = Array(viewModel.holds.prefix(12))

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Hold")
            if holds.isEmpty {
                emptySection("Ingen hold fundet")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(holds) { entity in
                        directoryRow(entity, subtitleOverride: holdSubtitle(for: entity))
                    }
                }
            }
        }
    }

    private var roomsSection: some View {
        let rooms = Array(viewModel.rooms.prefix(10))

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Lokaler")
            if rooms.isEmpty {
                emptySection("Ingen lokaler fundet")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rooms) { entity in
                        directoryRow(entity)
                    }
                }
            }
        }
    }

    private var resourcesSection: some View {
        let resources = Array(viewModel.resources.prefix(10))

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Ressourcer")
            if resources.isEmpty {
                emptySection("Ingen ressourcer fundet")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(resources) { entity in
                        directoryRow(entity)
                    }
                }
            }
        }
    }

    private var groupsSection: some View {
        let list = viewModel.groups

        return VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Grupper")
            if list.isEmpty {
                emptySection("Ingen grupper fundet")
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(list) { entity in
                        directoryRow(entity)
                    }
                }
            }
        }
    }

    private var searchResultsSection: some View {
        let sections = viewModel.searchSections()

        return VStack(alignment: .leading, spacing: 12) {
            if sections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Ingen resultater")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader(section.title)
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(section.entities) { entity in
                                directoryRow(entity, subtitleOverride: entity.kind == .hold ? holdSubtitle(for: entity) : nil)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)
    }

    private func emptySection(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
    }

    private func holdSubtitle(for entity: DirectoryEntity) -> String? {
        let count = viewModel.memberCount(of: entity)
        if count > 0 {
            return "\(count) medlemmer"
        }
        return entity.displaySubtitle
    }

    private func directoryCard(_ entity: DirectoryEntity, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: directoryIconName(for: entity))
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Spacer()
            }

            Text(entity.name)
                .font(.headline)
                .foregroundColor(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func directoryRow(_ entity: DirectoryEntity, subtitleOverride: String? = nil) -> some View {
        DirectoryEntityRow(
            entity: entity,
            authenticatedStudent: student,
            viewModel: viewModel,
            navigationPath: $navigationPath,
            subtitleOverride: subtitleOverride
        )
    }
}

struct DirectoryClassView: View {
    let classEntity: DirectoryEntity
    let authenticatedStudent: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @ObservedObject var viewModel: DirectoryViewModel
    @Binding var navigationPath: NavigationPath

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let students = viewModel.students(in: classEntity)
                if students.isEmpty {
                    Text("Ingen elever fundet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(students) { entity in
                        DirectoryEntityRow(
                            entity: entity,
                            authenticatedStudent: authenticatedStudent,
                            viewModel: viewModel,
                            navigationPath: $navigationPath,
                            subtitleOverride: entity.seatNumber.map { "Nr. \($0)" }
                        )
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle(classEntity.name)
        .navigationBarTitleDisplayMode(.large)
    }
}

struct DirectoryHoldView: View {
    let holdEntity: DirectoryEntity
    let authenticatedStudent: Student
    @ObservedObject var authViewModel: AuthenticationViewModel
    @ObservedObject var viewModel: DirectoryViewModel
    @Binding var navigationPath: NavigationPath
    @State private var members: [DirectoryEntity] = []
    @State private var isLoading = true

    var body: some View {
        List {
            let teachers = members.filter { $0.kind == .teacher }
            let students = members.filter { $0.kind == .student }

            if members.isEmpty && isLoading {
                Section {
                    Text("Indlæser medlemmer...")
                        .foregroundColor(.secondary)
                }
            } else if members.isEmpty {
                Section {
                    Text("Ingen medlemmer fundet")
                        .foregroundColor(.secondary)
                }
            }

            if !teachers.isEmpty {
                Section("Lærere") {
                    ForEach(teachers) { entity in
                        NavigationLink(value: DirectoryRoute.entity(entity.id)) {
                            personRow(entity)
                        }
                    }
                }
            }

            if !students.isEmpty {
                Section("Elever") {
                    ForEach(students) { entity in
                        NavigationLink(value: DirectoryRoute.entity(entity.id)) {
                            personRow(entity)
                        }
                    }
                }
            }
        }
        .navigationTitle(holdEntity.name)
        .navigationBarTitleDisplayMode(.large)
        .task(id: holdEntity.id) {
            isLoading = true
            members = await viewModel.loadMembers(of: holdEntity)
            guard !Task.isCancelled else { return }
            await viewModel.ensureHoldMembers(for: holdEntity, authenticatedStudent: authenticatedStudent)
            guard !Task.isCancelled else { return }
            members = await viewModel.loadMembers(of: holdEntity)
            isLoading = false
        }
    }

    private func personRow(_ entity: DirectoryEntity) -> some View {
        HStack(spacing: 12) {
            DirectoryPersonRemoteView(entity: entity, authenticatedStudent: authenticatedStudent, style: .avatar(40))

            VStack(alignment: .leading, spacing: 2) {
                Text(entity.name)
                if let subtitle = entity.displaySubtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct DirectoryGroupView: View {
    let entity: DirectoryEntity
    @ObservedObject var viewModel: DirectoryViewModel
    @Binding var navigationPath: NavigationPath

    var body: some View {
        List {
            Section("Type") {
                Text(entity.kind.displayName)
            }

            if let subtitle = entity.displaySubtitle, !subtitle.isEmpty {
                Section("Info") {
                    Text(subtitle)
                }
            }

            if let classCode = entity.classCode {
                Section("Klasse") {
                    Text(classCode)
                }
            }

            if let linkedClass = viewModel.classes.first(where: { $0.classCode == entity.classCode }) {
                Section("Relateret") {
                    Button {
                        navigationPath.append(DirectoryRoute.entity(linkedClass.id))
                    } label: {
                        Label("Åbn \(linkedClass.name)", systemImage: "person.2.fill")
                    }
                }
            }
        }
        .navigationTitle(entity.name)
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    @Previewable @State var path = NavigationPath()
    NavigationStack(path: $path) {
        StudentSearchView(
            student: Student(studentId: "12345", gymId: 94, name: "Test Student"),
            authViewModel: AuthenticationViewModel(),
            navigationPath: $path
        )
    }
}
