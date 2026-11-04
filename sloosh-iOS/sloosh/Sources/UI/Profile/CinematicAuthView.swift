import SwiftUI
import UIKit

/// Flagship Cinematic Auth View for sloosh.
/// Inspired by ChatGPT & Claude: dynamic typewriter cinema quotes with optical blur reveal,
/// atmospheric cinematic aurora orbs, and native Google Sign-In.
public struct CinematicAuthView: View {
    @ObservedObject private var authRepo = AuthRepository.shared

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

    private struct PhraseState: Equatable {
        let id: String
        let text: String
        let words: [String]
    }

    @State private var activePhrase: PhraseState = PhraseState(id: "init", text: "", words: [])
    @State private var revealedCount: Int = 0
    @State private var isDissolving: Bool = false
    @State private var auroraPulse: Bool = false

    public var onDismiss: (() -> Void)?

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    private var versionName: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1"
    }

    public var body: some View {
        ZStack {
            // MARK: - Atmospheric Background (Full Screen)
            cinematicBackground
                .ignoresSafeArea()

            // MARK: - Foreground Content (Strictly Safe-Area Bound)
            VStack(spacing: 0) {
                // Top Bar with Logo and optional close button
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
                        .padding(.trailing, 20)
                    }
                }
                .padding(.top, 24)

                Spacer()

                // Center Hero: Cinematic Phrase with Blur-Reveal
                heroPhraseContainer
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 400)

                // Error Notice (if any)
                if let error = authRepo.lastError, !error.isEmpty {
                    errorNoticeView(error)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .frame(maxWidth: 400)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Spacer()

                // Google Sign-In Button
                googleSignInButton
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 380)

                // Value proposition
                Text("История просмотров и избранное сохранятся в вашем профиле")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
                    .padding(.top, 14)

                // App version
                Text("Версия \(versionName)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.32))
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
        .task {
            startPhraseAnimationLoop()
        }
    }

    // MARK: - Hero Phrase Container

    private var heroPhraseContainer: some View {
        AuthPhraseFlowLayout(horizontalSpacing: 7, verticalSpacing: 6, alignment: .center) {
            ForEach(Array(activePhrase.words.enumerated()), id: \.offset) { index, word in
                BlurRevealWord(
                    word: word,
                    isRevealed: revealedCount > index,
                    accentColor: Color.slooshAccent
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 110)
        .blur(radius: isDissolving ? 8 : 0)
        .opacity(isDissolving ? 0 : 1)
        .offset(y: isDissolving ? -6 : 0)
        .animation(.easeInOut(duration: 0.35), value: isDissolving)
    }

    // MARK: - Google Sign-In Button (Perfect Pill with Capsule Shape)

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
            .frame(height: 54)
            .background(Color.white, in: Capsule())
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 7)
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
                .font(.system(size: 13, weight: .regular))
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
    }

    // MARK: - Cinematic Aurora Background

    private var cinematicBackground: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07)

            // Aurora Orb 1 (Emerald Accent)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.slooshAccent.opacity(0.20),
                            Color.slooshAccent.opacity(0.05),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 220
                    )
                )
                .frame(width: 440, height: 440)
                .offset(x: auroraPulse ? 35 : -35, y: auroraPulse ? -110 : -70)
                .blur(radius: 50)

            // Aurora Orb 2 (Deep Indigo / Teal)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.12, green: 0.22, blue: 0.40).opacity(0.24),
                            Color(red: 0.12, green: 0.22, blue: 0.40).opacity(0.06),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 240
                    )
                )
                .frame(width: 480, height: 480)
                .offset(x: auroraPulse ? -50 : 45, y: auroraPulse ? 140 : 100)
                .blur(radius: 60)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 6.5).repeatForever(autoreverses: true)) {
                auroraPulse.toggle()
            }
        }
    }

    // MARK: - Seamless Optical Animation Loop (Zero Flicker)

    private func startPhraseAnimationLoop() {
        Task {
            var playlist = phrases.shuffled()
            var playlistIndex = 0

            while !Task.isCancelled {
                let targetText = playlist[playlistIndex]
                let targetWords = targetText.split(separator: " ").map(String.init)
                let newPhrase = PhraseState(id: UUID().uuidString, text: targetText, words: targetWords)

                // 1. Mount new phrase under total invisibility
                await MainActor.run {
                    activePhrase = newPhrase
                    revealedCount = 0
                }

                // Small pause for layout mounting
                try? await Task.sleep(nanoseconds: 120_000_000)

                // 2. Fade in container smoothly
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.20)) {
                        isDissolving = false
                    }
                }

                try? await Task.sleep(nanoseconds: 200_000_000)

                // 3. Sequentially reveal words from blur
                for i in 1...targetWords.count {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        revealedCount = i
                    }
                    let currentWord = targetWords[i - 1]
                    let delayMs: UInt64
                    if currentWord.count <= 2 {
                        delayMs = 110
                    } else if currentWord.hasSuffix(".") || currentWord.hasSuffix("?") {
                        delayMs = 240
                    } else if currentWord.hasSuffix(",") || currentWord == "—" {
                        delayMs = 190
                    } else {
                        delayMs = 150
                    }
                    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                }

                // 4. Crisp reading pause (2.8 seconds)
                try? await Task.sleep(nanoseconds: 2_800_000_000)

                // 5. Dissolve phase: entire phrase dissolves away completely
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isDissolving = true
                    }
                }
                // Wait for dissolve animation to fully complete
                try? await Task.sleep(nanoseconds: 400_000_000)

                // Advance to next phrase
                playlistIndex += 1
                if playlistIndex >= playlist.count {
                    playlist = phrases.shuffled()
                    playlistIndex = 0
                }
            }
        }
    }
}

// MARK: - BlurRevealWord (Optical Focus Transition)

private struct BlurRevealWord: View {
    let word: String
    let isRevealed: Bool
    let accentColor: Color

    private var isSlooshWord: Bool {
        word.lowercased().contains("sloosh")
    }

    var body: some View {
        Text(word)
            .font(.system(size: 23, weight: .bold, design: .default))
            .foregroundStyle(isSlooshWord ? accentColor : Color.white.opacity(0.92))
            .blur(radius: isRevealed ? 0 : 7)
            .opacity(isRevealed ? 1 : 0)
            .scaleEffect(isRevealed ? 1.0 : 0.95)
            .offset(y: isRevealed ? 0 : 3)
            .animation(.easeOut(duration: 0.24), value: isRevealed)
    }
}

// MARK: - AuthPhraseFlowLayout (Guaranteed Zero-Overflow Horizontal Flow)

private struct AuthPhraseFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 7
    var verticalSpacing: CGFloat = 6
    var alignment: TextAlignment = .center

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var totalHeight: CGFloat = 0
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let neededWidth = currentRowWidth == 0 ? size.width : (currentRowWidth + horizontalSpacing + size.width)

            if neededWidth > maxWidth && currentRowWidth > 0 {
                totalHeight += currentRowHeight + verticalSpacing
                currentRowWidth = size.width
                currentRowHeight = size.height
            } else {
                currentRowWidth = neededWidth
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }
        totalHeight += currentRowHeight
        return CGSize(width: maxWidth, height: max(totalHeight, 100))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var rows: [[(subview: LayoutSubview, size: CGSize)]] = []
        var currentRow: [(subview: LayoutSubview, size: CGSize)] = []
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let neededWidth = currentRow.isEmpty ? size.width : (currentRowWidth + horizontalSpacing + size.width)

            if neededWidth > maxWidth && !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = [(subview, size)]
                currentRowWidth = size.width
            } else {
                currentRow.append((subview, size))
                currentRowWidth = neededWidth
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        var y = bounds.minY
        for row in rows {
            let rowContentWidth = row.map(\.size.width).reduce(0, +) + CGFloat(max(0, row.count - 1)) * horizontalSpacing
            let rowHeight = row.map(\.size.height).max() ?? 0

            var x: CGFloat = bounds.minX
            if alignment == .center {
                x = bounds.minX + max(0, (bounds.width - rowContentWidth) / 2)
            }

            for item in row {
                item.subview.place(
                    at: CGPoint(x: x, y: y + (rowHeight - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += rowHeight + verticalSpacing
        }
    }
}

// MARK: - AuthPressButtonStyle

private struct AuthPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}
