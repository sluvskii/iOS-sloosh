import SwiftUI

public struct AuthView: View {
    enum AuthMode {
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

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Telegram iOS Top Bar with back button
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Назад")
                                .font(.system(size: 17, weight: .regular))
                        }
                        .foregroundColor(Color.slooshAccent)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Telegram Hero Icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.slooshAccent.opacity(0.25), Color.white.opacity(0.06)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 96, height: 96)
                                .glassEffect(in: Circle())

                            Image(systemName: mode == .signIn ? "lock.shield.fill" : "person.badge.plus")
                                .font(.system(size: 42, weight: .medium))
                                .foregroundStyle(Color.slooshAccent)
                        }
                        .padding(.top, 24)

                        // Telegram Title & Subtitle
                        VStack(spacing: 8) {
                            Text(mode == .signIn ? "Вход в sloosh" : "Регистрация в sloosh")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(.primary)

                            Text(mode == .signIn ? "Введите ваш Email и пароль для входа и облачной синхронизации Избранного." : "Укажите имя, Email и пароль для создания нового аккаунта.")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        // Telegram-style Grouped Glass Input Block
                        VStack(spacing: 0) {
                            if mode == .signUp {
                                HStack(spacing: 14) {
                                    Text("Имя")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.secondary)
                                        .frame(width: 70, alignment: .leading)

                                    TextField("Ваше имя", text: $name)
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.primary)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 14)

                                Divider()
                                    .padding(.leading, 18)
                            }

                            HStack(spacing: 14) {
                                Text("Email")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.secondary)
                                    .frame(width: 70, alignment: .leading)

                                TextField("email@example.com", text: $email)
                                    .font(.system(size: 16, weight: .regular))
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)

                            Divider()
                                .padding(.leading, 18)

                            HStack(spacing: 14) {
                                Text("Пароль")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.secondary)
                                    .frame(width: 70, alignment: .leading)

                                if isPasswordVisible {
                                    TextField("Мин. 6 символов", text: $password)
                                        .font(.system(size: 16, weight: .regular))
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .foregroundColor(.primary)
                                } else {
                                    SecureField("Мин. 6 символов", text: $password)
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.primary)
                                }

                                Button {
                                    isPasswordVisible.toggle()
                                } label: {
                                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                        }
                        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 20)

                        // Telegram Action Button "Далее"
                        Button {
                            Task {
                                let success: Bool
                                if mode == .signIn {
                                    success = await authRepo.signIn(email: email, password: password)
                                } else {
                                    success = await authRepo.signUp(email: email, password: password, displayName: name)
                                }
                                if success { dismiss() }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if authRepo.isLoading {
                                    ProgressView().tint(.black)
                                } else {
                                    Text("Далее")
                                        .font(.system(size: 17, weight: .bold))
                                }
                                Spacer()
                            }
                            .padding(.vertical, 15)
                            .background(Color.slooshAccent)
                            .foregroundColor(.black)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(authRepo.isLoading)
                        .padding(.horizontal, 20)

                        // Telegram Footer Switcher & Password Reset
                        VStack(spacing: 12) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    mode = (mode == .signIn) ? .signUp : .signIn
                                }
                            } label: {
                                Text(mode == .signIn ? "Ещё нет аккаунта? Зарегистрироваться" : "Уже есть аккаунт? Войти")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color.slooshAccent)
                            }
                            .buttonStyle(.plain)

                            if mode == .signIn {
                                Button("Забыли пароль?") {
                                    resetEmail = email
                                    showResetAlert = true
                                }
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.secondary)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
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
            Text("Инструкция по сбросу пароля будет отправлена на ваш Email.")
        }
    }
}
