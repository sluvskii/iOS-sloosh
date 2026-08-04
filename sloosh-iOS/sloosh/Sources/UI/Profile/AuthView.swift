import SwiftUI
import UIKit

// MARK: - Telegram-iOS Styled Authentication View for Firebase (Google + Email & Password)

public struct AuthView: View {
    public enum AuthMode {
        case signIn
        case signUp
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var authRepo = AuthRepository.shared

    @State private var mode: AuthMode = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var name: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var showResetAlert: Bool = false
    @State private var resetEmail: String = ""

    // Telegram Spring Animation States
    @State private var heroScale: CGFloat = 1.0
    @State private var heroOffsetY: CGFloat = 0
    @State private var shakeOffset: CGFloat = 0

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case email
        case password
    }

    public init() {}

    public var body: some View {
        ZStack {
            // Telegram Dark Canvas
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar (Telegram xmark)
                topNavigationBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Telegram Hero 3D Emoji Node
                        Text(mode == .signIn ? "🔐" : "👤")
                            .font(.system(size: 78))
                            .scaleEffect(heroScale)
                            .offset(y: heroOffsetY)
                            .padding(.top, 12)

                        // Title & Subtitle Node
                        VStack(spacing: 8) {
                            Text(mode == .signIn ? "Вход в sloosh" : "Регистрация")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(.white)

                            Text(mode == .signIn ? "Войдите через Google или по Email с паролем для синхронизации Избранного." : "Укажите имя, Email и пароль для создания нового аккаунта.")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        // Firebase Google Auth Button (Telegram Prominent Glass Pill)
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            Task {
                                let success = await authRepo.signInWithGoogle()
                                if success { dismiss() }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "g.circle.fill")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white)

                                Text("Продолжить с Google")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glassEffect(in: Capsule())
                        }
                        .buttonStyle(TelegramScaleButtonStyle())
                        .padding(.horizontal, 24)

                        // Divider Line: — или через Email —
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 1)
                            Text("или через Email")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                            Rectangle()
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 24)

                        // Telegram Grouped Glass Input Card
                        VStack(spacing: 0) {
                            if mode == .signUp {
                                HStack(spacing: 14) {
                                    Text("Имя")
                                        .font(.system(size: 17, weight: .regular))
                                        .foregroundColor(.secondary)
                                        .frame(width: 65, alignment: .leading)

                                    TextField("Ваше имя", text: $name)
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(.white)
                                        .focused($focusedField, equals: .name)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                                Divider()
                                    .background(Color.white.opacity(0.15))
                                    .padding(.leading, 16)
                            }

                            HStack(spacing: 14) {
                                Text("Email")
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundColor(.secondary)
                                    .frame(width: 65, alignment: .leading)

                                TextField("email@example.com", text: $email)
                                    .font(.system(size: 17, weight: .medium))
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .foregroundColor(.white)
                                    .focused($focusedField, equals: .email)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider()
                                .background(Color.white.opacity(0.15))
                                .padding(.leading, 16)

                            HStack(spacing: 14) {
                                Text("Пароль")
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundColor(.secondary)
                                    .frame(width: 65, alignment: .leading)

                                if isPasswordVisible {
                                    TextField("Пароль", text: $password)
                                        .font(.system(size: 17, weight: .medium))
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .foregroundColor(.white)
                                        .focused($focusedField, equals: .password)
                                } else {
                                    SecureField("Пароль", text: $password)
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundColor(.white)
                                        .focused($focusedField, equals: .password)
                                }

                                Button {
                                    isPasswordVisible.toggle()
                                } label: {
                                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(TelegramScaleButtonStyle())
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 24)
                        .modifier(ShakeEffect(animatableData: shakeOffset))

                        // Action Links: Forgot Password & Mode Switcher
                        VStack(spacing: 12) {
                            if mode == .signIn {
                                Button("Забыли пароль?") {
                                    resetEmail = email
                                    showResetAlert = true
                                }
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(Color.slooshAccent)
                                .buttonStyle(TelegramScaleButtonStyle())
                            }

                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    mode = (mode == .signIn) ? .signUp : .signIn
                                }
                            } label: {
                                Text(mode == .signIn ? "Ещё нет аккаунта? Зарегистрироваться" : "Уже есть аккаунт? Войти")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color.slooshAccent)
                            }
                            .buttonStyle(TelegramScaleButtonStyle())
                        }
                    }
                    .padding(.top, 12)
                }

                Spacer(minLength: 0)

                // Bottom Floating Primary Action Button (Continue)
                actionButtonNode
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Сброс пароля", isPresented: $showResetAlert) {
            TextField("Введите Email", text: $resetEmail)
            Button("Отмена", role: .cancel) {}
            Button("Отправить") {
                Task {
                    _ = await authRepo.resetPassword(email: resetEmail)
                }
            }
        } message: {
            Text("Ссылка для сброса пароля будет отправлена на ваш Email.")
        }
        .onChange(of: mode) { _, _ in
            triggerHeroBounce()
        }
    }

    private func triggerHeroBounce() {
        withAnimation(.interpolatingSpring(stiffness: 220, damping: 11)) {
            heroScale = 1.18
            heroOffsetY = -10
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                heroScale = 1.0
                heroOffsetY = 0
            }
        }
    }

    // MARK: - Navigation Header

    private var topNavigationBar: some View {
        HStack {
            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(TelegramScaleButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Primary Action Button Node

    private var actionButtonNode: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            handlePrimaryAction()
        } label: {
            HStack {
                Spacer()
                if authRepo.isLoading {
                    ProgressView().tint(.black)
                } else {
                    Text(mode == .signIn ? "Войти" : "Зарегистрироваться")
                        .font(.system(size: 17, weight: .bold))
                }
                Spacer()
            }
            .padding(.vertical, 16)
            .background(Color.slooshAccent)
            .foregroundColor(.black)
            .clipShape(Capsule())
        }
        .buttonStyle(TelegramScaleButtonStyle())
        .disabled(authRepo.isLoading || email.isEmpty || password.isEmpty)
        .opacity((email.isEmpty || password.isEmpty) ? 0.5 : 1.0)
    }

    private func handlePrimaryAction() {
        Task {
            let success: Bool
            if mode == .signIn {
                success = await authRepo.signIn(email: email, password: password)
            } else {
                success = await authRepo.signUp(email: email, password: password, displayName: name)
            }
            if success {
                dismiss()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                withAnimation(.default) {
                    shakeOffset = 6
                }
            }
        }
    }
}

// MARK: - Telegram Spring Button Style

private struct TelegramScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Shake Effect Helper

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(animatableData * .pi * 2) * 8, y: 0))
    }
}
