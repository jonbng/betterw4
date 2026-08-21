//
//  LoginView.swift
//  BetterW4
//
//  W4's native sign-in: username + password, then a one-time code when W4 challenges the
//  device. No school picker, no WebView, no MitID.
//

import SwiftUI
import UIKit

struct LoginView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var username = ""
    @State private var password = ""
    @State private var oneTimeCode = ""
    @State private var isPasswordVisible = false
    @State private var lastPasteboardChangeCount = UIPasteboard.general.changeCount
    @State private var lastConsumedClipboardCode: String?

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case username
        case password
        case oneTimeCode
    }

    private var isVerifyingCode: Bool { viewModel.otpChallenge != nil }

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    header

                    if isVerifyingCode {
                        oneTimeCodeCard
                    } else {
                        credentialsCard
                    }

                    errorBanner
                    footer
                }
                .padding(.horizontal, 24)
                .padding(.top, 48)
                .padding(.bottom, 40)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(.default, value: isVerifyingCode)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onChange(of: isVerifyingCode) { _, showingCode in
            oneTimeCode = ""
            lastConsumedClipboardCode = nil
            if showingCode {
                // The password is no longer needed: the challenge carries the half-finished
                // session. Drop it rather than keep it in memory behind the code field.
                password = ""
                focusedField = .oneTimeCode
                // Snapshot without reading so we only auto-fill after they copy a new code.
                lastPasteboardChangeCount = UIPasteboard.general.changeCount
            } else {
                focusedField = nil
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consumeClipboardIfNeeded() }
        }
        .onChange(of: username) { _, value in
            let cleaned = W4Username.normalize(value)
            if cleaned != value { username = cleaned }
        }
        .onChange(of: oneTimeCode) { _, value in
            let cleaned = W4OtpCode.sanitizeInput(value)
            if cleaned != value { oneTimeCode = cleaned }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            consumeClipboardIfNeeded()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 84, height: 84)
                Text("W4")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(Color.accentColor)
            }
            .accessibilityHidden(true)

            Text("BetterW4")
                .font(.largeTitle.weight(.bold))

            Text("Sign in with your \(AuthenticationService.collegeName) W4 account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Username + password

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Username")

                TextField("nc26abcd", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.asciiCapable)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .password }
                    .padding(14)
                    .background(fieldBackground)
                    .accessibilityLabel("Username")
                    .accessibilityHint("Your UWC id. It looks like n c 2 6 a b c d.")

                Text("Your UWC id — it looks like nc26abcd.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Password")

                HStack(spacing: 8) {
                    Group {
                        if isPasswordVisible {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit { Task { await submitCredentials() } }
                    .accessibilityLabel("Password")

                    Button {
                        isPasswordVisible.toggle()
                        focusedField = .password
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .imageScale(.medium)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                }
                .padding(14)
                .background(fieldBackground)
            }

            primaryButton(
                title: "Log in",
                busyTitle: "Signing in…",
                isEnabled: canSubmitCredentials
            ) {
                await submitCredentials()
            }

            Button("Try demo") {
                Task { await viewModel.enterDemoMode() }
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .disabled(viewModel.isSubmitting)
            .accessibilityHint("Explore the app with sample data. No W4 account needed.")
        }
    }

    // MARK: - One-time code

    private var oneTimeCodeCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Two-factor authentication")
                    .font(.headline)
                Text("W4 emailed an 8-character code. Paste it here, or open Gmail to copy it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("One-time code")

                TextField("Verification code", text: $oneTimeCode)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .font(.title3.monospaced())
                    .submitLabel(.go)
                    .focused($focusedField, equals: .oneTimeCode)
                    .onSubmit { Task { await submitOneTimeCode() } }
                    .padding(14)
                    .background(fieldBackground)
                    .accessibilityLabel("One-time code")
                    .accessibilityHint("The 8-character code W4 emailed you. It includes letters.")
            }

            primaryButton(
                title: "Verify",
                busyTitle: "Verifying…",
                isEnabled: canSubmitCode
            ) {
                await submitOneTimeCode()
            }

            Button {
                openGmail()
            } label: {
                Label("Open Gmail", systemImage: "envelope")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(viewModel.isSubmitting)
            .accessibilityHint("Opens Gmail so you can copy the W4 code.")

            Text("Copy the 8-character code, then return here. We’ll paste it and sign you in.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Cancel") {
                viewModel.cancelOTP()
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity)
            .disabled(viewModel.isSubmitting)
            .accessibilityHint("Go back to the username and password form.")
        }
    }

    // MARK: - Shared pieces

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(UIColor.secondarySystemGroupedBackground))
    }

    private func primaryButton(
        title: String,
        busyTitle: String,
        isEnabled: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 10) {
                if viewModel.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(viewModel.isSubmitting ? busyTitle : title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityValue(viewModel.isSubmitting ? busyTitle : "")
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = viewModel.errorMessage, !message.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red.opacity(0.12))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Error")
            .accessibilityValue(message)
        }
    }

    private var footer: some View {
        Label("Your password goes only to w4.uwcrcn.no", systemImage: "lock.shield.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private var canSubmitCredentials: Bool {
        !viewModel.isSubmitting
            && !W4Username.normalize(username).isEmpty
            && !password.isEmpty
    }

    private var canSubmitCode: Bool {
        !viewModel.isSubmitting
            && !oneTimeCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitCredentials() async {
        let cleaned = W4Username.normalize(username)
        if cleaned != username { username = cleaned }
        guard canSubmitCredentials else { return }
        focusedField = nil
        await viewModel.logIn(username: cleaned, password: password)
    }

    private func submitOneTimeCode(_ code: String? = nil) async {
        let value = W4OtpCode.sanitizeInput(code ?? oneTimeCode)
        guard !viewModel.isSubmitting, !value.isEmpty else { return }
        oneTimeCode = value
        focusedField = nil
        await viewModel.submitOTP(code: value)
        // Still on the code step ⇒ W4 rejected it. Clear the field for the next attempt.
        if viewModel.otpChallenge != nil {
            oneTimeCode = ""
            focusedField = .oneTimeCode
        }
    }

    private func consumeClipboardIfNeeded() {
        guard isVerifyingCode, !viewModel.isSubmitting, scenePhase == .active else { return }
        let changeCount = UIPasteboard.general.changeCount
        guard changeCount != lastPasteboardChangeCount else { return }
        guard UIPasteboard.general.hasStrings else {
            lastPasteboardChangeCount = changeCount
            return
        }
        // Don't burn the change-count if the pasteboard is unreadable in the background;
        // we'll try again the next time the scene is active.
        guard let raw = UIPasteboard.general.string else { return }
        lastPasteboardChangeCount = changeCount
        guard let code = W4OtpCode.extract(raw), code != lastConsumedClipboardCode else { return }
        if !oneTimeCode.isEmpty && oneTimeCode != code { return }
        lastConsumedClipboardCode = code
        oneTimeCode = code
        Task { await submitOneTimeCode(code) }
    }

    private func openGmail() {
        let gmail = URL(string: "googlegmail://")!
        let web = URL(string: "https://mail.google.com")!
        if UIApplication.shared.canOpenURL(gmail) {
            UIApplication.shared.open(gmail)
        } else {
            UIApplication.shared.open(web)
        }
    }
}

// MARK: - Preview

#Preview {
    LoginView(viewModel: AuthenticationViewModel())
}
