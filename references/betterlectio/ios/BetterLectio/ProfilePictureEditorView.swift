import Combine
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class ProfilePictureEditorViewModel: ObservableObject {
    @Published var state: ProfilePictureState?
    @Published var selection: PhotosPickerItem?
    @Published var previewImage: UIImage?
    @Published var cropSourceImage: UIImage?
    @Published var preparedPicture: PreparedProfilePicture?
    @Published var isLoading = false
    @Published var isPreparing = false
    @Published var isUploading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    let student: Student
    private let service: any ProfilePictureServing

    init(student: Student, service: any ProfilePictureServing = SupabaseProfilePictureService.shared) {
        self.student = student
        self.service = service
    }

    var canChoose: Bool {
        guard let state else { return false }
        return state.unlocked && !state.isPending && state.canSubmit && !isUploading
    }

    func refresh() async {
        if student.isDemo {
            state = .demo
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            state = try await service.state(studentID: student.studentId)
        } catch {
            errorMessage = String(localized: "profile_picture.status_error", defaultValue: "Kunne ikke hente status for profilbilledet.")
        }
    }

    func prepareSelection() async {
        guard let selection else { return }
        isPreparing = true
        errorMessage = nil
        preparedPicture = nil
        previewImage = nil
        defer { isPreparing = false }
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else {
                throw ProfilePictureServiceError.invalidFile
            }
            let image = try await Task.detached(priority: .userInitiated) {
                guard let image = UIImage(data: data) else {
                    throw ProfilePictureServiceError.invalidFile
                }
                return image.normalizedAndDownsampled(maxDimension: 4_000)
            }.value
            try Task.checkCancellation()
            cropSourceImage = image
        } catch {
            errorMessage = String(localized: "profile_picture.invalid_selection", defaultValue: "Billedet kunne ikke bruges. Vælg et JPEG-, PNG- eller WebP-billede på højst 5 MB.")
        }
    }

    func acceptCrop(_ source: UIImage, zoom: CGFloat, offset: CGSize, displaySize: CGFloat) async {
        isPreparing = true
        defer { isPreparing = false }
        let prepared = await Task.detached(priority: .userInitiated) {
            guard let image = source.croppedSquare(
                zoom: zoom,
                displayOffset: offset,
                displaySize: displaySize
            ), let jpeg = image.jpegUnderMaximumBytes(ProfilePictureValidator.maximumBytes) else {
                return nil
            }
            return (image, jpeg)
        }.value
        guard !Task.isCancelled else { return }
        guard let prepared else {
            errorMessage = String(localized: "profile_picture.compression_error", defaultValue: "Billedet kunne ikke komprimeres. Vælg et andet billede.")
            return
        }
        let picture = PreparedProfilePicture(data: prepared.1, mimeType: "image/jpeg", fileExtension: "jpg")
        do {
            try ProfilePictureValidator.validate(picture)
        } catch {
            errorMessage = String(localized: "profile_picture.invalid_payload", defaultValue: "Det beskårne billede kunne ikke klargøres til upload.")
            return
        }
        previewImage = prepared.0
        preparedPicture = picture
        cropSourceImage = nil
    }

    func submit() async {
        guard let preparedPicture else { return }
        if student.isDemo {
            successMessage = String(localized: "profile_picture.demo_success", defaultValue: "Demo: Billedet ville nu blive sendt til godkendelse.")
            return
        }
        isUploading = true
        errorMessage = nil
        successMessage = nil
        defer { isUploading = false }
        do {
            let result = try await service.submit(student: student, picture: preparedPicture)
            if result.ok {
                successMessage = String(localized: "profile_picture.submit_success", defaultValue: "Billedet er sendt til godkendelse. Dit nuværende billede forbliver synligt imens.")
                UIAccessibility.post(notification: .announcement, argument: successMessage)
                self.preparedPicture = nil
                previewImage = nil
                selection = nil
                await refresh()
                await ProfilePictureReviewMonitor.shared.refresh(for: student)
            } else {
                errorMessage = message(for: result.code)
            }
        } catch {
            if let serviceError = error as? ProfilePictureServiceError {
                switch serviceError {
                case .invalidFile:
                    errorMessage = String(localized: "profile_picture.invalid_payload", defaultValue: "Det beskårne billede kunne ikke klargøres til upload.")
                case .notAuthenticated:
                    errorMessage = String(localized: "profile_picture.unauthorized", defaultValue: "Din session er udløbet. Log ind igen og prøv på ny.")
                case .notConfigured, .invalidResponse:
                    errorMessage = String(localized: "profile_picture.submit_error", defaultValue: "Billedet kunne ikke sendes. Prøv igen.")
                }
            } else {
                errorMessage = String(localized: "profile_picture.upload_error", defaultValue: "Upload mislykkedes. Kontrollér forbindelsen og prøv igen.")
            }
        }
    }

    private func message(for code: String?) -> String {
        switch code {
        case "not_unlocked": return String(localized: "profile_picture.not_unlocked", defaultValue: "Inviter tre klassekammerater for at låse funktionen op.")
        case "pending_exists": return String(localized: "profile_picture.pending_exists", defaultValue: "Du har allerede et billede, der afventer godkendelse.")
        case "cooldown": return String(localized: "profile_picture.cooldown_error", defaultValue: "Der er endnu ikke gået tre måneder siden sidste ændring.")
        case "invalid_file": return String(localized: "profile_picture.invalid_file", defaultValue: "Billedtypen eller filstørrelsen understøttes ikke.")
        case "unauthorized": return String(localized: "profile_picture.unauthorized", defaultValue: "Din session er udløbet. Log ind igen og prøv på ny.")
        case "feature_disabled": return String(localized: "profile_picture.disabled", defaultValue: "Profilbilleder er midlertidigt slået fra. Prøv igen senere.")
        default: return String(localized: "profile_picture.submit_error", defaultValue: "Billedet kunne ikke sendes. Prøv igen.")
        }
    }
}

struct ProfilePictureEditorView: View {
    @StateObject private var viewModel: ProfilePictureEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(student: Student) {
        _viewModel = StateObject(wrappedValue: ProfilePictureEditorViewModel(student: student))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    avatarPreview
                    statusCard
                    pickerCard
                    messages
                }
                .padding(16)
            }
            .refreshable { await viewModel.refresh() }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(localized: "profile_picture.title", defaultValue: "Skift profilbillede"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close", defaultValue: "Luk")) { dismiss() }
                }
            }
            .task { await viewModel.refresh() }
            .onChange(of: viewModel.selection) { _, _ in
                Task { await viewModel.prepareSelection() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await viewModel.refresh() } }
            }
            .sheet(isPresented: cropSheetBinding) {
                if let image = viewModel.cropSourceImage {
                    ProfilePictureCropView(image: image) { zoom, offset, displaySize in
                        Task {
                            await viewModel.acceptCrop(
                                image,
                                zoom: zoom,
                                offset: offset,
                                displaySize: displaySize
                            )
                        }
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var cropSheetBinding: Binding<Bool> {
        Binding(get: { viewModel.cropSourceImage != nil }, set: { if !$0 { viewModel.cropSourceImage = nil } })
    }

    @ViewBuilder
    private var avatarPreview: some View {
        VStack(spacing: 10) {
            if let image = viewModel.previewImage {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 132, height: 132).clipShape(Circle())
            } else if let url = viewModel.state?.currentImageURL {
                PublicProfileAvatarView(
                    url: url,
                    name: viewModel.student.name ?? String(localized: "profile_picture.student", defaultValue: "Elev"),
                    size: 132,
                    lectioFallbackURL: lectioFallbackURL
                )
            } else {
                LectioAvatarView(
                    url: lectioFallbackURL,
                    name: viewModel.student.name ?? String(localized: "profile_picture.student", defaultValue: "Elev"),
                    size: 132
                )
            }
            Text(viewModel.previewImage == nil
                 ? String(localized: "profile_picture.current", defaultValue: "Nuværende profilbillede")
                 : String(localized: "profile_picture.preview", defaultValue: "Forhåndsvisning"))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
    }

    @ViewBuilder
    private var statusCard: some View {
        if viewModel.isLoading && viewModel.state == nil {
            ProgressView(String(localized: "profile_picture.loading", defaultValue: "Henter status…"))
                .frame(maxWidth: .infinity).padding(20)
        } else if viewModel.state == nil, let error = viewModel.errorMessage {
            ContentUnavailableView {
                Label(String(localized: "profile_picture.status_unavailable", defaultValue: "Status kunne ikke hentes"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button(String(localized: "common.retry", defaultValue: "Prøv igen")) { Task { await viewModel.refresh() } }
            }
        } else if let state = viewModel.state {
            VStack(alignment: .leading, spacing: 8) {
                if !state.unlocked {
                    Label(String(localized: "profile_picture.locked", defaultValue: "Profilbilledet er låst"), systemImage: "lock.fill")
                    Text(String(format: String(localized: "profile_picture.progress", defaultValue: "%1$d/%2$d invitationer gennemført."), state.referralConversions, state.unlockThreshold))
                        .monospacedDigit()
                    if let url = ReferralLink.shareURL(studentID: viewModel.student.studentId) {
                        ShareLink(item: url, message: Text(String(localized: "profile_picture.invite_message", defaultValue: "Prøv BetterLectio. Lectio der faktisk virker på mobilen."))) {
                            Label(String(localized: "profile_picture.invite", defaultValue: "Inviter klassekammerater"), systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if state.isPending {
                    Label(String(localized: "profile_picture.pending", defaultValue: "Afventer godkendelse"), systemImage: "clock.fill").foregroundStyle(.orange)
                    Text(String(localized: "profile_picture.pending_body", defaultValue: "Dit nuværende billede forbliver synligt, mens vi gennemgår det nye."))
                } else if state.wasRejected {
                    Label(String(localized: "profile_picture.rejected", defaultValue: "Billedet blev afvist"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(rejectionDescription(state)).font(.subheadline)
                } else if !state.canSubmit, let date = formattedDate(state.nextEligibleAt) {
                    Label(String(format: String(localized: "profile_picture.next_change", defaultValue: "Næste ændring: %@"), date), systemImage: "calendar.badge.clock")
                } else {
                    Label(String(localized: "profile_picture.ready", defaultValue: "Klar til et nyt billede"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if state.isPending || state.wasRejected || !state.canSubmit {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Label(String(localized: "profile_picture.refresh", defaultValue: "Opdater status"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isLoading)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var pickerCard: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $viewModel.selection, matching: .images) {
                Label(String(localized: "profile_picture.choose", defaultValue: "Vælg fra Fotos"), systemImage: "photo.on.rectangle.angled")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canChoose || viewModel.isPreparing)

            if viewModel.isPreparing { ProgressView(String(localized: "profile_picture.preparing", defaultValue: "Forbereder billede…")) }

            Button {
                Task { await viewModel.submit() }
            } label: {
                if viewModel.isUploading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                } else {
                    Text(String(localized: "profile_picture.submit", defaultValue: "Send til godkendelse")).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.preparedPicture == nil || viewModel.isUploading)

            Text(String(localized: "profile_picture.format_help", defaultValue: "JPEG, PNG eller WebP · højst 5 MB. Alle billeder gennemgås før offentliggørelse."))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(String(localized: "profile_picture.safety_help", defaultValue: "Brug et tydeligt billede af dig selv. Undgå andre personer, kontaktoplysninger og stødende indhold. Efter godkendelse kan billedet ændres igen om tre måneder."))
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var messages: some View {
        if let error = viewModel.errorMessage {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .font(.subheadline).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
        }
        if let success = viewModel.successMessage {
            Label(success, systemImage: "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(.green).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rejectionDescription(_ state: ProfilePictureState) -> String {
        let description = [localizedRejectionReason(state.submission?.rejectionReason), state.submission?.reviewNote]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return description.isEmpty
            ? String(localized: "profile_picture.rejection_fallback", defaultValue: "Vælg et andet billede og prøv igen.")
            : description
    }

    private func localizedRejectionReason(_ reason: String?) -> String? {
        switch reason {
        case "inappropriate": return String(localized: "profile_picture.reason_inappropriate", defaultValue: "Upassende indhold")
        case "privacy_or_impersonation": return String(localized: "profile_picture.reason_privacy", defaultValue: "Privatliv eller efterligning")
        case "unsuitable": return String(localized: "profile_picture.reason_unsuitable", defaultValue: "Billedet egner sig ikke som profilbillede")
        case "other": return String(localized: "profile_picture.reason_other", defaultValue: "Billedet opfylder ikke retningslinjerne")
        default: return reason
        }
    }

    private func formattedDate(_ value: String?) -> String? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else { return nil }
        return date.formatted(date: .long, time: .omitted)
    }

    private var lectioFallbackURL: URL? {
        guard let pictureID = viewModel.student.pictureId, !pictureID.isEmpty else { return nil }
        return URL(string: "https://www.lectio.dk/lectio/\(viewModel.student.gymId)/GetImage.aspx?pictureid=\(pictureID)&fullsize=1")
    }
}

private struct ProfilePictureCropView: View {
    let image: UIImage
    let onConfirm: (CGFloat, CGSize, CGFloat) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    private let cropSize: CGFloat = 300

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                ZStack {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: cropSize, height: cropSize)
                        .scaleEffect(zoom).offset(offset)
                }
                    .frame(width: cropSize, height: cropSize)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                    .shadow(radius: 18, y: 8)
                    .gesture(
                        DragGesture()
                            .onChanged { value in offset = clamped(dragStart.adding(value.translation)) }
                            .onEnded { _ in dragStart = offset }
                    )
                    .accessibilityLabel(String(localized: "profile_picture.crop_accessibility", defaultValue: "Beskæring af profilbillede"))

                VStack(spacing: 8) {
                    Label(String(localized: "profile_picture.zoom", defaultValue: "Zoom"), systemImage: "plus.magnifyingglass").font(.subheadline)
                    Slider(value: $zoom, in: 1...3)
                        .onChange(of: zoom) { _, _ in
                            offset = clamped(offset)
                            dragStart = offset
                        }
                        .accessibilityLabel(String(localized: "profile_picture.zoom_accessibility", defaultValue: "Zoom profilbillede"))
                }
                .frame(maxWidth: 320)
                Spacer()
            }
            .padding(20)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(localized: "profile_picture.crop_title", defaultValue: "Tilpas billede"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "common.cancel", defaultValue: "Annuller")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "profile_picture.use_image", defaultValue: "Brug billede")) {
                        onConfirm(zoom, offset, cropSize)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func clamped(_ proposed: CGSize) -> CGSize {
        let shortest = max(1, min(image.size.width, image.size.height))
        let maxX = max(0, (cropSize * image.size.width / shortest * zoom - cropSize) / 2)
        let maxY = max(0, (cropSize * image.size.height / shortest * zoom - cropSize) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}

private extension CGSize {
    func adding(_ other: CGSize) -> CGSize {
        CGSize(width: width + other.width, height: height + other.height)
    }
}

private extension UIImage {
    nonisolated func croppedSquare(zoom: CGFloat, displayOffset: CGSize, displaySize: CGFloat) -> UIImage? {
        guard let cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let side = min(width, height) / max(1, zoom)
        let shiftX = displayOffset.width / displaySize * side
        let shiftY = displayOffset.height / displaySize * side
        let x = min(max(0, width / 2 - side / 2 - shiftX), width - side)
        let y = min(max(0, height / 2 - side / 2 - shiftY), height - side)
        guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: side, height: side)) else { return nil }
        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
            .normalizedAndDownsampled(maxDimension: 1_600)
    }

    nonisolated func normalizedAndDownsampled(maxDimension: CGFloat) -> UIImage {
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    nonisolated func jpegUnderMaximumBytes(_ maximum: Int) -> Data? {
        var quality: CGFloat = 0.9
        while quality >= 0.35 {
            if let data = jpegData(compressionQuality: quality), data.count <= maximum { return data }
            quality -= 0.1
        }
        return nil
    }
}
