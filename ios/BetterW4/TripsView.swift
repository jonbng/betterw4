//
//  TripsView.swift
//  BetterW4
//
//  My trips + My travel forms (features.md §1.9, ui.md §4.12 / §4.13).
//
//  Trips carry a status pill from W4's own ladder — Planning → Pending confirmation → Approved |
//  Cancelled — and the status *text W4 printed* is what the pill shows; the parsed enum only
//  chooses the colour, so a status vocabulary we have never seen still renders correctly.
//
//  Read-only. "Plan new trip" and each travel form open the W4 page in the in-app browser with the
//  session cookie, because no capture of either form exists to build a POST from.
//

import SwiftUI

struct TripsView: View {

    @StateObject private var viewModel = TripsViewModel()
    @State private var sheetTarget: W4SurfaceSheetTarget?

    init() {}

    var body: some View {
        List {
            tripsSection
            travelSection
            contactsSection

            if viewModel.freshness != nil {
                Section {
                    W4SurfaceFreshnessLabel(freshness: viewModel.freshness)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Trips")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
        .overlay { overlay }
        .toolbar {
            if viewModel.canPlanNewTrip || viewModel.tripList != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheetTarget = W4SurfaceSheetTarget(
                            title: "Plan new trip",
                            url: viewModel.planNewTripURL
                        )
                    } label: {
                        Label("Plan new trip", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $sheetTarget) { target in
            W4SurfacePageSheet(target: target)
        }
    }

    // MARK: - States

    @ViewBuilder
    private var overlay: some View {
        if viewModel.isLoading, viewModel.tripList == nil, viewModel.travelPage == nil {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        } else if let message = viewModel.errorMessage,
                  viewModel.tripList == nil, viewModel.travelPage == nil {
            ContentUnavailableView {
                Label("Trips unavailable", systemImage: "suitcase")
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

    // MARK: - Trips

    @ViewBuilder
    private var tripsSection: some View {
        Section {
            if viewModel.trips.isEmpty {
                W4SurfaceEmptyRow(text: viewModel.tripsEmptyMessage, systemImage: "suitcase")
            } else {
                ForEach(viewModel.trips) { trip in
                    tripRow(trip)
                }
            }
        } header: {
            Text("My trips")
        } footer: {
            if viewModel.hasMoreTrips {
                Text("W4 has more trips than this page shows. Open the trip page to see them all.")
            }
        }
    }

    @ViewBuilder
    private func tripRow(_ trip: Trip) -> some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(trip.name)
                    .font(.headline)
                Spacer(minLength: 8)
                TripStatusChip(trip: trip)
            }
            if let destination = trip.destination, !destination.isEmpty {
                Label(destination, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let range = TripsViewModel.dateRange(for: trip) {
                Label(range, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if let type = trip.type, !type.isEmpty {
                    Text(type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let participants = trip.participantsLabel, !participants.isEmpty {
                    Label(participants, systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)

        if let url = viewModel.url(for: trip) {
            Button {
                sheetTarget = W4SurfaceSheetTarget(title: trip.name, url: url)
            } label: {
                content.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    // MARK: - Travel forms

    @ViewBuilder
    private var travelSection: some View {
        Section {
            if viewModel.travelForms.isEmpty {
                W4SurfaceEmptyRow(text: viewModel.travelEmptyMessage, systemImage: "airplane")
            } else {
                ForEach(viewModel.travelForms) { form in
                    travelRow(form)
                }
            }
            if let url = viewModel.manageContactsURL {
                Button {
                    sheetTarget = W4SurfaceSheetTarget(title: viewModel.manageContactsLabel, url: url)
                } label: {
                    Label(viewModel.manageContactsLabel, systemImage: "person.crop.circle.badge.plus")
                }
            }
        } header: {
            Text("My travel forms")
        } footer: {
            Text("Travel forms are filled in on W4. Opening one signs you in automatically.")
        }
    }

    @ViewBuilder
    private func travelRow(_ form: TravelForm) -> some View {
        let content = HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(form.displayName)
                if let journey = form.journey, journey.displayName != form.displayName {
                    Text(journey.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let status = form.statusLabel, !status.isEmpty {
                Text(status)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }

        if let url = viewModel.url(for: form) {
            Button {
                sheetTarget = W4SurfaceSheetTarget(title: form.displayName, url: url)
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    // MARK: - Travel contacts

    @ViewBuilder
    private var contactsSection: some View {
        if !viewModel.contacts.isEmpty {
            Section("Travel contacts") {
                ForEach(viewModel.contacts) { contact in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(contact.name)
                            if let relation = contact.relation, !relation.isEmpty {
                                Text(relation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let phone = contact.phone, !phone.isEmpty {
                            Text(phone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let email = contact.email, !email.isEmpty {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

// MARK: - Status pill

/// The trip status, in W4's own words, coloured by the parsed ladder position.
struct TripStatusChip: View {
    let trip: Trip

    var body: some View {
        Label(trip.statusDisplay, systemImage: TripsViewModel.symbol(for: trip.status))
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(TripsViewModel.tint(for: trip.status).opacity(0.14), in: Capsule())
            .foregroundStyle(TripsViewModel.tint(for: trip.status))
            .lineLimit(1)
    }
}
