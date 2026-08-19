//
//  OnDutyView.swift
//  BetterW4
//
//  Who is on duty today — photo, role, and a tappable phone number so a student
//  can actually reach them.
//

import SwiftUI
import UIKit

struct OnDutyView: View {
    @StateObject private var viewModel = OnDutyViewModel()

    var body: some View {
        List {
            if let dateLabel = viewModel.dateLabel {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                        Text(dateLabel)
                            .font(.headline)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("On duty \(dateLabel)")
                }
            }

            if viewModel.groups.isEmpty, viewModel.snapshot != nil {
                Section {
                    W4SurfaceEmptyRow(
                        text: "Nobody is listed as on duty today.",
                        systemImage: "person.badge.shield.checkmark"
                    )
                }
            } else {
                ForEach(viewModel.groups) { group in
                    Section {
                        ForEach(group.people) { person in
                            OnDutyPersonCard(person: person)
                        }
                    } header: {
                        Text(group.role)
                    }
                }
            }

            if !viewModel.upcoming.isEmpty {
                Section {
                    ForEach(viewModel.upcoming) { day in
                        OnDutyUpcomingRow(day: day)
                    }
                } header: {
                    Text("Coming up")
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
        .navigationTitle("On duty")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
        .overlay { overlay }
    }

    @ViewBuilder
    private var overlay: some View {
        if viewModel.isLoading, viewModel.snapshot == nil {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        } else if let message = viewModel.errorMessage, viewModel.snapshot == nil {
            ContentUnavailableView {
                Label("On duty unavailable", systemImage: "person.badge.shield.checkmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") {
                    Task { await viewModel.refresh() }
                }
            }
            .background(.background)
        }
    }
}

// MARK: - Person card

private struct OnDutyPersonCard: View {
    let person: OnDutyPerson
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                W4AvatarView(url: person.photoURL, name: person.name, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let location = person.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if person.hasContact {
                VStack(spacing: 8) {
                    if let phone = person.phone, let url = OnDutyContact.telephoneURL(phone) {
                        contactButton(
                            title: "Call",
                            detail: phone,
                            systemImage: "phone.fill",
                            tint: Color.green
                        ) {
                            openURL(url)
                        }
                    }
                    if let email = person.email, let url = OnDutyContact.mailtoURL(email) {
                        contactButton(
                            title: "Email",
                            detail: email,
                            systemImage: "envelope.fill",
                            tint: Color.accentColor
                        ) {
                            openURL(url)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            if let phone = person.phone, !phone.isEmpty {
                if let url = OnDutyContact.telephoneURL(phone) {
                    Button { openURL(url) } label: {
                        Label("Call \(phone)", systemImage: "phone")
                    }
                }
                if let url = OnDutyContact.smsURL(phone) {
                    Button { openURL(url) } label: {
                        Label("Send message", systemImage: "message")
                    }
                }
                Button {
                    UIPasteboard.general.string = phone
                } label: {
                    Label("Copy phone number", systemImage: "doc.on.doc")
                }
            }
            if let email = person.email, !email.isEmpty {
                Button {
                    UIPasteboard.general.string = email
                } label: {
                    Label("Copy email", systemImage: "doc.on.doc")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func contactButton(
        title: String,
        detail: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(detail)")
    }
}

// MARK: - Upcoming

private struct OnDutyUpcomingRow: View {
    let day: OnDutyDay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(OnDutyViewModel.caption(for: day))
                .font(.subheadline.weight(.semibold))
            ForEach(day.groups) { group in
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(group.people) { person in
                        HStack(spacing: 8) {
                            Text(person.name)
                            if let phone = person.phone, let url = OnDutyContact.telephoneURL(phone) {
                                Spacer(minLength: 8)
                                Link(destination: url) {
                                    Label(phone, systemImage: "phone.fill")
                                        .labelStyle(.titleAndIcon)
                                        .font(.caption)
                                }
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview("On duty") {
    NavigationStack {
        OnDutyView()
    }
}
