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
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                // Top Bar with single Glass Close Button
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Segment Pill Switcher
                HStack(spacing: 0) {
                    ForEach(AuthTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    selectedTab == tab ? Color.white.opacity(0.16) : Color.clear
                                )
                                .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 20)

                // Form Fields Card
                VStack(spacing: 12) {
                    if selectedTab == .signUp {
                        GlassInputField(
                            icon: "person.fill",
                            placeholder: "Ваше имя (необязательно)",
                            text: $name
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    GlassInputField(
                        icon: "envelope.fill",
                        placeholder: "Email",
                        text: $email,
                        keyboardType: .emailAddress
                    )

                    GlassPasswordField(
                        icon: "lock.fill",
                        placeholder: "Пароль",
                        text: $password,
                        isVisible: $isPasswordVisible
                    )

                    if selectedTab == .signIn {
                        HStack {
                            Spacer()
                            Button {
                                resetEmail = email
                                showResetAlert = true
                            } label: {
                                Text("Забыли пароль?")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.slooshAccent.opacity(0.9))
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 20)

                // Primary Action Pill
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
                            Text(selectedTab == .signIn ? "Войти" : "Создать аккаунт")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.slooshAccent)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
                    .shadow(color: Color.slooshAccent.opacity(0.25), radius: 12, x: 0, y: 4)
                }
                .disabled(authRepo.isLoading)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer()
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
            Text("Инструкция по сбросу пароля будет отправлена на ваш Email.")
        }
    }
}

// MARK: - Ultra-Clean Floating Input Components

private struct GlassInputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 18)

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
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct GlassPasswordField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    @Binding var isVisible: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 18)

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
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
