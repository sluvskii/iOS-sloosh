import SwiftUI
import UIKit

/// Флагманский нативный экран обязательной авторизации sloosh.
/// Чистый дизайн Apple TV / Liquid Glass (Сборка 2.1):
/// - Оптическое появление кино-цитат слово за словом из блюр-фокуса (как в ChatGPT / Claude)
/// - Идеальная типографика San Francisco без костылей и вылетов за пределы экрана
/// - Полноэкранный edge-to-edge лэйаут с нативным затемнением системных окон без смещений
/// - Идеальная капсула «Продолжить через Google» с тактильным откликом
/// - Дышащий кинематографичный фон с акцентным неоновым ореолом slooshAccent
public struct CinematicAuthView: View {
    @ObservedObject private var authRepo = AuthRepository.shared

    public var onDismiss: (() -> Void)?

    private struct PhraseQuote: Identifiable {
        let id: Int
        let lines: [[String]]

        var totalWords: Int {
            lines.reduce(0) { $0 + $1.count }
        }
    }

    /// Сбалансированные кино-мысли, разбитые на естественные строки для идеального переноса
    private let quotes: [PhraseQuote] = [
        PhraseQuote(id: 0, lines: [["Не", "только", "смотри,"], ["но", "и", "sloosh-ай"]]),
        PhraseQuote(id: 1, lines: [["Смотри", "глазами."], ["sloosh-ай", "сердцем"]]),
        PhraseQuote(id: 2, lines: [["Твой", "личный", "кинозал"], ["в", "кармане"]]),
        PhraseQuote(id: 3, lines: [["Один", "клик", "—"], ["и", "ты", "уже", "в", "кино"]]),
        PhraseQuote(id: 4, lines: [["Кинотеатр,", "который"], ["всегда", "с", "тобой"]]),
        PhraseQuote(id: 5, lines: [["Залипнуть", "на", "все", "выходные?"], ["Легко"]]),
        PhraseQuote(id: 6, lines: [["Ещё", "одну", "серию"], ["и", "точно", "спать"]]),
        PhraseQuote(id: 7, lines: [["Тот", "самый", "фильм"], ["из", "сохранённых"]]),
        PhraseQuote(id: 8, lines: [["Кино,", "которое"], ["давно", "откладывали"]]),
        PhraseQuote(id: 9, lines: [["Сериал,", "который", "затянет"], ["с", "первой", "серии"]]),
        PhraseQuote(id: 10, lines: [["Что", "вышло"], ["в", "хорошем", "качестве?"]])
    ]

    @State private var currentQuoteIndex: Int = 0
    @State private var revealedWordCount: Int = 0
    @State private var isDissolving: Bool = false
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

            // MARK: - Нативный контент внутри Safe Area
            VStack(spacing: 0) {
                // Верхняя панель: Логотип и опциональная кнопка закрытия
                topBarView
                    .padding(.top, 14)

                Spacer()

                // Центр: Кинематографичная мысль с оптическим появлением из блюр-фокуса
                heroPhraseContainer
                    .frame(maxWidth: 340)

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

                // Пояснительная подпись
                Text("История просмотров и избранное сохранятся в вашем профиле")
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 28)
                    .padding(.top, 14)

                // Версия приложения
                Text("Версия \(versionName)")
                    .font(.system(size: 11, weight: .regular, design: .default))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
            .safeAreaPadding(.vertical)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task {
            withAnimation(.easeInOut(duration: 6.5).repeatForever(autoreverses: true)) {
                auroraPulse = true
            }
            await runPhraseAnimationLoop()
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

    // MARK: - Hero Phrase Container (Оптический блюр-фокус)

    private var heroPhraseContainer: some View {
        let quote = quotes[currentQuoteIndex]

        return VStack(spacing: 8) {
            ForEach(0..<quote.lines.count, id: \.self) { lineIdx in
                let lineWords = quote.lines[lineIdx]
                let lineStartIndex = quote.lines.prefix(lineIdx).reduce(0) { $0 + $1.count }

                HStack(spacing: 7) {
                    ForEach(0..<lineWords.count, id: \.self) { wordIdx in
                        let word = lineWords[wordIdx]
                        let globalWordIndex = lineStartIndex + wordIdx

                        BlurRevealWord(
                            word: word,
                            isRevealed: revealedWordCount > globalWordIndex,
                            accentColor: Color.slooshAccent
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 110)
        .opacity(isDissolving ? 0 : 1)
        .blur(radius: isDissolving ? 8 : 0)
        .offset(y: isDissolving ? -6 : 0)
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

    // MARK: - Генеративный цикл пословной материализации из блюра без морганий

    @MainActor
    private func runPhraseAnimationLoop() async {
        var playlist = Array(0..<quotes.count).shuffled()
        var playlistIndex = 0

        while !Task.isCancelled {
            let quoteIdx = playlist[playlistIndex]
            currentQuoteIndex = quoteIdx
            revealedWordCount = 0
            isDissolving = false

            let quote = quotes[quoteIdx]

            // 1. Короткая пауза перед началом материализации
            try? await Task.sleep(nanoseconds: 240_000_000)
            if Task.isCancelled { break }

            // 2. Последовательно открываем каждое слово из блюра в фокус
            for wordIndex in 1...quote.totalWords {
                revealedWordCount = wordIndex

                let wordDelay: UInt64
                if wordIndex == quote.totalWords {
                    wordDelay = 100_000_000
                } else {
                    wordDelay = 180_000_000
                }

                try? await Task.sleep(nanoseconds: wordDelay)
                if Task.isCancelled { break }
            }
            if Task.isCancelled { break }

            // 3. Фаза чтения (3.0 секунды в идеальном фокусе)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { break }

            // 4. Плавное растворение цитаты в блюр (350 мс)
            withAnimation(.easeInOut(duration: 0.35)) {
                isDissolving = true
            }
            try? await Task.sleep(nanoseconds: 380_000_000)
            if Task.isCancelled { break }

            // 5. Переход к следующей фразе
            playlistIndex += 1
            if playlistIndex >= playlist.count {
                playlist = Array(0..<quotes.count).shuffled()
                playlistIndex = 0
            }
        }
    }
}

// MARK: - BlurRevealWord (Оптическая фокусировка слова)

private struct BlurRevealWord: View {
    let word: String
    let isRevealed: Bool
    let accentColor: Color

    private var isSlooshWord: Bool {
        word.lowercased().contains("sloosh")
    }

    var body: some View {
        Text(word)
            .font(.system(size: 25, weight: .bold, design: .default))
            .foregroundStyle(isSlooshWord ? accentColor : Color.white.opacity(0.92))
            .blur(radius: isRevealed ? 0 : 8)
            .opacity(isRevealed ? 1 : 0)
            .scaleEffect(isRevealed ? 1.0 : 0.94)
            .offset(y: isRevealed ? 0 : 4)
            .animation(.easeOut(duration: 0.28), value: isRevealed)
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
