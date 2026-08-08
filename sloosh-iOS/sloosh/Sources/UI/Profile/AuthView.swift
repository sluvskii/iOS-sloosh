import SwiftUI
import UIKit

/// Полноэкранный экран авторизации в дизайне ChatGPT / Liquid Glass.
/// Поддерживает входы через Email/Пароль и Google Sign-In (через ASWebAuthenticationSession + PKCE).
public struct AuthView: View {

    public enum AuthMode: Hashable, Equatable {
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
    @State private var shakeOffset: CGFloat = 0

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, email, password
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    // MARK: - Hero Logo & Headline
                    VStack(spacing: 12) {
                        Image("LogoText")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 36)
                            .foregroundStyle(Color.slooshAccent)
                            .padding(.bottom, 4)

                        Text(mode == .signIn ? "Войти в sloosh" : "Создать аккаунт")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .animation(.default, value: mode)

                        Text("Синхронизируйте избранное, историю просмотров и продолжение на всех устройствах.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .padding(.horizontal, 16)
                    }
                    .padding(.top, 12)

                    // MARK: - Mode Picker
                    Picker("Режим", selection: $mode.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                        Text("Вход").tag(AuthMode.signIn)
                        Text("Регистрация").tag(AuthMode.signUp)
                    }
                    .pickerStyle(.segmented)

                    // MARK: - Input Fields Card
                    VStack(spacing: 12) {
                        if mode == .signUp {
                            HStack(spacing: 12) {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Color.slooshAccent)
                                    .frame(width: 20)
                                TextField("Ваше имя", text: $name)
                                    .focused($focusedField, equals: .name)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "envelope.fill")
                                .foregroundStyle(Color.slooshAccent)
                                .frame(width: 20)
                            TextField("Электронная почта", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .email)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))

                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(Color.slooshAccent)
                                .frame(width: 20)
                            if isPasswordVisible {
                                TextField("Пароль (мин. 6 символов)", text: $password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .password)
                            } else {
                                SecureField("Пароль (мин. 6 символов)", text: $password)
                                    .focused($focusedField, equals: .password)
                            }
                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))

                        if let error = authRepo.lastError {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.system(size: 13, weight: .medium))
                                .multilineTextAlignment(.center)
                                .modifier(ShakeEffect(animatableData: shakeOffset))
                                .padding(.top, 4)
                        }
                    }

                    // MARK: - Primary Action Button
                    Button {
                        handlePrimaryAction()
                    } label: {
                        HStack {
                            Spacer()
                            if authRepo.isLoading {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Text(mode == .signIn ? "Войти" : "Зарегистрироваться")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                            Spacer()
                        }
                        .frame(height: 50)
                        .background(Color.slooshAccent)
                        .clipShape(Capsule())
                    }
                    .disabled(authRepo.isLoading || email.isEmpty || password.isEmpty)
                    .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1.0)
                    .buttonStyle(ScaleButtonStyle())

                    // MARK: - Divider "или"
                    HStack(spacing: 16) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(height: 1)
                        Text("или")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(height: 1)
                    }
                    .padding(.vertical, 2)

                    // MARK: - SSO: Google Sign-In Button
                    Button {
                        handleGoogleSignIn()
                    } label: {
                        HStack(spacing: 12) {
                            Image("GoogleLogo")
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                            Text("Продолжить через Google")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            if authRepo.isLoading {
                                ProgressView().tint(Color.slooshAccent)
                            }
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 50)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .disabled(authRepo.isLoading)
                    .buttonStyle(ScaleButtonStyle())

                    // MARK: - Forgot Password Link
                    if mode == .signIn {
                        Button {
                            resetEmail = email
                            showResetAlert = true
                        } label: {
                            Text("Забыли пароль?")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.slooshAccent)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                }
            }
            .onChange(of: email) { _, _ in authRepo.clearError() }
            .onChange(of: password) { _, _ in authRepo.clearError() }
            .alert("Сброс пароля", isPresented: $showResetAlert) {
                TextField("Email", text: $resetEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                Button("Отмена", role: .cancel) {}
                Button("Отправить ссылку") {
                    Task {
                        _ = await authRepo.resetPassword(email: resetEmail)
                    }
                }
            } message: {
                Text("Firebase отправит ссылку для сброса пароля на указанный адрес.")
            }
        }
    }

    // MARK: - Actions

    private func handlePrimaryAction() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        focusedField = nil

        Task {
            let success: Bool
            if mode == .signIn {
                success = await authRepo.signIn(email: email, password: password)
            } else {
                success = await authRepo.signUp(email: email, password: password, displayName: name.isEmpty ? nil : name)
            }

            if success {
                dismiss()
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                withAnimation(.default) {
                    shakeOffset = 6
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    shakeOffset = 0
                }
            }
        }
    }

    private func handleGoogleSignIn() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        focusedField = nil
        Task {
            let success = await authRepo.signInWithGoogle()
            if success {
                dismiss()
            }
        }
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Shake Effect

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(animatableData * .pi * 4) * 6, y: 0))
    }
}
