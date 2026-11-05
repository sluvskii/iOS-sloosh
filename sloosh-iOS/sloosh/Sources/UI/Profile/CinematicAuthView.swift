import SwiftUI
import UIKit

/// Флагманский нативный экран обязательной авторизации sloosh.
/// Чистый дизайн Apple TV / Liquid Glass:
/// - Безупречное позиционирование в Safe Area: логотип строго под Dynamic Island / чёлкой с комфортным отступом
/// - Последовательный выход слов из блюра с нативными переносами и мягкой сменой фраз
/// - Идеальная капсула «Продолжить через Google» с тактильным откликом
/// - Многослойный атмосферный фон с медленным движением света
public struct CinematicAuthView: View {
    @ObservedObject private var authRepo = AuthRepository.shared

    public var onDismiss: (() -> Void)?

    /// Сбалансированные кино-мысли, разбитые на естественные строки для идеальной типографики
    private let phrases = [
        "Не только смотри,\nно и sloosh-ай",
        "Смотри глазами.\nsloosh-ай сердцем",
        "Твой личный кинозал\nв кармане",
        "Один клик —\nи ты уже в кино",
        "Кинотеатр, который\nвсегда с тобой",
        "Залипнуть на все выходные?\nЛегко",
        "Ещё одну серию\nи точно спать",
        "Тот самый фильм\nиз сохранённых",
        "Кино, которое\nдавно откладывали",
        "Сериал, который затянет\nс первой серии",
        "Что вышло\nв хорошем качестве?"
    ]

    @State private var phraseIndex: Int = 0
    @State private var revealElapsed: Double = 0
    @State private var outgoingPhraseIndex: Int?
    @State private var outgoingOpacity: Double = 0
    @ScaledMetric(relativeTo: .title2) private var phraseScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase

    private var animatesPhrases: Bool {
        !reduceMotion && !voiceOverEnabled && scenePhase == .active
    }

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    private var versionName: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1"
    }

    public var body: some View {
        ZStack {
            // MARK: - Атмосферный фон на весь экран
            AuthCinematicBackground(accent: .slooshAccent)
                .ignoresSafeArea()

            // MARK: - Нативный контент строго внутри Safe Area (никогда не лезет под чёлку)
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Верхняя панель: Логотип под чёлкой/Dynamic Island
                    topBarView
                        .padding(.top, 14)
                        .modifier(AuthScreenEntrance(stage: .header))

                    Spacer()

                    // Центр: Кинематографичная кино-мысль с оптическим блюр-переходом
                    heroPhraseView
                        .frame(height: AuthPhraseLayout.heroHeight(availableHeight: geometry.size.height, scale: phraseScale))

                    // Оповещение об ошибке (если есть)
                    if let error = authRepo.lastError, !error.isEmpty {
                        errorNoticeView(error)
                            .padding(.top, 20)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    Spacer()

                    // Кнопка авторизации через Google (строгая капсула с отступами)
                    googleSignInButton
                        .frame(maxWidth: 360)
                        .modifier(AuthScreenEntrance(stage: .action))

                    // Пояснительная подпись
                    Text("История просмотров и избранное сохранятся в вашем профиле")
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(Color.white.opacity(0.60))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, 28)
                        .padding(.top, 14)
                        .modifier(AuthScreenEntrance(stage: .caption))

                    // Версия приложения
                    Text("Версия \(versionName)")
                        .font(.system(size: 11, weight: .regular, design: .default))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .modifier(AuthScreenEntrance(stage: .caption))
                }
                .padding(.horizontal, 24)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: animatesPhrases) {
            await runPhraseLoop(animated: animatesPhrases)
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
        }
    }

    // MARK: - Hero Phrase View

    private var heroPhraseView: some View {
        ZStack {
            if let outgoingPhraseIndex {
                AuthAnimatedPhrase(phrase: phrases[outgoingPhraseIndex],
                                   elapsed: AuthWordRevealPlan(phrases[outgoingPhraseIndex]).duration,
                                   accent: .slooshAccent, scale: phraseScale,
                                   phraseOpacity: outgoingOpacity, phraseBlur: (1 - outgoingOpacity) * 6)
                    .accessibilityHidden(true)
            }
            AuthAnimatedPhrase(phrase: phrases[phraseIndex], elapsed: revealElapsed, accent: .slooshAccent, scale: phraseScale)
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(authRepo.isLoading ? "Вход через Google" : "Продолжить через Google")
        .disabled(authRepo.isLoading)
        .buttonStyle(AuthPressButtonStyle())
    }

    // MARK: - Error Notice View

    private func errorNoticeView(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                .font(.system(size: 15))
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
    }

    // MARK: - Cancellable word reveal / phrase cycle

    @MainActor
    private func runPhraseLoop(animated: Bool) async {
        // Don't continually change a screen reader's content or animate with
        // Reduce Motion. Resume with a fresh reveal after foregrounding.
        guard animated else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                outgoingPhraseIndex = nil
                revealElapsed = AuthWordRevealPlan(phrases[phraseIndex]).duration
            }
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            outgoingPhraseIndex = nil
            revealElapsed = 0
        }
        while !Task.isCancelled {
            // Commit the zero-progress frame before animating to the end value;
            // otherwise SwiftUI may coalesce resets and reveal a whole phrase.
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard !Task.isCancelled else { return }
            let duration = AuthWordRevealPlan(phrases[phraseIndex]).duration
            withAnimation(.linear(duration: duration)) {
                revealElapsed = duration
            }
            withAnimation(.easeOut(duration: 0.5)) {
                outgoingOpacity = 0
            }
            do {
                // Hold starts after the last word is fully in focus.
                try await Task.sleep(for: .seconds(duration + 2.8))
            } catch { return }
            guard !Task.isCancelled else { return }
            withTransaction(transaction) {
                outgoingPhraseIndex = phraseIndex
                outgoingOpacity = 1
                phraseIndex = (phraseIndex + 1) % phrases.count
                revealElapsed = 0
            }
        }
    }
}
