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
        VStack(spacing: 20) {
            // Top Bar with native .glassEffect close button
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Liquid Glass Segment Switcher
            HStack(spacing: 0) {
                ForEach(AuthTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selectedTab == tab ? Color.white.opacity(0.18) : Color.clear
                            )
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .glassEffect(in: Capsule())
            .padding(.horizontal, 20)

            // Liquid Glass Capsule Form Fields
            VStack(spacing: 12) {
                if selectedTab == .signUp {
                    GlassCapsuleInputField(
                        icon: "person.fill",
                        placeholder: "Ваше имя (необязательно)",
                        text: $name
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                GlassCapsuleInputField(
                    icon: "envelope.fill",
                    placeholder: "Email",
                    text: $email,
                    keyboardType: .emailAddress
                )

                GlassCapsulePasswordField(
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
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.slooshAccent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 20)

            // Primary Action Pill Button
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
                            .font(.system(size: 16, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.slooshAccent)
                .foregroundColor(.black)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(authRepo.isLoading)
            .padding(.horizontal, 20)
            .padding(.top, 6)

            Spacer(minLength: 10)
        }
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
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

// MARK: - Native iOS 26 Liquid Glass Capsule Inputs

private struct GlassCapsuleInputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 18)

            TextField(placeholder, text: $text)
                .font(.system(size: 15, weight: .regular))
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(in: Capsule())
    }
}

private struct GlassCapsulePasswordField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    @Binding var isVisible: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 18)

            if isVisible {
                TextField(placeholder, text: $text)
                    .font(.system(size: 15, weight: .regular))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.primary)
            } else {
                SecureField(placeholder, text: $text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.primary)
            }

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(in: Capsule())
    }
}
