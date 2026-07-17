import SwiftUI

/// Единый компонент пустого состояния для всех экранов приложения.
/// Стилистика соответствует iOS 26 — крупный символ, жирный заголовок, описание в secondary.
struct AppEmptyStateView: View {

    let icon: String
    let title: String
    let description: String
    var action: ActionConfig? = nil

    struct ActionConfig {
        let label: String
        let handler: () -> Void
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)

            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 300)

            if let action {
                Button(action.label) {
                    action.handler()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(Color.slooshAccent)
                .padding(.top, 22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
}
