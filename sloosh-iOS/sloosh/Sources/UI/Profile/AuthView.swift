import SwiftUI
import UIKit

/// Полноэкранный экран обязательной авторизации в флагманском дизайне sloosh (1-в-1 с Android AuthSheet.kt).
/// Исключительно Google Sign-In без лишних полей почты и паролей.
public struct AuthView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authRepo = AuthRepository.shared

    public init() {}

    public var body: some View {
        CinematicAuthView(onDismiss: {
            dismiss()
        })
        .onChange(of: authRepo.isAuthenticated) { _, isAuth in
            if isAuth {
                dismiss()
            }
        }
    }
}
