import SwiftUI
import UIKit

/// Flagship Cinematic Auth View for sloosh.
/// Ported 1-to-1 from Android (AuthSheet.kt) with optical blur-reveal cinema thoughts,
/// atmospheric aurora background, and pure native Google Sign-In.
public struct CinematicAuthView: View {
    @ObservedObject private var authRepo = AuthRepository.shared
    @Environment(\.colorScheme) private var colorScheme

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

    @State private var currentPhrase: String = ""
    @State private var words: [String] = []
    @State private var revealedCount: Int = 0
    @State private var isDissolving: Bool = false

    @State private var auroraPulse: Bool = false

    public init() {}

    private var versionName: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1"
    }

    public var body: some View {
        ZStack {
            // Atmospheric cinematic background (breathing aurora orbs)
            cinematicBackground

            // Foreground content
            VStack(spacing: 0) {
                // Top Logo
                Image("LogoText")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 24)
                    .foregroundStyle(Color.slooshAccent)
                    .padding(.top, 48)

                Spacer()

                // Center Hero: Word-by-Word Blur Focus Reveal
                heroWordsRevealView
                    .padding(.horizontal, 28)

                // Error Notice (if any)
                if let error = authRepo.lastError, !error.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                            .font(.system(size: 15))
                        Text(error)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color(red: 1.0, green: 0.27, blue: 0.23))
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(red: 1.0, green: 0.27, blue: 0.23).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(red: 1.0, green: 0.27, blue: 0.23).opacity(0.25), lineWidth: 1)
                    )
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Spacer()

                // Google Sign-In Button
                googleSignInButton
                    .padding(.horizontal, 28)

                // Value proposition
                Text("История просмотров и избранное сохранятся в вашем профиле")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 32)
                    .padding(.top, 14)

                // App version
                Text("Версия \(versionName)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.38))
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea()
        .task {
            startPhraseAnimationLoop()
        }
    }

    // MARK: - Center Hero Words Flow

    private var heroWordsRevealView: some View {
        WrappingHStack(horizontalSpacing: 8, verticalSpacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                BlurRevealWord(
                    word: word,
                    isRevealed: revealedCount > index,
                    accentColor: Color.slooshAccent
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 120)
        .blur(radius: isDissolving ? 7 : 0)
        .opacity(isDissolving ? 0 : 1)
        .offset(y: isDissolving ? -8 : 0)
        .animation(.easeInOut(duration: 0.32), value: isDissolving)
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.black)
                } else {
                    Image("GoogleLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text("Продолжить через Google")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.white)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.20), radius: 12, x: 0, y: 6)
        }
        .disabled(authRepo.isLoading)
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Cinematic Background

    private var cinematicBackground: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.07)

            // Aurora Orb 1 (Emerald Accent)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.slooshAccent.opacity(0.18),
                            Color.slooshAccent.opacity(0.04),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 240
                    )
                )
                .frame(width: 480, height: 480)
                .offset(x: auroraPulse ? 40 : -40, y: auroraPulse ? -120 : -80)
                .blur(radius: 60)

            // Aurora Orb 2 (Deep Indigo / Teal)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.12, green: 0.22, blue: 0.38).opacity(0.22),
                            Color(red: 0.12, green: 0.22, blue: 0.38).opacity(0.05),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: auroraPulse ? -60 : 50, y: auroraPulse ? 160 : 120)
                .blur(radius: 70)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 7.0).repeatForever(autoreverses: true)) {
                auroraPulse.toggle()
            }
        }
    }

    // MARK: - Animation Loop

    private func startPhraseAnimationLoop() {
        Task {
            var playlist = phrases.shuffled()
            var playlistIndex = 0

            while !Task.isCancelled {
                let target = playlist[playlistIndex]
                await MainActor.run {
                    currentPhrase = target
                    words = target.split(separator: " ").map(String.init)
                    revealedCount = 0
                    isDissolving = false
                }

                try? await Task.sleep(nanoseconds: 280_000_000)

                for i in 1...words.count {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        revealedCount = i
                    }
                    let currentWord = words[i - 1]
                    let delayMs: UInt64
                    if currentWord.count <= 2 {
                        delayMs = 110
                    } else if currentWord.hasSuffix(".") || currentWord.hasSuffix("?") {
                        delayMs = 240
                    } else if currentWord.hasSuffix(",") || currentWord == "—" {
                        delayMs = 190
                    } else {
                        delayMs = 160
                    }
                    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                }

                // Crisp reading pause
                try? await Task.sleep(nanoseconds: 2_800_000_000)

                // Dissolve phase
                await MainActor.run {
                    isDissolving = true
                }
                try? await Task.sleep(nanoseconds: 380_000_000)

                playlistIndex += 1
                if playlistIndex >= playlist.count {
                    playlist = phrases.shuffled()
                    playlistIndex = 0
                }

                await MainActor.run {
                    revealedCount = 0
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}

// MARK: - BlurRevealWord

private struct BlurRevealWord: View {
    let word: String
    let isRevealed: Bool
    let accentColor: Color

    private var isSlooshWord: Bool {
        word.lowercased().contains("sloosh")
    }

    var body: some View {
        Text(word)
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(isSlooshWord ? accentColor : Color.white.opacity(0.88))
            .blur(radius: isRevealed ? 0 : 9)
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed ? 0 : 5)
            .animation(.easeOut(duration: 0.26), value: isRevealed)
    }
}

// MARK: - Wrapping Layout for Words

private struct WrappingHStack: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + horizontalSpacing
        }
        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Collect rows to center-align each row horizontally
        var rows: [[(subview: LayoutSubview, size: CGSize)]] = []
        var currentRow: [(subview: LayoutSubview, size: CGSize)] = []
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > bounds.width && !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = []
                currentRowWidth = 0
            }
            currentRow.append((subview, size))
            currentRowWidth += size.width + horizontalSpacing
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        var y = bounds.minY
        for row in rows {
            let rowContentWidth = row.map(\.size.width).reduce(0, +) + CGFloat(max(0, row.count - 1)) * horizontalSpacing
            var x = bounds.minX + max(0, (bounds.width - rowContentWidth) / 2)
            let maxHeight = row.map(\.size.height).max() ?? 0

            for item in row {
                item.subview.place(
                    at: CGPoint(x: x, y: y + (maxHeight - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += maxHeight + verticalSpacing
        }
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
