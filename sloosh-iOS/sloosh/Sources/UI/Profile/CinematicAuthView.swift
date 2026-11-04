import SwiftUI
import UIKit

/// Флагманский нативный экран обязательной авторизации sloosh.
/// Чистый дизайн Apple TV / Liquid Glass:
/// - Нативная типографика San Francisco без костылей и вылетов за экран
/// - Плавный кинематографичный cross-dissolve переход кино-цитат
/// - Идеальная капсула «Продолжить с Google» с тактильным откликом
/// - Атмосферный кинотеатральный фон с акцентным неоновым ореолом slooshAccent
public struct CinematicAuthView: View {
    @ObservedObject private var authRepo = AuthRepository.shared

    public var onDismiss: (() -> Void)?

    private let phrases = [
        "Не только смотри, но и sloosh-ай",
        "Смотри глазами. sloosh-ай сердцем",
        "Твой личный кинозал в кармане",
        "Один клик — и ты уже в кино",
        "Кинотеатр, который всегда с тобой",
        "Залипнуть на все выходные? Легко",
        "Ещё одну серию и точно спать",
        "Тот самый фильм из сохранённых",
        "Кино, которое давно откладывали",
        "Сериал, который затянет с первой серии",
        "Что вышло в хорошем качестве?"
    ]

    @State private var phraseIndex: Int = 0
    @State private var auroraPulse: Bool = false

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    private var versionName: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1"
    }

    public var body: some View {
        ZStack {
            // MARK: - Атмосферный фон на весь экран
            cinematicBackground
                .ignoresSafeArea()

            // MARK: - Нативный контент внутри Safe Area
            VStack(spacing: 0) {
                // Верхняя панель: Логотип и опциональная кнопка закрытия
                topBarView
                    .padding(.top, 16)

                Spacer()

                // Центр: Кинематографичная кино-мысль
                ZStack {
                    Text(formattedPhrase(phrases[phraseIndex]))
                        .font(.system(size: 25, weight: .bold, design: .default))
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .frame(maxWidth: 320)
                        .id(phraseIndex)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.97)),
                            removal: .opacity.combined(with: .scale(scale: 1.02))
                        ))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 120)

                // Оповещение об ошибке (если есть)
                if let error = authRepo.lastError, !error.isEmpty {
                    errorNoticeView(error)
                        .padding(.top, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Spacer()

                // Кнопка авторизации через Google (строгая капсула с отступами)
                googleSignInButton
                    .frame(maxWidth: 360)

                // Пояснительная подпись
                Text("История просмотров и избранное сохранятся в вашем профиле")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
                    .padding(.top, 14)

                // Версия приложения
                Text("Версия \(versionName)")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
        .task {
            withAnimation(.easeInOut(duration: 6.5).repeatForever(autoreverses: true)) {
                auroraPulse = true
            }
            await runPhraseLoop()
        }
    }

    // MARK: - Top Bar

    private var topBarView: some View {
        HStack {
            Spacer()

            Image("LogoText")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(height: 24)
                .foregroundStyle(Color.slooshAccent)

            Spacer()
        }
        .overlay(alignment: .trailing) {
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
            }
        }
    }

    // MARK: - Google Sign-In Button

    private var googleSignInButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            authRepo.clearError()
            Task {
                _ = await authRepo.signInWithGoogle()
            }
        } label: {
            HStack(spacing: 12) {
                if authRepo.isLoading {
                    ProgressView()
                        .tint(.black)
                    Text("Авторизация...")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(Color.black)
                } else {
                    Image("GoogleLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)

                    Text("Продолжить через Google")
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(Color.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.white, in: Capsule())
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.35), radius: 14, x: 0, y: 6)
        }
        .disabled(authRepo.isLoading)
        .buttonStyle(AuthPressButtonStyle())
    }

    // MARK: - Error Notice View

    private func errorNoticeView(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                .font(.system(size: 15))
            Text(message)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 1.0, green: 0.27, blue: 0.23).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(red: 1.0, green: 0.27, blue: 0.23).opacity(0.25), lineWidth: 1)
        )
        .frame(maxWidth: 360)
    }

    // MARK: - Кинематографичный фон

    private var cinematicBackground: some View {
        ZStack {
            Color.black

            // Неоновое свечение slooshAccent (изумрудное)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.slooshAccent.opacity(0.24),
                            Color.slooshAccent.opacity(0.06),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 220
                    )
                )
                .frame(width: 440, height: 440)
                .offset(x: auroraPulse ? 30 : -30, y: auroraPulse ? -100 : -60)
                .blur(radius: 50)

            // Глубокий оттенок индиго снизу
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.12, green: 0.22, blue: 0.40).opacity(0.25),
                            Color(red: 0.12, green: 0.22, blue: 0.40).opacity(0.06),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 240
                    )
                )
                .frame(width: 460, height: 460)
                .offset(x: auroraPulse ? -40 : 40, y: auroraPulse ? 130 : 90)
                .blur(radius: 60)
        }
    }

    // MARK: - Плавный таймер смены реплик без костылей и мерцаний

    @MainActor
    private func runPhraseLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_800_000_000)
            if Task.isCancelled { break }
            withAnimation(.easeInOut(duration: 0.65)) {
                phraseIndex = (phraseIndex + 1) % phrases.count
            }
        }
    }

    // MARK: - Форматирование реплики с подсветкой sloosh-ай

    private func formattedPhrase(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.foregroundColor = Color.white.opacity(0.92)

        if let range = attr.range(of: "sloosh-ай", options: .caseInsensitive) {
            attr[range].foregroundColor = Color.slooshAccent
        } else if let range = attr.range(of: "sloosh", options: .caseInsensitive) {
            attr[range].foregroundColor = Color.slooshAccent
        }
        return attr
    }
}

// MARK: - Тактильная кнопка с мягким откликом

private struct AuthPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
