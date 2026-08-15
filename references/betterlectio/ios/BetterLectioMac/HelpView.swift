//
//  HelpView.swift
//  BetterLectioMac
//
//  Troubleshooting for the handful of things that actually go wrong with a Safari
//  Web Extension: it isn't visible, permissions reset, or Lectio logs you out.
//

import SwiftUI

struct HelpView: View {
    @EnvironmentObject private var extensionState: ExtensionState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BL.Space.l) {
                ForEach(Self.topics) { topic in
                    FAQItem(topic: topic)
                }

                contactCard
            }
            .frame(maxWidth: 620)
            .padding(BL.Space.xl)
            .frame(maxWidth: .infinity)
        }
    }

    private var contactCard: some View {
        HStack(spacing: BL.Space.m) {
            IconChip(systemName: "ladybug.fill", tint: .pink)

            VStack(alignment: .leading, spacing: 2) {
                Text("Noget virker ikke?")
                    .font(.headline)
                Text("Skriv til os på GitHub. Beskriv gerne hvilken side i Lectio det drejer sig om.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: BL.Space.m)

            Button("Rapportér") {
                NSWorkspace.shared.open(BL.feedbackURL)
            }
            .controlSize(.large)
        }
        .padding(BL.Space.m)
        .blCard()
    }

    // MARK: - Content

    struct Topic: Identifiable {
        let id = UUID()
        let icon: String
        let question: String
        let answer: String
    }

    static let topics: [Topic] = [
        Topic(
            icon: "eye.slash",
            question: "Jeg kan ikke se BetterLectio i Safari",
            answer: """
            Åbn Safari → Indstillinger → Udvidelser og sæt flueben ved BetterLectio.

            Kan du slet ikke finde den i listen, ligger appen sandsynligvis ikke i \
            mappen Programmer. Safari finder kun udvidelser i apps, der er flyttet \
            til Programmer. Træk BetterLectio derover og prøv igen.
            """
        ),
        Topic(
            icon: "lock.rotation",
            question: "Den spørger om adgang til lectio.dk hver gang",
            answer: """
            Du har givet adgang for én dag i stedet for permanent. Klik på \
            BetterLectio-ikonet i Safaris værktøjslinje og vælg \
            “Tillad altid på lectio.dk”.

            Du kan også styre det under Safari → Indstillinger → Udvidelser → \
            BetterLectio, hvor lectio.dk skal stå til “Tillad”.
            """
        ),
        Topic(
            icon: "person.crop.circle.badge.questionmark",
            question: "Jeg bliver logget ud af Lectio",
            answer: """
            BetterLectio holder din Lectio-session i live, men Lectio selv logger \
            dig ud efter længere tids inaktivitet. Det kan vi ikke omgå.

            Sker det hele tiden, så slå udvidelsen fra et øjeblik og se, om \
            problemet følger med. Gør det ikke, vil vi meget gerne høre om det.
            """
        ),
        Topic(
            icon: "hand.raised.fill",
            question: "Hvorfor skal den have adgang til lectio.dk?",
            answer: """
            BetterLectio bygger sin brugerflade oven på Lectios egne sider. Uden \
            adgang til lectio.dk kan udvidelsen ikke se siden og dermed ikke gøre noget.

            Den kører udelukkende på lectio.dk, og dit Lectio-login forlader aldrig \
            din maskine. Vi ser hverken dit brugernavn eller din adgangskode.
            """
        ),
        Topic(
            icon: "iphone",
            question: "Har jeg også appen til iPhone?",
            answer: """
            Ja. BetterLectio til Mac og BetterLectio til iPhone er den samme app i \
            App Store. Har du den ene, står den anden allerede som købt på dine \
            øvrige enheder og kan hentes uden videre.
            """
        ),
    ]
}

// MARK: - FAQ item

private struct FAQItem: View {
    let topic: HelpView.Topic
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.26)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: BL.Space.m) {
                    Image(systemName: topic.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)

                    Text(topic.question)
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: BL.Space.m)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(BL.Space.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(topic.answer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, BL.Space.m)
                    .padding(.leading, 28)
                    .padding(.bottom, BL.Space.m)
            }
        }
        .blCard()
    }
}
