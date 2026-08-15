import SwiftUI

struct FeedbackSheet: View {
    @StateObject private var viewModel: FeedbackViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var messageFocused: Bool
    @State private var showingScreenshotPreview = false
    @State private var showingDiagnostics = false

    init(presentation: FeedbackPresentation) {
        _viewModel = StateObject(wrappedValue: FeedbackViewModel(presentation: presentation))
    }

    var body: some View {
        NavigationStack {
            Group {
                if case .success(let success) = viewModel.phase {
                    successView(success)
                } else {
                    composeView
                }
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isSuccess {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuller") { dismiss() }
                            .disabled(viewModel.isSending)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(viewModel.isSending)
        .fullScreenCover(isPresented: $showingScreenshotPreview) {
            screenshotPreview
        }
    }

    private var composeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                intro

                if viewModel.presentation.student.isDemo {
                    notice(
                        icon: "theatermasks",
                        title: "Demotilstand",
                        message: "Du kan prøve hele forløbet. Der sendes ingen data."
                    )
                }

                categoryPicker
                messageEditor
                attachmentCard

                if case .failure(let message) = viewModel.phase {
                    errorCard(message)
                }

                Text("Skærmbilledet kan indeholde personlige oplysninger. Du bestemmer selv, om skærmbillede og diagnostik skal med.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground))
        .disabled(viewModel.isSending)
        .safeAreaInset(edge: .bottom) {
            sendBar
        }
    }

    private var intro: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Hjælp os med at gøre appen bedre")
                    .font(.headline)
                Text("Beskriv problemet eller din idé. Vi læser alt.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Kategori")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(FeedbackCategory.allCases) { category in
                    let selected = viewModel.category == category
                    Button {
                        viewModel.category = category
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: category.systemImage)
                                .font(.title3)
                            Text(category.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(selected ? Color.accentColor : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(
                            selected ? Color.accentColor.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.16), lineWidth: selected ? 1.5 : 1)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if viewModel.message.isEmpty {
                    Text(viewModel.category.prompt)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: Binding(
                    get: { viewModel.message },
                    set: viewModel.updateMessage
                ))
                .focused($messageFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(8)
                .accessibilityLabel("Feedbacktekst")
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            }

            HStack {
                Text("Undlad adgangskoder og andre følsomme oplysninger.")
                Spacer()
                Text("\(viewModel.remainingCharacters)")
                    .monospacedDigit()
                    .accessibilityLabel("\(viewModel.remainingCharacters) tegn tilbage")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var attachmentCard: some View {
        VStack(spacing: 0) {
            if let screenshot = viewModel.presentation.capture.screenshot {
                HStack(spacing: 12) {
                    Button {
                        showingScreenshotPreview = true
                    } label: {
                        Image(uiImage: screenshot)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(.black.opacity(0.55), in: Circle())
                                    .padding(3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Vis skærmbillede")

                    attachmentText(
                        title: "Skærmbillede",
                        subtitle: viewModel.includeScreenshot ? "Medtages" : "Medtages ikke"
                    )
                    Toggle("Skærmbillede", isOn: $viewModel.includeScreenshot)
                        .labelsHidden()
                }
                .padding(14)

            } else {
                HStack(spacing: 12) {
                    attachmentIcon("photo")
                    attachmentText(title: "Skærmbillede", subtitle: "Ikke tilgængeligt")
                    Spacer()
                }
                .padding(14)
                .foregroundStyle(.secondary)
            }

            Divider().padding(.leading, 74)

            if viewModel.presentation.capture.logs.isEmpty {
                HStack(spacing: 12) {
                    attachmentIcon("doc.text")
                    attachmentText(title: "Diagnostik", subtitle: "Ikke tilgængelig")
                    Spacer()
                }
                .padding(14)
                .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        attachmentIcon("doc.text")
                        attachmentText(
                            title: "Diagnostik",
                            subtitle: viewModel.includeLogs ? "Seneste apphændelser medtages" : "Medtages ikke"
                        )
                        Toggle("Diagnostik", isOn: $viewModel.includeLogs)
                            .labelsHidden()
                    }
                    .padding(14)

                    Button {
                        showingDiagnostics.toggle()
                    } label: {
                        HStack {
                            Text(showingDiagnostics ? "Skjul diagnostik" : "Se præcis hvad der sendes")
                            Spacer()
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(showingDiagnostics ? 180 : 0))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    }
                    .buttonStyle(.plain)

                    if showingDiagnostics {
                        ScrollView(.horizontal) {
                            Text(verbatim: viewModel.presentation.capture.logs)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .padding(12)
                        }
                        .frame(maxHeight: 150)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding([.horizontal, .bottom], 12)
                    }
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }

    private var sendBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                messageFocused = false
                Task { await viewModel.submit() }
            } label: {
                HStack(spacing: 9) {
                    if viewModel.isSending {
                        ProgressView().tint(.white)
                        Text("Sender…")
                    } else {
                        Image(systemName: "paperplane.fill")
                        Text(viewModel.presentation.student.isDemo ? "Prøv afsendelse" : "Send feedback")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSubmit)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Kunne ikke sende", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Prøv igen") {
                Task { await viewModel.retry() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func successView(_ success: FeedbackViewModel.Success) -> some View {
        ContentUnavailableView {
            Label(
                success.isDemo ? "Demofeedback klar" : "Feedback sendt",
                systemImage: success.attachmentFailed ? "exclamationmark.circle" : "checkmark.circle.fill"
            )
        } description: {
            if success.isDemo {
                Text("Sådan ser det ud, når feedback er sendt. Ingen data forlod enheden.")
            } else if success.attachmentFailed {
                Text("Din tekst blev sendt, men skærmbilledet kunne ikke vedhæftes.")
            } else {
                Text("Tak, din feedback hjælper os med at gøre BetterLectio bedre.")
            }
        } actions: {
            Button("Luk") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var screenshotPreview: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let screenshot = viewModel.presentation.capture.screenshot {
                    Image(uiImage: screenshot)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Skærmbillede af appen før feedbackvinduet blev åbnet")
                }
            }
            .navigationTitle("Skærmbillede")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Luk") { showingScreenshotPreview = false }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func attachmentText(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func attachmentIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 48, height: 48)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func notice(
        icon: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var isSuccess: Bool {
        if case .success = viewModel.phase { return true }
        return false
    }
}
