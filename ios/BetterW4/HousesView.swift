//
//  HousesView.swift
//  BetterW4
//
//  More ▸ Houses — every boarding house, its rooms, and who lives in each room.
//

import SwiftUI
import UIKit

struct HousesView: View {
    @StateObject private var viewModel = HousesViewModel()
    @StateObject private var directory = DirectoryViewModel()

    var body: some View {
        List {
            if viewModel.houses.isEmpty, !viewModel.isLoading {
                ContentUnavailableView {
                    Label("No houses", systemImage: "building.2")
                } description: {
                    Text(viewModel.errorMessage ?? "W4 did not list any houses.")
                } actions: {
                    Button("Try again") {
                        Task { await viewModel.refresh() }
                    }
                }
            } else {
                ForEach(viewModel.houses) { house in
                    NavigationLink {
                        HouseDetailView(
                            houseId: house.id,
                            viewModel: viewModel,
                            directory: directory
                        )
                    } label: {
                        houseRow(house)
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
        .navigationTitle("Houses")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
        .overlay {
            if viewModel.isLoading, viewModel.houses.isEmpty {
                ProgressView("Loading houses…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
            }
        }
    }

    private func houseRow(_ house: House) -> some View {
        HStack(spacing: 12) {
            if let kind = house.flagKind {
                HouseFlagView(kind: kind)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(house.name)
                    .font(.body.weight(.medium))
                Text(houseSubtitle(house))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func houseSubtitle(_ house: House) -> String {
        if !house.loaded {
            return "Loading rooms…"
        }
        let rooms = house.roomCount
        let people = house.studentCount
        switch (rooms, people) {
        case (0, 0):
            return house.leaders.isEmpty ? "No rooms listed" : "House leader only"
        case (0, _):
            return people == 1 ? "1 student" : "\(people) students"
        default:
            let roomWord = rooms == 1 ? "room" : "rooms"
            let peopleWord = people == 1 ? "student" : "students"
            return "\(rooms) \(roomWord) · \(people) \(peopleWord)"
        }
    }
}

// MARK: - House detail

struct HouseDetailView: View {
    let houseId: String
    @ObservedObject var viewModel: HousesViewModel
    @ObservedObject var directory: DirectoryViewModel

    private var house: House? { viewModel.house(id: houseId) }

    var body: some View {
        Group {
            if let house {
                List {
                    if let kind = house.flagKind {
                        Section {
                            HStack(spacing: 12) {
                                HouseFlagView(kind: kind, width: 44)
                                Text(house.name)
                                    .font(.headline)
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                        }
                    }

                    if !house.leaders.isEmpty {
                        Section("House leader") {
                            ForEach(house.leaders) { resident in
                                residentRow(resident, house: house, room: nil)
                            }
                        }
                    }

                    ForEach(house.rooms) { room in
                        Section {
                            if room.residents.isEmpty {
                                Text("No one listed")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(room.residents) { resident in
                                    residentRow(resident, house: house, room: room)
                                }
                            }
                        } header: {
                            Text(room.name)
                        } footer: {
                            if !room.residents.isEmpty {
                                Text(
                                    room.residents.count == 1
                                        ? "1 student"
                                        : "\(room.residents.count) students"
                                )
                            }
                        }
                    }

                    if !house.unassigned.isEmpty {
                        Section("No room") {
                            ForEach(house.unassigned) { resident in
                                residentRow(resident, house: house, room: nil)
                            }
                        }
                    }

                    if house.loaded,
                       house.rooms.isEmpty,
                       house.unassigned.isEmpty,
                       house.leaders.isEmpty {
                        Section {
                            W4SurfaceEmptyRow(
                                text: "No one is listed in this house.",
                                systemImage: "person.2.slash"
                            )
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(house?.flaggedName ?? "House")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if let house, !house.loaded, house.rooms.isEmpty {
                ProgressView("Loading rooms…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
            }
        }
    }

    private func residentRow(
        _ resident: HouseResident,
        house: House,
        room: HouseRoom?
    ) -> some View {
        NavigationLink {
            StudentProfileView(
                person: resident.person,
                placement: HousePlacement(house: house, room: room, resident: resident),
                directory: directory
            )
        } label: {
            HStack(spacing: 12) {
                W4AvatarView(
                    url: resident.person.photoURL,
                    name: resident.person.displayName,
                    size: 44
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(resident.person.displayName)
                        .font(.body.weight(.medium))
                    if let detail = resident.detailLine {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

#Preview("Houses") {
    NavigationStack {
        HousesView()
    }
}
