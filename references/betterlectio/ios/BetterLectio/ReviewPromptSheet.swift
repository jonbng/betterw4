import SwiftUI

/// Soft pre-filter before App Store review: happy → StoreKit, unhappy → feedback.
struct ReviewPromptSheet: View {
    let onPositive: () -> Void
    let onNegative: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.thumbsup")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text(String(localized: "review_prompt.title", defaultValue: "Kan du lide BetterLectio?"))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(
                String(
                    localized: "review_prompt.body",
                    defaultValue: "Det tager kun et øjeblik, og det hjælper os med at gøre appen bedre for dig og dine klassekammerater."
                )
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button(action: onPositive) {
                Text(String(localized: "review_prompt.positive", defaultValue: "Ja, den er god"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: onNegative) {
                Text(String(localized: "review_prompt.negative", defaultValue: "Kunne være bedre"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(action: onDismiss) {
                Text(String(localized: "review_prompt.dismiss", defaultValue: "Ikke nu"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
