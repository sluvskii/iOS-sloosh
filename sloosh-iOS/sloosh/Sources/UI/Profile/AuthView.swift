import SwiftUI
import UIKit

// MARK: - 1:1 Implementation of Telegram-iOS AuthorizationSequenceController Architecture

public struct AuthView: View {
    public enum SequenceStep: Hashable {
        case email
        case code
        case password
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var authRepo = AuthRepository.shared

    @State private var currentStep: SequenceStep = .email
    @State private var email: String = ""
    @State private var pinCode: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var showConfirmOverlay: Bool = false
    @State private var showResetAlert: Bool = false
    @State private var resetEmail: String = ""
    @State private var shakeOffset: CGFloat = 0

    @FocusState private var focusedField: SequenceStep?

    public init() {}

    public var body: some View {
        ZStack {
            // Telegram iOS Dark Canvas
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Telegram Navigation Header (AuthorizationSequenceNavigationBar)
                navigationHeaderBar

                // Animated Step Node Container
                ZStack {
                    switch currentStep {
                    case .email:
                        emailEntryStepNode
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    case .code:
                        codeEntryStepNode
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    case .password:
                        passwordEntryStepNode
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
                .modifier(ShakeEffect(animatableData: shakeOffset))

                Spacer(minLength: 0)

                // Telegram SolidRoundedButtonNode (Continue Action Pill)
                actionButtonNode
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }

            // Telegram Confirmation Overlay Card (AuthorizationConfirmationController)
            if showConfirmOverlay {
                confirmationCardOverlay
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

    // MARK: - Navigation Header (AuthorizationSequenceNavigationBar)

    private var navigationHeaderBar: some View {
        HStack {
            if currentStep != .email {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if currentStep == .password { currentStep = .code }
                        else if currentStep == .code { currentStep = .email }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
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
                        .foregroundColor(.white)
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

    // MARK: - Step 1: AuthorizationSequenceEmailEntryControllerNode

    private var emailEntryStepNode: some View {
        VStack(spacing: 24) {
            // Telegram Animated Sticker Placeholder (IntroPhone)
            Text("✉️")
                .font(.system(size: 76))
                .padding(.top, 16)

            VStack(spacing: 8) {
                Text("Ваш Email")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)

                Text("Введите адрес вашей электронной почты для входа или регистрации в sloosh.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            // Telegram Grouped Input Node
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text("Email")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .leading)

                    TextField("email@example.com", text: $email)
                        .font(.system(size: 17, weight: .medium))
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(.white)
                        .focused($focusedField, equals: .email)
                }
                .padding(.vertical, 14)

                Divider()
                    .background(Color.white.opacity(0.15))
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
        .onAppear {
            focusedField = .email
        }
    }

    // MARK: - Step 2: AuthorizationSequenceCodeEntryControllerNode

    private var codeEntryStepNode: some View {
        VStack(spacing: 24) {
            Text("📨")
                .font(.system(size: 76))
                .padding(.top, 16)

            VStack(spacing: 8) {
                Text("Проверьте почту")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)

                Text("Мы отправили 5-значный код подтверждения на \(maskedEmail(email))")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            // CodeInputView (5 Digit Boxes)
            ZStack {
                TextField("", text: $pinCode)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .code)
                    .opacity(0.01)
                    .onChange(of: pinCode) { _, newValue in
                        if newValue.count > 5 {
                            pinCode = String(newValue.prefix(5))
                        }
                        if pinCode.count == 5 {
                            Task {
                                let valid = await authRepo.verifyCode(pinCode)
                                if valid {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        currentStep = .password
                                    }
                                } else {
                                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                                    withAnimation(.default) {
                                        shakeOffset = 6
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
                            focusedField = .code
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
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Color.slooshAccent)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .onAppear {
            focusedField = .code
        }
    }

    // MARK: - Step 3: AuthorizationSequencePasswordEntryControllerNode

    private var passwordEntryStepNode: some View {
        VStack(spacing: 24) {
            // IntroPassword Sticker (Telegram 2FA Monkey 🙈)
            Text("🙈")
                .font(.system(size: 76))
                .padding(.top, 16)

            VStack(spacing: 8) {
                Text("Ваш пароль")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)

                Text("Ваш аккаунт защищен дополнительным паролем. Введите ваш пароль для входа.")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
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
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 14)

                Divider()
                    .background(Color.white.opacity(0.15))
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Button {
                resetEmail = email
                showResetAlert = true
            } label: {
                Text("Забыли пароль?")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Color.slooshAccent)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .onAppear {
            focusedField = .password
        }
    }

    // MARK: - Action Button Node (SolidRoundedButtonNode)

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
        .disabled(authRepo.isLoading || (currentStep == .email && email.isEmpty))
        .opacity((currentStep == .email && email.isEmpty) ? 0.5 : 1.0)
    }

    private func handlePrimaryAction() {
        if currentStep == .email {
            guard !email.isEmpty else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                showConfirmOverlay = true
            }
        } else if currentStep == .code {
            Task {
                let valid = await authRepo.verifyCode(pinCode)
                if valid {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        currentStep = .password
                    }
                }
            }
        } else if currentStep == .password {
            Task {
                let success = await authRepo.signIn(email: email, password: password)
                if success {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Confirmation Card Overlay (AuthorizationConfirmationController)

    private var confirmationCardOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showConfirmOverlay = false }
                }

            VStack(spacing: 16) {
                Text(email)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Это ваш правильный Email?")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.secondary)

                Button {
                    withAnimation {
                        showConfirmOverlay = false
                        focusedField = .email
                    }
                } label: {
                    Text("Изменить")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color.slooshAccent)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                Button {
                    withAnimation {
                        showConfirmOverlay = false
                        currentStep = .code
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

// MARK: - Shake Effect Helper

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(animatableData * .pi * 2) * 8, y: 0))
    }
}
