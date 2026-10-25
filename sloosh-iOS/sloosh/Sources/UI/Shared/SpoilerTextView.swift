import SwiftUI

// MARK: - SpoilerTextView (Telegram-style)

/// Текст под спойлером: размыт, накрыт полем живых частиц и бейджем
/// «Спойлер». Тап по блоку мягко раскрывает текст. Стейт в самом блоке —
/// как в Telegram: сворачивать обратно не нужно.
struct SpoilerTextView: View {
    let text: String
    var font: Font = .system(size: 14)
    var contentColor: Color = .white.opacity(0.85)
    var badgeSize: BadgeSize = .full

    enum BadgeSize {
        case full
        case preview
    }

    @State private var revealed = false

    var body: some View {
        Group {
            if revealed {
                Text(text)
                    .font(font)
                    .foregroundColor(contentColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .transition(.opacity)
            } else {
                hiddenBody
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: revealed)
    }

    private var hiddenBody: some View {
        Text(text)
            .font(font)
            .foregroundColor(.white.opacity(0.55))
            .lineLimit(badgeSize == .preview ? 1 : nil)
            .blur(radius: badgeSize == .preview ? 4.5 : 6.5)
            .overlay {
                SpoilerParticleField(seed: text.hashValue)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                badge
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                revealed = true
            }
            .accessibilityLabel("Скрытый спойлер. Нажмите, чтобы показать")
    }

    private var badge: some View {
        HStack(spacing: 5) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: badgeSize == .full ? 11 : 9, weight: .semibold))

            Text("Спойлер")
                .font(.system(size: badgeSize == .full ? 11 : 9.5, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, badgeSize == .full ? 9 : 6)
        .frame(height: badgeSize == .full ? 24 : 20)
        .background(Capsule().fill(Color.black.opacity(0.38)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

// MARK: - Redacted Preview Block

/// Компактный блок «скрытого» текста для превью (секция на экране детали):
/// полоски-строки под частицами с мини-бейджем, без реального текста.
struct SpoilerRedactedView: View {
    var seed: Int
    var lines: Int = 2

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .frame(width: lines > 1 ? 190 : 150, height: 8)
                    if lines > 1 {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 124, height: 8)
                    }
                }
                .blur(radius: 1.5)

                Spacer(minLength: 6)
            }
            .overlay {
                SpoilerParticleField(seed: seed)
            }

            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Спойлер")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Capsule().fill(Color.black.opacity(0.38)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Particle Field

/// Живое поле частиц в духе Telegram: детерминированные точки, дрейфующие
/// и мерцающие поверх скрытого текста. Рисуется на Canvas (дёшево),
/// работает только пока спойлер не раскрыт.
private struct SpoilerParticleField: View {
    var seed: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                guard size.width > 2, size.height > 2 else { return }

                let time = timeline.date.timeIntervalSinceReferenceDate
                let cell: Double = 9.0
                let cols = Int(ceil(size.width / cell))
                let rows = Int(ceil(size.height / cell))

                for row in 0..<rows {
                    for col in 0..<cols {
                        let index = row * cols + col
                        let r1 = random(offset: seed + index * 7, salt: 1)
                        let r2 = random(offset: seed + index * 7, salt: 2)
                        let r3 = random(offset: seed + index * 7, salt: 3)

                        var x = Double(col) * cell + r1 * cell
                        var y = Double(row) * cell + r2 * cell

                        // Медленный дрейф, чтобы поле «дышало».
                        x += sin(time * 0.55 + Double(index) * 0.7) * 1.6
                        y += cos(time * 0.4 + Double(index) * 1.1) * 1.6

                        // Мерцание: у каждой частицы своя фаза.
                        let phase = r3 * 2.0 * .pi
                        let wave = sin(time * 2.1 + phase)
                        if wave < 0.05 { continue }

                        let radius = 1.3 + r1 * 1.5
                        let alpha = 0.18 + 0.5 * wave
                        let rect = CGRect(
                            x: x - radius,
                            y: y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(Color.white.opacity(alpha))
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func random(offset: Int, salt: Int) -> Double {
        let value = sin(Double(offset &* 1013 &+ salt &* 7919) * 12.9898) * 43758.5453
        return value - floor(value)
    }
}
