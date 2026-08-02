import SwiftUI
import AuthenticationServices

public struct AuthSheetView: View {
    enum AuthTab: String, CaseIterable {
        case signIn = "Вход"
        case signUp = "Регистрация"
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var authRepo = AuthRepository.shared
    
    @State private var selectedTab: AuthTab = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var name: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var showResetAlert: Bool = false
    @State private var resetEmail: String = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header Logo & Title
                        VStack(spacing: 8) {
                            Text("sloosh")
                                .font(.system(size: 38, weight: .black, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, Color.slooshAccent],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )

                            Text("Войдите, чтобы синхронизировать Избранное и Историю на всех устройствах")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(.top, 16)

                        // Segment Picker: Вход / Регистрация
                        HStack(spacing: 0) {
                            ForEach(AuthTab.allCases, id: \.self) { tab in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        selectedTab = tab
                                    }
                                } label: {
                                    Text(tab.rawValue)
                                        .font(.system(size: 15, weight: .semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            selectedTab == tab ? Color.white : Color.clear
                                        )
                                        .foregroundColor(selectedTab == tab ? .black : .white.opacity(0.7))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(4)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                        .padding(.horizontal, 24)

                        // Native Sign in with Apple
                        SignInWithAppleButton(
                            .signIn,
                            onRequest: { request in
                                request.requestedScopes = [.fullName, .email]
                            },
                            onCompletion: { result in
                                switch result {
                                case .success(let authorization):
                                    if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                        let token = String(data: appleIDCredential.identityToken ?? Data(), encoding: .utf8) ?? ""
                                        Task {
                                            let success = await authRepo.signInWithApple(
                                                idToken: token,
                                                rawNonce: "",
                                                email: appleIDCredential.email,
                                                fullName: appleIDCredential.fullName
                                            )
                                            if success { dismiss() }
                                        }
                                    }
                                case .failure(let error):
                                    AppDiagnostics.shared.log("Apple Auth error: \(error.localizedDescription)")
                                }
                            }
                        )
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 24)

                        // Divider OR
                        HStack(spacing: 16) {
                            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                            Text("или через Email")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                        }
                        .padding(.horizontal, 24)

                        // Input Form
                        VStack(spacing: 16) {
                            if selectedTab == .signUp {
                                CustomTextField(
                                    icon: "person.fill",
                                    placeholder: "Ваше имя (необязательно)",
                                    text: $name
                                )
                            }

                            CustomTextField(
                                icon: "envelope.fill",
                                placeholder: "Email",
                                text: $email,
                                keyboardType: .emailAddress
                            )

                            CustomPasswordField(
                                icon: "lock.fill",
                                placeholder: "Пароль",
                                text: $password,
                                isVisible: $isPasswordVisible
                            )

                            if selectedTab == .signIn {
                                Button {
                                    resetEmail = email
                                    showResetAlert = true
                                } label: {
                                    Text("Забыли пароль?")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(Color.slooshAccent)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .padding(.trailing, 4)
                            }
                        }
                        .padding(.horizontal, 24)

                        // Action Button
                        Button {
                            Task {
                                let success: Bool
                                if selectedTab == .signIn {
                                    success = await authRepo.signIn(email: email, password: password)
                                } else {
                                    success = await authRepo.signUp(email: email, password: password, displayName: name)
                                }
                                if success { dismiss() }
                            }
                        } label: {
                            HStack {
                                if authRepo.isLoading {
                                    ProgressView().tint(.black)
                                } else {
                                    Text(selectedTab == .signIn ? "Войти в аккаунт" : "Зарегистрироваться")
                                        .font(.system(size: 16, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.slooshAccent)
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(authRepo.isLoading)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                        // Close / Guest Action
                        Button {
                            dismiss()
                        } label: {
                            Text("Продолжить без входа")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .alert("Сброс пароля", isPresented: $showResetAlert) {
                TextField("Введите Email", text: $resetEmail)
                Button("Отмена", role: .cancel) {}
                Button("Отправить") {
                    Task {
                        _ = await authRepo.resetPassword(email: resetEmail)
                    }
                }
            } message: {
                Text("Мы отправим ссылку для сброса пароля на ваш Email.")
            }
        }
    }
}

// MARK: - UI Helpers

private struct CustomTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct CustomPasswordField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    @Binding var isVisible: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 20)

            if isVisible {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
            } else {
                SecureField(placeholder, text: $text)
                    .foregroundColor(.white)
            }

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
