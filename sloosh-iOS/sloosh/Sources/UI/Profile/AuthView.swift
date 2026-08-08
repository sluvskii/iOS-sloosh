import SwiftUI
import UIKit

/// Полноэкранный экран авторизации.
/// Использует Firebase Identity Toolkit REST API напрямую (без Firebase iOS SDK).
/// Google Sign-In убран — для него нужен GoogleSignIn iOS SDK, которого нет в проекте.
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
            Form {
                // MARK: Mode Picker
                Section {
                    Picker("Режим", selection: $mode.animation()) {
                        Text("Вход").tag(AuthMode.signIn)
                        Text("Регистрация").tag(AuthMode.signUp)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                }

                // MARK: Input Fields
                Section {
                    if mode == .signUp {
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundStyle(Color.slooshAccent)
                                .frame(width: 22)
                            TextField("Ваше имя", text: $name)
                                .focused($focusedField, equals: .name)
                        }
                    }

                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(Color.slooshAccent)
                            .frame(width: 22)
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                    }

                    HStack {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(Color.slooshAccent)
                            .frame(width: 22)
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
                } footer: {
                    // Показываем ошибку прямо под полями
                    if let error = authRepo.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .modifier(ShakeEffect(animatableData: shakeOffset))
                    }
                }

                // MARK: Primary Action Button
                Section {
                    Button {
                        handlePrimaryAction()
                    } label: {
                        HStack {
                            Spacer()
                            if authRepo.isLoading {
                                ProgressView()
                                    .tint(Color.slooshAccent)
                            } else {
                                Text(mode == .signIn ? "Войти" : "Зарегистрироваться")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.slooshAccent)
                            }
                            Spacer()
                        }
                    }
                    .disabled(authRepo.isLoading || email.isEmpty || password.isEmpty)
                }

                // MARK: Google Sign-In
                Section {
                    Button {
                        handleGoogleSignIn()
                    } label: {
                        HStack(spacing: 10) {
                            Image("GoogleLogo")
                                .renderingMode(.original)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                            Text("Продолжить с Google")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            if authRepo.isLoading {
                                ProgressView().tint(Color.slooshAccent)
                            }
                        }
                    }
                    .disabled(authRepo.isLoading)
                }

                // MARK: Forgot Password
                if mode == .signIn {
                    Section {
                        Button("Забыли пароль?") {
                            resetEmail = email
                            showResetAlert = true
                        }
                        .foregroundStyle(Color.slooshAccent)
                    }
                }
            }
            .navigationTitle(mode == .signIn ? "Вход" : "Регистрация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                }
            }
            .scrollContentBackground(.hidden)
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
                Text("Firebase отправит ссылку сброса пароля на указанный адрес.")
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

// MARK: - Shake Effect

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(animatableData * .pi * 4) * 6, y: 0))
    }
}
