import SwiftUI

public struct AuthView: View {
    enum Step {
        case email
        case code
        case password
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var authRepo = AuthRepository.shared
    
    @State private var step: Step = .email
    @State private var email: String = ""
    @State private var pinCode: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var showConfirmSheet: Bool = false
    @State private var showResetAlert: Bool = false
    @State private var resetEmail: String = ""
    @FocusState private var isCodeFocused: Bool
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isPasswordFocused: Bool

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Bar Navigation
                topNavigationBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        switch step {
                        case .email:
                            emailStepView
                        case .code:
                            codeStepView
                        case .password:
                            passwordStepView
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }

                Spacer(minLength: 0)

                // Bottom Floating Action Button (Continue)
                bottomActionButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }

            // Step 1.5: Confirmation Card Popup (1:1 Telegram Screenshot 2)
            if showConfirmSheet {
                emailConfirmationOverlay
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

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        HStack {
            if step != .email {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if step == .password { step = .code }
                        else if step == .code { step = .email }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Step 1: Email (1:1 Screenshot 1)

    private var emailStepView: some View {
        VStack(spacing: 24) {
            // 3D Emoji Hero Header
            Text("✉️")
                .font(.system(size: 76))
                .padding(.top, 12)

            VStack(spacing: 8) {
                Text("Ваш Email")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("Введите адрес вашей электронной почты для входа или регистрации в sloosh.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // Telegram Input Line
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Email")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .leading)

                    TextField("000 000 0000", text: $email)
                        .font(.system(size: 18, weight: .medium))
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(.white)
                        .focused($isEmailFocused)
                }
                .padding(.vertical, 14)

                Divider()
                    .background(Color.white.opacity(0.15))
            }
            .padding(.top, 16)
        }
    }

    // MARK: - Step 2: Verification Code 5 Digits (1:1 Screenshot 3)

    private var codeStepView: some View {
        VStack(spacing: 24) {
            Text("📨")
                .font(.system(size: 76))
                .padding(.top, 12)

            VStack(spacing: 8) {
                Text("Проверьте почту")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("Мы отправили 5-значный код подтверждения на \(maskedEmail(email))")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // 5 Pin Code Boxes (Screenshot 3)
            ZStack {
                // Invisible TextField catching focus
                TextField("", text: $pinCode)
                    .keyboardType(.numberPad)
                    .focused($isCodeFocused)
                    .opacity(0.01)
                    .onChange(of: pinCode) { _, newValue in
                        if newValue.count > 5 {
                            pinCode = String(newValue.prefix(5))
                        }
                        if pinCode.count == 5 {
                            Task {
                                let valid = await authRepo.verifyCode(pinCode)
                                if valid {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        step = .password
                                    }
                                }
                            }
                        }
                    }

                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { index in
                        let digit = getDigit(at: index)
                        let isCurrent = (pinCode.count == index)

                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.06))

                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    isCurrent ? Color.slooshAccent : Color.white.opacity(0.12),
                                    lineWidth: isCurrent ? 2 : 1
                                )

                            Text(digit)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 52, height: 60)
                        .onTapGesture {
                            isCodeFocused = true
                        }
                    }
                }
            }
            .padding(.top, 16)

            Button {
                Task {
                    _ = await authRepo.sendVerificationCode(email: email)
                }
            } label: {
                Text("Не получили код?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.slooshAccent)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .onAppear {
            isCodeFocused = true
        }
    }

    // MARK: - Step 3: Password / 2FA Monkey (1:1 Screenshot 4)

    private var passwordStepView: some View {
        VStack(spacing: 24) {
            // Iconic Telegram 2FA Monkey See-No-Evil Emoji
            Text("🙈")
                .font(.system(size: 76))
                .padding(.top, 12)

            VStack(spacing: 8) {
                Text("Ваш пароль")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text("Ваш аккаунт защищен паролем. Введите ваш пароль для завершения входа.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if isPasswordVisible {
                        TextField("Пароль", text: $password)
                            .font(.system(size: 18, weight: .medium))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundColor(.white)
                            .focused($isPasswordFocused)
                    } else {
                        SecureField("Пароль", text: $password)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .focused($isPasswordFocused)
                    }

                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 14)

                Divider()
                    .background(Color.white.opacity(0.15))
            }
            .padding(.top, 16)

            Button {
                resetEmail = email
                showResetAlert = true
            } label: {
                Text("Забыли пароль?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.slooshAccent)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .onAppear {
            isPasswordFocused = true
        }
    }

    // MARK: - Bottom Floating Action Button

    private var bottomActionButton: some View {
        Button {
            handleContinue()
        } label: {
            HStack {
                Spacer()
                if authRepo.isLoading {
                    ProgressView().tint(.black)
                } else {
                    Text("Продолжить")
                        .font(.system(size: 17, weight: .bold))
                }
                Spacer()
            }
            .padding(.vertical, 16)
            .background(Color.slooshAccent)
            .foregroundColor(.black)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(authRepo.isLoading || (step == .email && email.isEmpty))
        .opacity((step == .email && email.isEmpty) ? 0.5 : 1.0)
    }

    private func handleContinue() {
        if step == .email {
            guard !email.isEmpty else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showConfirmSheet = true
            }
        } else if step == .code {
            Task {
                let valid = await authRepo.verifyCode(pinCode)
                if valid {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        step = .password
                    }
                }
            }
        } else if step == .password {
            Task {
                let success = await authRepo.signIn(email: email, password: password)
                if success {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Confirmation Card Overlay (1:1 Screenshot 2)

    private var emailConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showConfirmSheet = false }
                }

            VStack(spacing: 16) {
                Text(email)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Это ваш правильный Email?")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.secondary)

                Button {
                    withAnimation {
                        showConfirmSheet = false
                        isEmailFocused = true
                    }
                } label: {
                    Text("Изменить")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.slooshAccent)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                Button {
                    withAnimation {
                        showConfirmSheet = false
                        step = .code
                    }
                    Task {
                        _ = await authRepo.sendVerificationCode(email: email)
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Продолжить")
                            .font(.system(size: 17, weight: .bold))
                        Spacer()
                    }
                    .padding(.vertical, 15)
                    .background(Color.slooshAccent)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(24)
            .background(Color.white.opacity(0.12))
            .glassEffect(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .padding(.horizontal, 20)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Helpers

    private func getDigit(at index: Int) -> String {
        guard index < pinCode.count else { return "" }
        let charIndex = pinCode.index(pinCode.startIndex, offsetBy: index)
        return String(pinCode[charIndex])
    }

    private func maskedEmail(_ raw: String) -> String {
        let parts = raw.components(separatedBy: "@")
        guard parts.count == 2, let first = parts.first, let domain = parts.last else { return raw }
        let maskedPrefix = String(first.prefix(2)) + "****" + String(first.suffix(1))
        return "\(maskedPrefix)@\(domain)"
    }
}
