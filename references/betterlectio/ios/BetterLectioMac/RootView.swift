//
//  RootView.swift
//  BetterLectioMac
//
//  Post-onboarding shell. A sidebar split view is the conventional shape for a
//  small Mac utility app — a tab bar is not.
//

import SwiftUI

struct RootView: View {
    enum Section: String, CaseIterable, Identifiable {
        case status, help, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .status: "Status"
            case .help: "Hjælp"
            case .about: "Om"
            }
        }

        var icon: String {
            switch self {
            case .status: "checkmark.seal"
            case .help: "questionmark.circle"
            case .about: "info.circle"
            }
        }
    }

    @State private var selection: Section = .status

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            Group {
                switch selection {
                case .status: StatusView()
                case .help: HelpView()
                case .about: AboutView()
                }
            }
            .navigationTitle(selection.title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BL.Palette.windowBackground)
        }
    }
}
