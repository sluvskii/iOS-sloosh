import SwiftUI

public struct AuthSheetView: View {
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
        VStack(spacing: 0) {
            // Telegram iOS Top Navigation Bar
            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .font(.body)
                .foregroundColor(Color.slooshAccent)
                .buttonStyle(.plain)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 30, height: 30)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    // Telegram Hero Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.slooshAccent.opacity(0.3), Color.white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: mode == .signIn ? "lock.shield.fill" : "person.badge.plus")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(Color.slooshAccent)
                    }
                    .padding(.top, 8)

                    // Telegram Title & Description
                    VStack(spacing: 6) {
                        Text(mode == .signIn ? "Вход в sloosh" : "Регистрация в sloosh")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.primary)

                        Text(mode == .signIn ? "Введите Email и пароль для входа и облачной синхронизации Избранного." : "Укажите имя, Email и пароль для создания нового аккаунта.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Telegram-style Grouped Input Block
                    VStack(spacing: 0) {
                        if mode == .signUp {
                            HStack(spacing: 14) {
                                Text("Имя")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .frame(width: 65, alignment: .leading)

                                TextField("Ваше имя", text: $name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Divider()
                                .padding(.leading, 16)
                        }

                        HStack(spacing: 14) {
                            Text("Email")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .frame(width: 65, alignment: .leading)

                            TextField("email@example.com", text: $email)
                                .font(.body)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        Divider()
                            .padding(.leading, 16)

                        HStack(spacing: 14) {
                            Text("Пароль")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .frame(width: 65, alignment: .leading)

                            if isPasswordVisible {
                                TextField("Мин. 6 символов", text: $password)
                                    .font(.body)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .foregroundColor(.primary)
                            } else {
                                SecureField("Мин. 6 символов", text: $password)
                                    .font(.body)
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                    .glassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 20)

                    // Telegram Primary Button "Далее"
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
                                    .font(.body.weight(.bold))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 14)
                        .background(Color.slooshAccent)
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(authRepo.isLoading)
                    .padding(.horizontal, 20)

                    // Telegram Footer Switcher & Password Reset Link
                    VStack(spacing: 10) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                mode = (mode == .signIn) ? .signUp : .signIn
                            }
                        } label: {
                            Text(mode == .signIn ? "Ещё нет аккаунта? Зарегистрироваться" : "Уже есть аккаунт? Войти")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Color.slooshAccent)
                        }
                        .buttonStyle(.plain)

                        if mode == .signIn {
                            Button("Забыли пароль?") {
                                resetEmail = email
                                showResetAlert = true
                            }
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
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
