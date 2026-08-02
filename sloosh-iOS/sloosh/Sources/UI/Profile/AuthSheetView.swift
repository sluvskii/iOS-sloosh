import SwiftUI

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
                    VStack(spacing: 22) {
                        // Title & Subtitle
                        VStack(spacing: 6) {
                            Text(selectedTab == .signIn ? "Вход в аккаунт" : "Создание аккаунта")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            Text("Синхронизируйте Избранное и историю просмотра между всеми устройствами")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .padding(.top, 24)

                        // Segment Picker: Вход / Регистрация
                        HStack(spacing: 4) {
                            ForEach(AuthTab.allCases, id: \.self) { tab in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                        selectedTab = tab
                                    }
                                } label: {
                                    Text(tab.rawValue)
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            selectedTab == tab ? Color.white.opacity(0.18) : Color.clear
                                        )
                                        .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.6))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal, 20)

                        // Form Fields
                        VStack(spacing: 14) {
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
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(Color.slooshAccent)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                                .padding(.trailing, 4)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Main Action Button
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
                                    Text(selectedTab == .signIn ? "Войти" : "Зарегистрироваться")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.slooshAccent)
                            .foregroundColor(.black)
                            .clipShape(Capsule())
                        }
                        .disabled(authRepo.isLoading)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                        // Continue as Guest
                        Button {
                            dismiss()
                        } label: {
                            Text("Продолжить как гость")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    TelegramGlassIconButton(systemName: "xmark") {
                        dismiss()
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
                Text("Мы отправим инструкцию по сбросу пароля на ваш Email.")
            }
        }
    }
}

// MARK: - Refined Glass Input Helpers

private struct CustomTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 20)

            if isVisible {
                TextField(placeholder, text: $text)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
            } else {
                SecureField(placeholder, text: $text)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
            }

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
