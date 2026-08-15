//
//  LoginView.swift
//  BetterLectio
//
//  Created by Elliott Friedrich on 03/02/2026.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    @State private var showSchoolPicker = false

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            if viewModel.showResumeLogin {
                resumeContent
            } else {
                standardContent
            }
        }
        .sheet(isPresented: $showSchoolPicker) {
            SchoolPickerView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showWebView) {
            if let url = viewModel.authenticationURL {
                NavigationView {
                    LectioWebView(
                        url: url,
                        isCallbackURL: { viewModel.authService.isCallbackURL($0) },
                        onAuthComplete: { viewModel.handleWebViewAuthComplete(result: $0) }
                    )
                    .navigationTitle("Log ind med MitID")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Annuller") {
                                viewModel.showWebView = false
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Resume (one-tap same school)

    private var resumeContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.bottom, 8)

                Text("BetterLectio")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                if let hint = viewModel.lastSchoolHint {
                    Text(resumeTitle(for: hint.reason))
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    Text(resumeSubtitle(for: hint.reason))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 60)

            Spacer()

            VStack(spacing: 16) {
                if let errorMessage = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

                if viewModel.isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Godkender…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                Button(action: {
                    viewModel.resumeLastSchoolLogin()
                }) {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                            .font(.title3)
                        Text(resumeCTATitle)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                    .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .disabled(viewModel.isLoading)

                Button("Vælg anden skole") {
                    viewModel.chooseOtherSchool()
                    showSchoolPicker = true
                }
                .font(.body.weight(.medium))
                .disabled(viewModel.isLoading)

                Button("Prøv demo") {
                    viewModel.selectedSchool = .demo
                    viewModel.loginWithMitID(source: "demo")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 24)

            Spacer()

            secureFooter
                .padding(.bottom, 40)
        }
    }

    // MARK: - Standard school pick

    private var standardContent: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                if viewModel.lastSchoolHint != nil {
                    HStack {
                        Button {
                            viewModel.backToResumeLogin()
                        } label: {
                            Label("Tilbage", systemImage: "chevron.left")
                                .font(.body.weight(.medium))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }

                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.bottom, 8)

                Text("BetterLectio")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("Log ind med MitID")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, viewModel.lastSchoolHint == nil ? 60 : 12)

            Spacer()

            VStack(spacing: 24) {
                Button {
                    showSchoolPicker = true
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill((viewModel.selectedSchool == nil ? Color.gray : Color.blue).opacity(0.15))
                                .frame(width: 52, height: 52)
                            Image(systemName: "building.columns.fill")
                                .font(.title2)
                                .foregroundColor(viewModel.selectedSchool == nil ? .secondary : .blue)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Skole")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            Text(viewModel.selectedSchool?.name ?? "Tryk for at vælge")
                                .font(.headline)
                                .foregroundColor(viewModel.selectedSchool == nil ? .secondary : .primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                viewModel.selectedSchool == nil ? Color.secondary.opacity(0.35) : Color.blue,
                                style: StrokeStyle(
                                    lineWidth: viewModel.selectedSchool == nil ? 1 : 2,
                                    dash: viewModel.selectedSchool == nil ? [6, 4] : []
                                )
                            )
                    )
                }
                .buttonStyle(.plain)

                Button(action: {
                    viewModel.loginWithMitID()
                }) {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                            .font(.title3)
                        Text("Log ind med MitID")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        viewModel.selectedSchool == nil ? Color.gray : Color.blue
                    )
                    .cornerRadius(12)
                    .shadow(
                        color: viewModel.selectedSchool == nil ? .clear : Color.blue.opacity(0.3),
                        radius: 10,
                        x: 0,
                        y: 5
                    )
                }
                .disabled(viewModel.selectedSchool == nil || viewModel.isLoading)

                if let errorMessage = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }

                if viewModel.isLoading {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Godkender…")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            secureFooter
                .padding(.bottom, 40)
        }
    }

    private var secureFooter: some View {
        VStack(spacing: 4) {
            Text("Sikker godkendelse via")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption)
                Text("MitID & Lectio")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.blue)
        }
    }

    private var resumeCTATitle: String {
        if let name = viewModel.lastSchoolHint?.schoolName {
            return "Log ind igen, \(name)"
        }
        return "Log ind igen med MitID"
    }

    private func resumeTitle(for reason: LastSchoolReason) -> String {
        switch reason {
        case .sessionExpired:
            return "Din session er udløbet"
        case .loggedOut:
            return "Log ind igen"
        }
    }

    private func resumeSubtitle(for reason: LastSchoolReason) -> String {
        switch reason {
        case .sessionExpired:
            return "Log ind med MitID for at fortsætte."
        case .loggedOut:
            return "Fortsæt med MitID på din skole."
        }
    }
}

// MARK: - Preview

#Preview {
    LoginView(viewModel: AuthenticationViewModel())
}
