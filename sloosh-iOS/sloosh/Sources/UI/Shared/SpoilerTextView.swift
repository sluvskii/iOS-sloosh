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
        let fine = CAEmitterCell()
        fine.contents = Self.speckleImage
        fine.contentsScale = 3.2
        fine.color = UIColor.white.cgColor
        fine.emissionRange = .pi * 2.0
        fine.lifetime = 1.0
        fine.lifetimeRange = 0.35
        fine.scale = 0.38
        fine.scaleRange = 0.3
        fine.velocity = 4.0
        fine.velocityRange = 20.0
        // Прозрачность у каждой пылинки своя: от еле заметной до плотной.
        fine.alphaRange = 0.85
        fine.alphaSpeed = -0.12
        fine.birthRate = 1
        fine.name = "dustFine"

        // Редкие более крупные и полностью непрозрачные крупинки — дают
        // ту самую «неоднородность» телеграмовской пыли.
        let bright = CAEmitterCell()
        bright.contents = Self.speckleImage
        bright.contentsScale = 2.6
        bright.color = UIColor.white.cgColor
        bright.emissionRange = .pi * 2.0
        bright.lifetime = 0.9
        bright.lifetimeRange = 0.3
        bright.scale = 0.52
        bright.scaleRange = 0.18
        bright.velocity = 3.0
        bright.velocityRange = 16.0
        bright.alphaRange = 0.15
        bright.alphaSpeed = -0.2
        bright.birthRate = 1
        bright.name = "dustBright"

        emitterLayer.emitterCells = [fine, bright]
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

        // Пылинок меньше: каждая заметнее, поле дышит, а не «шумит».
        let square = Float(bounds.width * bounds.height)
        let density = min(9_000, max(350, square * 0.35))
        emitterLayer.emitterCells?.first?.birthRate = density
        emitterLayer.emitterCells?.last?.birthRate = density * 0.12
    }

    func setActive(_ active: Bool) {
        emitterLayer.birthRate = active ? 1 : 0
    }

    // MARK: Speckle

    /// Крошечное мягкое зерно вместо ассета Telegram (TextSpeckle):
    /// радиальный градиент, чтобы пылинка не читалась как «кружок».
    private static func makeSpeckle() -> CGImage? {
        let size = CGSize(width: 6, height: 6)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            let colors = [
                UIColor.white.withAlphaComponent(1.0).cgColor,
                UIColor.white.withAlphaComponent(0.75).cgColor,
                UIColor.white.withAlphaComponent(0.0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.45, 1.0]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) else { return }

            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            cg.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: size.width / 2,
                options: []
            )
        }
        return image.cgImage
    }
}
