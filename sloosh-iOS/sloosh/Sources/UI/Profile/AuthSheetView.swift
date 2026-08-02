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
        VStack(spacing: 22) {
            // Telegram-style Header: Title + Right Glass Close Button
            HStack {
                Text(selectedTab == .signIn ? "Вход" : "Регистрация")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.primary)

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
            .padding(.top, 20)

            // Segment Switcher
            Picker("Режим", selection: $selectedTab.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                ForEach(AuthTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            // Telegram-style Grouped Glass Input Card
            VStack(spacing: 0) {
                if selectedTab == .signUp {
                    HStack(spacing: 12) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .frame(width: 20)

                        TextField("Ваше имя", text: $name)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider()
                        .padding(.leading, 48)
                }

                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    TextField("Email", text: $email)
                        .font(.body)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()
                    .padding(.leading, 48)

                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                        .frame(width: 20)

                    if isPasswordVisible {
                        TextField("Пароль", text: $password)
                            .font(.body)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundColor(.primary)
                    } else {
                        SecureField("Пароль", text: $password)
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

            if selectedTab == .signIn {
                HStack {
                    Spacer()
                    Button("Забыли пароль?") {
                        resetEmail = email
                        showResetAlert = true
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Color.slooshAccent)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, -10)
            }

            // Primary Action Button (Telegram style prominent pill)
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
                    Spacer()
                    if authRepo.isLoading {
                        ProgressView().tint(.black)
                    } else {
                        Text(selectedTab == .signIn ? "Продолжить" : "Зарегистрироваться")
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

            Spacer(minLength: 12)
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
