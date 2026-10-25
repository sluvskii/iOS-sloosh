import SwiftUI
import UIKit

// MARK: - SpoilerTextView (Telegram dust, like InvisibleInkDustNode)

/// Текст под спойлером, как в Telegram: сам текст скрыт, а его место
/// занимает облако мерцающих «пылинок» (CAEmitterLayer + TextSpeckle).
/// Тап мягко растворяет пыль и проявляет текст.
struct SpoilerTextView: View {
    let text: String
    var font: Font = .system(size: 14)
    var contentColor: Color = .white.opacity(0.85)

    @State private var revealed = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(contentColor)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(revealed ? 1 : 0)
            .overlay {
                if !revealed {
                    SpoilerDustOverlay()
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !revealed else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.easeOut(duration: 0.22)) {
                    revealed = true
                }
            }
            .modifier(SpoilerSelectionModifier(isEnabled: revealed))
            .accessibilityLabel(revealed ? text : "Скрытый спойлер. Нажмите, чтобы показать")
    }
}

// MARK: - Conditional selection

/// `.textSelection` принимает статический тип, поэтому переключаем модификатором.
private struct SpoilerSelectionModifier: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.textSelection(.enabled)
        } else {
            content.textSelection(.disabled)
        }
    }
}

// MARK: - Redacted Preview Block
/// Компактный блок для превью в секции на экране детали: то же облако пыли
/// и мини-бейдж «Спойлер». Реального текста тут нет вовсе.
struct SpoilerRedactedView: View {
    var body: some View {
        ZStack {
            SpoilerDustOverlay()

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
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            }
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }
}

// MARK: - Dust Overlay

/// Слой пыли поверх скрытого текста. Параметры повторяют Telegram:
/// speckle-текстура 1.8 contentsScale, scale 0.5, lifetime 1s,
/// плотность ≈ площадь × 0.35.
private struct SpoilerDustOverlay: UIViewRepresentable {
    func makeUIView(context: Context) -> SpoilerDustEmitterView {
        let view = SpoilerDustEmitterView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: SpoilerDustEmitterView, context: Context) {}
}

final class SpoilerDustEmitterView: UIView {
    override class var layerClass: AnyClass { CAEmitterLayer.self }

    private var emitterLayer: CAEmitterLayer {
        layer as! CAEmitterLayer
    }

    private static let speckleImage: CGImage? = SpoilerDustEmitterView.makeSpeckle()

    override init(frame: CGRect = .zero) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        let cell = CAEmitterCell()
        cell.contents = Self.speckleImage
        cell.contentsScale = 1.8
        cell.color = UIColor.white.cgColor
        cell.emissionRange = .pi * 2.0
        cell.lifetime = 1.0
        cell.lifetimeRange = 0.25
        cell.scale = 0.5
        cell.scaleRange = 0.22
        cell.velocity = 4.0
        cell.velocityRange = 20.0
        cell.alphaRange = 1.0
        cell.birthRate = 1
        cell.name = "dustCell"

        emitterLayer.emitterCells = [cell]
        emitterLayer.emitterShape = .rectangle
        emitterLayer.emitterMode = .volume
        emitterLayer.emitterPosition = .zero
        emitterLayer.emitterSize = .zero
        emitterLayer.birthRate = 1
        emitterLayer.seed = UInt32.random(in: 1...UInt32.max)
        emitterLayer.drawsAsynchronously = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        emitterLayer.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        emitterLayer.emitterSize = CGSize(width: max(bounds.width, 1), height: max(bounds.height, 1))

        // Плотность как в Telegram: квадрат площади × 0.35.
        let square = Float(bounds.width * bounds.height)
        emitterLayer.emitterCells?.first?.birthRate = min(60_000, max(300, square * 0.35))
    }

    func setActive(_ active: Bool) {
        emitterLayer.birthRate = active ? 1 : 0
    }

    // MARK: Speckle

    /// Крошечная мягкая пылинка вместо ассета Telegram (TextSpeckle).
    private static func makeSpeckle() -> CGImage? {
        let size = CGSize(width: 8, height: 8)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let rect = CGRect(x: 1.5, y: 1.5, width: 5, height: 5)
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in: rect)
        }
        return image.cgImage
    }
}
