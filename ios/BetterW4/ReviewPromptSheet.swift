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

            Text(String(localized: "review_prompt.title", defaultValue: "Do you like BetterW4?"))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(
                String(
                    localized: "review_prompt.body",
                    defaultValue: "It only takes a moment, and it helps us make the app better for you and your classmates."
                )
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button(action: onPositive) {
                Text(String(localized: "review_prompt.positive", defaultValue: "Yes, it is good"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: onNegative) {
                Text(String(localized: "review_prompt.negative", defaultValue: "Could be better"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(action: onDismiss) {
                Text(String(localized: "review_prompt.dismiss", defaultValue: "Not now"))
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
