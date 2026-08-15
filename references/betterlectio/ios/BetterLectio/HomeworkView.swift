//
//  HomeworkView.swift
//  BetterLectio
//

import Combine
import SwiftUI

struct HomeworkView: View {
    private static let sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "da_DK")
        formatter.dateFormat = "EEEE d. MMMM"
        return formatter
    }()

    let student: Student
    @StateObject private var viewModel = HomeworkViewModel()
    @State private var selectedHomework: HomeworkEntry?
    /// Incremented when the Lektier tab is tapped while already selected (scroll-to-top).
    @State private var scrollToTopTick = 0

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            Group {
                if viewModel.isLoading && viewModel.entries.isEmpty {
                    loadingView
                } else if let error = viewModel.errorMessage, viewModel.entries.isEmpty {
                    errorView(error)
                } else if viewModel.entries.isEmpty {
                    emptyView
                } else {
                    homeworkList
                }
            }
        }
        .navigationTitle("Lektier")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.loadHomework(for: student)
        }
        .task(id: student.studentId) {
            await viewModel.loadHomework(for: student)
        }
        .onReceive(NotificationCenter.default.publisher(for: .betterLectioCachesDidClear)) { _ in
            Task {
                await viewModel.loadHomework(for: student)
            }
        }
        .sheet(item: $selectedHomework) { entry in
            HomeworkDetailSheet(entry: entry, student: student, viewModel: viewModel)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Henter dine lektier...")
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.orange)

            Text(message)
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task { await viewModel.loadHomework(for: student) }
            } label: {
                Text("Prøv igen")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.blue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }

            VStack(spacing: 8) {
                Text("Alt klaret!")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)

                Text("Du har ingen lektier de næste 14 dage.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List (ScrollView: smooth height animation. List swipeActions force UITableView row jumps.)

    private var homeworkList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("homeworkListTop")
                    ForEach(viewModel.entriesByDate, id: \.date) { group in
                        scrollSectionHeader(date: group.date)
                        ForEach(group.entries) { entry in
                            HomeworkSwipeRow(
                                isDone: viewModel.isDone(entry.id),
                                onTapContent: {
                                    selectedHomework = entry
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                },
                                onCheckboxTap: { toggleHomeworkDone(entry) },
                                onSwipeAction: { toggleHomeworkDone(entry) }
                            ) {
                                HomeworkCard(entry: entry, student: student, viewModel: viewModel)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .onChange(of: scrollToTopTick) { _, _ in
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    proxy.scrollTo("homeworkListTop", anchor: .top)
                }
            }
            .background {
                TabBarSameTabReselectDetector {
                    scrollToTopTick += 1
                }
            }
        }
    }

    private func scrollSectionHeader(date: Date) -> some View {
        HStack {
            Text(formattedSectionDate(date))
                .font(.system(.title3, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.top, 14)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func toggleHomeworkDone(_ entry: HomeworkEntry) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            viewModel.toggleDone(entryId: entry.id, student: student)
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    // MARK: - Helpers

    private func formattedSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "I dag" }
        if calendar.isDateInTomorrow(date) { return "I morgen" }

        return Self.sectionDateFormatter.string(from: date).capitalized
    }
}

// MARK: - Swipe row (UIKit swipeActions only exist on List rows.)

private struct HomeworkSwipeRow<Content: View>: View {
    let isDone: Bool
    let onTapContent: () -> Void
    let onCheckboxTap: () -> Void
    let onSwipeAction: () -> Void
    @ViewBuilder let content: () -> Content

    /// Settled open width; extra pull elongates the shape (pill stretches horizontally).
    private let actionWidth: CGFloat = 88
    /// Fixed vertical size of the swipe control (not full row height).
    private let actionHeight: CGFloat = 52
    /// Space between the swipe blob’s trailing edge and the homework card.
    private let cardSwipeGap: CGFloat = 10
    /// Finger travel is ~1:1 with card offset up to this, then logarithmic resistance (no hard cap).
    private let pullFreeRun: CGFloat = 58
    private let pullResistanceScale: CGFloat = 34
    /// Ease-out (no spring overshoot) + `drawingGroup` on the card: animated `offset` otherwise interpolates text/SF Symbols/buttons on slightly different paths.
    private let settleAnimation = Animation.easeOut(duration: 0.22)

    @State private var offset: CGFloat = 0
    @State private var horizontalSwipeActive = false
    @State private var linearAtGestureStart: CGFloat = 0
    @State private var translationWhenLocked: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    /// Trailing hit zone routed to the done-toggle instead of opening detail — covers the 24pt circle plus its 14pt trailing padding with a small buffer.
    private let checkboxHitZoneWidth: CGFloat = 44

    private var blobWidth: CGFloat {
        max(0, offset - cardSwipeGap)
    }

    /// Calmer than default `Color.blue` on grouped backgrounds; still reads clearly as “primary action”.
    private var swipeCompleteFill: Color {
        Color(red: 0.12, green: 0.44, blue: 0.93)
    }

    private var swipeUndoFill: Color {
        Color(UIColor.systemGray2)
    }

    private var activeSwipeFill: Color {
        isDone ? swipeUndoFill : swipeCompleteFill
    }

    var body: some View {
        // iOS 18 / SwiftUI 6: ScrollView + child DragGesture breaks vertical scroll unless the row tap
        // is `TapGesture().exclusively(before:)` the same drag instance as a high-priority gesture.
        // See https://stackoverflow.com/questions/79001004
        // SpatialTapGesture (not TapGesture) so we can route trailing-edge taps to the checkbox —
        // the nested checkbox Button cannot receive taps while this gesture is high-priority.
        let rowTapGesture = SpatialTapGesture(coordinateSpace: .local).onEnded { value in
            if offset > 6 {
                withAnimation(settleAnimation) { offset = 0 }
                return
            }
            if contentWidth > 0, value.location.x >= contentWidth - checkboxHitZoneWidth {
                onCheckboxTap()
            } else {
                onTapContent()
            }
        }
        let dragGesture = DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if !horizontalSwipeActive {
                    if abs(dy) >= abs(dx), abs(dy) > 14 { return }
                    if abs(dx) > 14, abs(dx) >= abs(dy) {
                        horizontalSwipeActive = true
                        linearAtGestureStart = linearFromDisplay(offset)
                        translationWhenLocked = dx
                    } else {
                        return
                    }
                }
                let L = linearAtGestureStart + dx - translationWhenLocked
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    offset = displayFromLinearPull(max(0, L))
                }
            }
            .onEnded { value in
                let wasHorizontal = horizontalSwipeActive
                horizontalSwipeActive = false
                guard wasHorizontal else { return }

                let L = linearAtGestureStart + value.translation.width - translationWhenLocked
                let v = value.velocity.width
                let d = displayFromLinearPull(max(0, L))

                let commitLinear: CGFloat = 158
                let flickOutVelocity: CGFloat = 520
                let flickOutMinLinear: CGFloat = 44
                let peekDisplay: CGFloat = actionWidth * 0.46
                let peekLinear: CGFloat = 98
                let dismissLinear: CGFloat = 26
                let dismissVelocity: CGFloat = 400
                let flickInVelocity: CGFloat = -420

                withAnimation(settleAnimation) {
                    if L >= commitLinear || (v > flickOutVelocity && L > flickOutMinLinear) {
                        onSwipeAction()
                        offset = 0
                    } else if v < flickInVelocity {
                        offset = 0
                    } else if L < dismissLinear && abs(v) < dismissVelocity {
                        offset = 0
                    } else if d >= peekDisplay || L >= peekLinear {
                        offset = actionWidth
                    } else if d < 20 {
                        offset = 0
                    } else {
                        offset = abs(d - actionWidth) < abs(d - 0) ? actionWidth : 0
                    }
                }
            }

        return ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    if blobWidth > 0.5 {
                        GeometryReader { geo in
                            let w = geo.size.width
                            let h = actionHeight
                            let corner = min(w, h) / 2
                            let iconT = iconRevealProgress(width: w)

                            Button {
                                onSwipeAction()
                                withAnimation(settleAnimation) { offset = 0 }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                                        .fill(activeSwipeFill)

                                    Image(systemName: isDone ? "arrow.uturn.backward" : "checkmark")
                                        .font(.system(size: 20, weight: .semibold))
                                        .symbolRenderingMode(.monochrome)
                                        .foregroundStyle(.white)
                                        .scaleEffect(0.2 + 0.8 * iconT)
                                        .opacity(Double(iconT))
                                }
                                .frame(width: w, height: h)
                                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                                .compositingGroup()
                                .shadow(
                                    color: activeSwipeFill.opacity(0.35),
                                    radius: 5,
                                    y: 2
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(width: blobWidth, height: actionHeight)
                    }

                    Color.clear
                        .frame(width: max(0, offset - blobWidth))
                }
                .frame(width: max(offset, 0), alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .center)

                Spacer(minLength: 0)
            }
            content()
                .background(Color(UIColor.systemGroupedBackground))
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { contentWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in contentWidth = w }
                    }
                )
                .drawingGroup(opaque: false)
                .offset(x: offset)
                .simultaneousGesture(dragGesture)
                .highPriorityGesture(rowTapGesture.exclusively(before: dragGesture))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onChange(of: isDone) { _, _ in
            withAnimation(settleAnimation) { offset = 0 }
        }
    }

    /// Maps cumulative finger “effort” to visible offset: easy at first, then progressively harder, unbounded.
    private func displayFromLinearPull(_ L: CGFloat) -> CGFloat {
        guard L > 0 else { return 0 }
        if L <= pullFreeRun { return L }
        return pullFreeRun + pullResistanceScale * log(1 + (L - pullFreeRun) / pullResistanceScale)
    }

    /// Inverse of `displayFromLinearPull` so drag math stays consistent when starting mid-swipe.
    private func linearFromDisplay(_ d: CGFloat) -> CGFloat {
        guard d > 0 else { return 0 }
        if d <= pullFreeRun { return d }
        return pullFreeRun + pullResistanceScale * (exp((d - pullFreeRun) / pullResistanceScale) - 1)
    }

    private func iconRevealProgress(width w: CGFloat) -> CGFloat {
        let start: CGFloat = 6
        let end = max(24, actionHeight * 0.45)
        return smoothstep((w - start) / max(end - start, 1))
    }

    private func smoothstep(_ t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

// MARK: - Homework Card

private struct HomeworkCard: View {
    let entry: HomeworkEntry
    let student: Student
    @ObservedObject var viewModel: HomeworkViewModel

    @State private var isExpanded: Bool = true

    /// Isolated from the checkbox swipe/check spring so collapse doesn’t inherit bounce.
    private static let expandCollapseAnimation = Animation.easeInOut(duration: 0.22)
    
    private var isDone: Bool {
        viewModel.isDone(entry.id)
    }

    private var hasDetailContent: Bool {
        (entry.note != nil && !entry.note!.isEmpty) || !entry.items.isEmpty
    }
    
    private var themeColor: Color {
        SubjectMapper.color(for: entry.hold)
    }

    private var displayTitle: String {
        if SubjectMapper.isKnownSubject(entry.hold) {
            return SubjectMapper.displayName(for: entry.hold)
        }
        return entry.title ?? entry.hold
    }

    var body: some View {
        cardContent
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(isDone ? 0.5 : 1.0)
            .grayscale(isDone ? 0.8 : 0)
            .onAppear {
                if isDone { isExpanded = false }
            }
            .onChange(of: isDone) { _, done in
                var t = Transaction()
                t.animation = Self.expandCollapseAnimation
                withTransaction(t) {
                    isExpanded = !done
                }
            }
    }
    
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Section
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(themeColor.opacity(isDone ? 0.05 : 0.12))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: SubjectMapper.iconName(for: entry.hold))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isDone ? .secondary : themeColor)
                        .symbolEffectsRemoved()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundColor(isDone ? .secondary : .primary)
                        .strikethrough(isDone, color: .secondary)
                    
                    if let teacher = entry.teacher, !teacher.isEmpty {
                        Text(teacher)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                            .strikethrough(isDone, color: .secondary)
                    }
                }

                Spacer()

                if entry.status == .changed && !isDone {
                    StatusBadge(text: "Ændret", color: .orange)
                }

                if hasDetailContent {
                    Button {
                        withAnimation(Self.expandCollapseAnimation) {
                            isExpanded.toggle()
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Skjul lektier" : "Vis lektier")
                }
                
                // Keep the manual checkbox for accessibility/classic feel
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        viewModel.toggleDone(entryId: entry.id, student: student)
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(isDone ? Color.blue : Color.secondary.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 24, height: 24)
                        
                        if isDone {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 18, height: 18)
                                .transition(.scale.combined(with: .opacity))
                            
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .symbolEffectsRemoved()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color(UIColor.secondarySystemGroupedBackground))


            // Content Section
            if isExpanded && hasDetailContent {
                VStack(alignment: .leading, spacing: 14) {
                    // Note from teacher
                    if let note = entry.note, !note.isEmpty {
                        Text(note)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(isDone ? .secondary : .primary.opacity(0.9))
                            .strikethrough(isDone, color: .secondary)
                            .lineLimit(6)
                            .padding(.horizontal, 14)
                    }

                    // Homework list items
                    if !entry.items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(entry.items) { item in
                                HomeworkItemRow(item: item, themeColor: themeColor, isDone: isDone)
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.bottom, 16)
                .padding(.top, 4)
                .opacity(isDone ? 0.6 : 1.0)
                .transition(.opacity)
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .shadow(color: Color.black.opacity(isDone ? 0 : 0.03), radius: 8, x: 0, y: 4)
    }
}


// MARK: - Status Badge

private struct StatusBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Homework Item Row

private struct HomeworkItemRow: View {
    let item: HomeworkItem
    let themeColor: Color
    let isDone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 10))
                .foregroundColor(isDone ? .secondary.opacity(0.5) : themeColor)
                .padding(.top, 4)

            Group {
                if let urlString = item.url,
                   let url = URL(string: urlString.hasPrefix("http") ? urlString : "https://www.lectio.dk\(urlString)") {
                    Link(destination: url) {
                        itemContent
                    }
                } else {
                    itemContent
                }
            }
        }
    }

    private var itemContent: some View {
        Text(item.text)
            .font(.system(.subheadline, design: .rounded))
            .foregroundColor(isDone ? .secondary : .primary.opacity(0.8))
            .strikethrough(isDone, color: .secondary)
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}


#Preview {
    NavigationStack {
        HomeworkView(student: Student(studentId: "12345", gymId: 94, name: "Test Student"))
    }
}

// MARK: - Homework Detail Sheet

struct HomeworkDetailSheet: View {
    let entry: HomeworkEntry
    let student: Student
    @ObservedObject var viewModel: HomeworkViewModel

    @State private var content: LessonContent?
    @State private var isLoadingContent = true
    @Environment(\.dismiss) private var dismiss

    private var themeColor: Color {
        SubjectMapper.color(for: entry.hold)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerSection

                    // Info row
                    infoSection

                    Divider()

                    // Content
                    if isLoadingContent {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 32)
                            Spacer()
                        }
                    } else if let content, (!content.items.isEmpty || content.teacherNote != nil) {
                        // Teacher note
                        if let note = content.teacherNote {
                            teacherNoteSection(note)
                        }

                        // Homework
                        if !content.homework.isEmpty {
                            contentSection(title: "Lektier", items: content.homework)
                        }

                        // Other content
                        if !content.otherContent.isEmpty {
                            contentSection(title: "Øvrigt indhold", items: content.otherContent)
                        }
                    } else {
                        Text("Intet yderligere indhold")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }
                }
                .padding(20)
            }
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
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            // Show cached content immediately
            content = await viewModel.cachedContent(for: entry, student: student)
            isLoadingContent = content == nil

            // Always refresh silently in the background
            if let fresh = await viewModel.refreshContent(for: entry, student: student) {
                content = fresh
            }
            isLoadingContent = false
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: SubjectMapper.iconName(for: entry.hold))
                .font(.title2)
                .foregroundColor(themeColor)
                .frame(width: 44, height: 44)
                .background(themeColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(SubjectMapper.displayName(for: entry.hold))
                        .font(.title3)
                        .fontWeight(.bold)

                    if entry.status == .cancelled {
                        Text("Aflyst")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Capsule())
                    } else if entry.status == .changed {
                        Text("Ændret")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                
                let titleText = entry.title != nil && entry.title != "" ? entry.title! : entry.hold
                Text(titleText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(spacing: 10) {
            infoRow(icon: "calendar", text: entry.displayDate)

            if let teacher = entry.teacher, !teacher.isEmpty {
                infoRow(icon: "person", text: teacher)
            }

            if let room = entry.room, !room.isEmpty {
                infoRow(icon: "mappin.and.ellipse", text: room)
            }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)

            Spacer()
        }
    }

    // MARK: - Teacher Note

    private func teacherNoteSection(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Note fra lærer", systemImage: "quote.opening")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(note)
                .font(.subheadline)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: - Content Section

    private func contentSection(title: String, items: [LessonContentItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            ForEach(items) { item in
                LessonContentItemView(item: item)
            }
        }
    }
}
