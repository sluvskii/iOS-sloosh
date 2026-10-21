import SwiftUI
import UIKit
import QuartzCore

/// Создает эффект прогрессивного размытия (Liquid Glass) в стиле iOS 27:
///  1. Базовый проход — прогрессивный блюр, плавно затухающий от полного к нулю.
///  2. Диффузионный проход-«ореол» — второй, более сильный блюр с растушёванной
///     (ease-out) маской, частичной прозрачностью и выходом ЗА границы бара.
///     Размытый контент начинает «рассеиваться» за краем бара, создавая мягкий
///     световой ореол (bloom) вокруг резкого контента — дорогой системный эффект.
///
/// Реализация скопирована из Telegram-iOS с обходом приватного API (CAFilter variableBlur).
public struct VariableBlurView: View {
    public var maxBlurRadius: CGFloat = 2
    public var direction: VariableBlurRepresentable.BlurDirection = .blurredTopClearBottom
    public var tintColor: Color = Color(UIColor.systemBackground)
    public var tintOpacity: Double = 1.0
    public var style: UIBlurEffect.Style = .systemMaterial
    /// Сила диффузионного ореола: прозрачность второго прохода (0 — выключить).
    public var haloIntensity: Double = 0.55
    /// Насколько далеко (в долях размера) ореол выходит за границу блюра.
    public var haloSpread: CGFloat = 0.6
    /// Во сколько раз радиус блюра ореола больше базового.
    public var haloRadiusBoost: CGFloat = 3.0

    public init(
        maxBlurRadius: CGFloat = 2,
        direction: VariableBlurRepresentable.BlurDirection = .blurredTopClearBottom,
        tintColor: Color = Color(UIColor.systemBackground),
        tintOpacity: Double = 1.0,
        style: UIBlurEffect.Style = .systemMaterial,
        haloIntensity: Double = 0.55,
        haloSpread: CGFloat = 0.6,
        haloRadiusBoost: CGFloat = 3.0
    ) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.style = style
        self.haloIntensity = haloIntensity
        self.haloSpread = haloSpread
        self.haloRadiusBoost = haloRadiusBoost
    }

    public var body: some View {
        VariableBlurRepresentable(
            maxBlurRadius: maxBlurRadius,
            direction: direction,
            style: style,
            haloIntensity: haloIntensity,
            haloSpread: haloSpread,
            haloRadiusBoost: haloRadiusBoost
        )
        .overlay(
            LinearGradient(
                colors: {
                    switch direction {
                    case .blurredTopClearBottom, .blurredLeadingClearTrailing:
                        return [tintColor.opacity(tintOpacity), tintColor.opacity(0.0)]
                    case .blurredBottomClearTop, .blurredTrailingClearLeading:
                        return [tintColor.opacity(0.0), tintColor.opacity(tintOpacity)]
                    }
                }(),
                startPoint: {
                    switch direction {
                    case .blurredTopClearBottom, .blurredBottomClearTop: return .top
                    case .blurredLeadingClearTrailing, .blurredTrailingClearLeading: return .leading
                    }
                }(),
                endPoint: {
                    switch direction {
                    case .blurredTopClearBottom, .blurredBottomClearTop: return .bottom
                    case .blurredLeadingClearTrailing, .blurredTrailingClearLeading: return .trailing
                    }
                }()
            )
        )
        .allowsHitTesting(false)
    }
}

public struct VariableBlurRepresentable: UIViewRepresentable {
    public var maxBlurRadius: CGFloat = 2
    public var direction: BlurDirection = .blurredTopClearBottom
    public var style: UIBlurEffect.Style = .systemMaterial
    public var haloIntensity: Double = 0.55
    public var haloSpread: CGFloat = 0.6
    public var haloRadiusBoost: CGFloat = 3.0

    public enum BlurDirection {
        case blurredTopClearBottom
        case blurredBottomClearTop
        case blurredLeadingClearTrailing
        case blurredTrailingClearLeading
    }

    public init(
        maxBlurRadius: CGFloat = 2,
        direction: BlurDirection = .blurredTopClearBottom,
        style: UIBlurEffect.Style = .systemMaterial,
        haloIntensity: Double = 0.55,
        haloSpread: CGFloat = 0.6,
        haloRadiusBoost: CGFloat = 3.0
    ) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        self.style = style
        self.haloIntensity = haloIntensity
        self.haloSpread = haloSpread
        self.haloRadiusBoost = haloRadiusBoost
    }

    public func makeUIView(context: Context) -> VariableBlurUIView {
        return VariableBlurUIView(
            maxBlurRadius: maxBlurRadius,
            direction: direction,
            style: style,
            haloIntensity: haloIntensity,
            haloSpread: haloSpread,
            haloRadiusBoost: haloRadiusBoost
        )
    }

    public func updateUIView(_ uiView: VariableBlurUIView, context: Context) {
        if uiView.maxBlurRadius != maxBlurRadius || uiView.direction != direction || uiView.style != style
            || uiView.haloIntensity != haloIntensity || uiView.haloSpread != haloSpread || uiView.haloRadiusBoost != haloRadiusBoost {
            uiView.maxBlurRadius = maxBlurRadius
            uiView.direction = direction
            uiView.style = style
            uiView.haloIntensity = haloIntensity
            uiView.haloSpread = haloSpread
            uiView.haloRadiusBoost = haloRadiusBoost
        }
    }
}

public final class VariableBlurUIView: UIVisualEffectView {
    public var style: UIBlurEffect.Style {
        didSet {
            self.effect = UIBlurEffect(style: style)
            resetEffect()
        }
    }

    public var maxBlurRadius: CGFloat {
        didSet {
            resetEffect()
        }
    }

    public var direction: VariableBlurRepresentable.BlurDirection {
        didSet {
            resetEffect()
            setNeedsLayout()
        }
    }

    /// Сила диффузионного ореола (0 — выключить второй проход).
    public var haloIntensity: Double {
        didSet {
            resetEffect()
            setNeedsLayout()
        }
    }

    /// Насколько далеко ореол выходит за границу блюра (доля от размера).
    public var haloSpread: CGFloat {
        didSet {
            resetEffect()
            setNeedsLayout()
        }
    }

    /// Во сколько раз радиус блюра ореола больше базового.
    public var haloRadiusBoost: CGFloat {
        didSet {
            resetEffect()
        }
    }

    private let haloEffectView = UIVisualEffectView(effect: nil)
    /// Периодическая проверка целостности приватных фильтров (их срывает
    /// пересоздание backdrop-слоя после переходов/модалок/плеера).
    private var healthTimer: Timer?

    public init(
        maxBlurRadius: CGFloat = 2,
        direction: VariableBlurRepresentable.BlurDirection = .blurredTopClearBottom,
        style: UIBlurEffect.Style = .systemMaterial,
        haloIntensity: Double = 0.55,
        haloSpread: CGFloat = 0.6,
        haloRadiusBoost: CGFloat = 3.0
    ) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        self.style = style
        self.haloIntensity = haloIntensity
        self.haloSpread = haloSpread
        self.haloRadiusBoost = haloRadiusBoost
        super.init(effect: UIBlurEffect(style: style))

        if self.subviews.indices.contains(1) {
            let tintOverlayView = subviews[1]
            tintOverlayView.alpha = 0
        }

        // Диффузионный проход-ореол: дочерний blur-вью, выходящий за границы
        // базового прохода. ВАЖНО: сабвью UIVisualEffectView добавляются только
        // в contentView — прямое addSubview в effect view роняет приложение.
        haloEffectView.isUserInteractionEnabled = false
        haloEffectView.clipsToBounds = false
        contentView.addSubview(haloEffectView)
        contentView.clipsToBounds = false

        // После закрытия fullScreenCover (плеер/шиты) хуки layout/didMoveToWindow
        // у нижнего экрана не гарантированы — чиним фильтры на активацию приложения
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        self.resetEffect()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        haloEffectView.frame = haloFrame()
        healLostFiltersIfNeeded(force: false)
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            healLostFiltersIfNeeded(force: false)
            scheduleDelayedHeals()
            startHealthTimer()
        } else {
            stopHealthTimer()
        }
    }

    @objc private func appDidBecomeActive() {
        guard window != nil else { return }
        // Активация после плеера/модалок — слой мог быть пересоздан, ставим заново
        healLostFiltersIfNeeded(force: true)
    }

    deinit {
        healthTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Private Filter Self-Healing

    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.healLostFiltersIfNeeded(force: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    private func stopHealthTimer() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    /// Закрытие плеера/шитов не всегда вызывает layout у нижнего экрана —
    /// добиваем восстанавлением через короткие задержки.
    private func scheduleDelayedHeals() {
        for delay in [0.2, 0.6, 1.2] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, self.window != nil else { return }
                self.healLostFiltersIfNeeded(force: true)
            }
        }
    }

    /// Если UIKit пересоздал backdrop-слой (переходы, закрытие fullScreenCover
    /// плеера) — приватный фильтр variableBlur теряется, и эффект вырождается
    /// в тёмный прямоугольник с жёсткими краями. Переустанавливаем.
    private func healLostFiltersIfNeeded(force: Bool) {
        guard window != nil, bounds.width > 0, bounds.height > 0 else { return }

        func filtersMissing(_ layer: CALayer?) -> Bool {
            guard let filters = layer?.value(forKey: "filters") as? [Any] else { return true }
            return filters.isEmpty
        }

        if force || filtersMissing(subviews.first?.layer) {
            // Полный сброс перед установкой: одинаковый объект фильтра на
            // пересозданном слое мог не перезапустить рендер блюра
            subviews.first?.layer.setValue(nil, forKey: "filters")
            Self.applyVariableBlur(
                to: self,
                radius: maxBlurRadius,
                direction: direction,
                easing: .linear
            )
        }

        if haloIntensity > 0, haloEffectView.superview != nil {
            if force || filtersMissing(haloEffectView.subviews.first?.layer) {
                haloEffectView.subviews.first?.layer.setValue(nil, forKey: "filters")
                Self.applyVariableBlur(
                    to: haloEffectView,
                    radius: maxBlurRadius * haloRadiusBoost,
                    direction: direction,
                    easing: .easeOut
                )
            }
        }
    }

    private func haloFrame() -> CGRect {
        let spill: CGFloat
        switch direction {
        case .blurredTopClearBottom, .blurredBottomClearTop:
            spill = bounds.height * haloSpread
        case .blurredLeadingClearTrailing, .blurredTrailingClearLeading:
            spill = bounds.width * haloSpread
        }

        switch direction {
        case .blurredTopClearBottom:
            // Блюр сверху → ореол тянется вниз за пределы бара
            return CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height + spill)
        case .blurredBottomClearTop:
            // Блюр снизу → ореол тянется вверх
            return CGRect(x: 0, y: -spill, width: bounds.width, height: bounds.height + spill)
        case .blurredLeadingClearTrailing:
            return CGRect(x: 0, y: 0, width: bounds.width + spill, height: bounds.height)
        case .blurredTrailingClearLeading:
            return CGRect(x: -spill, y: 0, width: bounds.width + spill, height: bounds.height)
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if #available(iOS 13.0, *) {
            if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                self.resetEffect()
            }
        }
    }

    // MARK: - Effect Configuration

    private func resetEffect() {
        // 1. Базовый прогрессивный проход (линейная маска) — как раньше
        Self.applyVariableBlur(
            to: self,
            radius: maxBlurRadius,
            direction: direction,
            easing: .linear
        )

        // 2. Диффузионный проход-ореол: радиус ×boost, ease-out маска с длинным
        //    мягким хвостом, частичная прозрачность, выход за границы
        guard haloIntensity > 0 else {
            haloEffectView.effect = nil
            Self.applyVariableBlur(to: haloEffectView, radius: 0, direction: direction, easing: .linear, clear: true)
            if haloEffectView.superview != nil {
                haloEffectView.removeFromSuperview()
            }
            return
        }

        if haloEffectView.superview == nil {
            contentView.addSubview(haloEffectView)
        }
        haloEffectView.effect = UIBlurEffect(style: style)
        Self.applyVariableBlur(
            to: haloEffectView,
            radius: maxBlurRadius * haloRadiusBoost,
            direction: direction,
            easing: .easeOut
        )
        haloEffectView.alpha = CGFloat(haloIntensity)
        haloEffectView.frame = haloFrame()
    }

    // MARK: - Private CAFilter variableBlur Engine

    private enum MaskEasing {
        case linear
        case easeOut
    }

    private static func applyVariableBlur(
        to view: UIVisualEffectView,
        radius: CGFloat,
        direction: VariableBlurRepresentable.BlurDirection,
        easing: MaskEasing,
        clear: Bool = false
    ) {
        let filterClassStringEncoded = "Q0FGaWx0ZXI="
        let filterClassString: String = {
            if let data = Data(base64Encoded: filterClassStringEncoded),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return ""
        }()
        let filterWithTypeStringEncoded = "ZmlsdGVyV2l0aFR5cGU6"
        let filterWithTypeString: String = {
            if let data = Data(base64Encoded: filterWithTypeStringEncoded),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return ""
        }()

        let filterWithTypeSelector = Selector(filterWithTypeString)

        guard let filterClass = NSClassFromString(filterClassString) as AnyObject as? NSObjectProtocol else {
            return
        }

        guard filterClass.responds(to: filterWithTypeSelector) else {
            return
        }

        let variableBlur = filterClass.perform(filterWithTypeSelector, with: "variableBlur").takeUnretainedValue()

        guard let variableBlur = variableBlur as? NSObject else {
            return
        }

        guard clear == false, let gradientImageRef = createMaskImage(direction: direction, easing: easing) else {
            // Полный сброс фильтров (проход-ореол выключен)
            let backdropLayer = view.subviews.first?.layer
            backdropLayer?.filters = nil
            return
        }

        variableBlur.setValue(radius, forKey: "inputRadius")
        variableBlur.setValue(gradientImageRef, forKey: "inputMaskImage")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")

        let backdropLayer = view.subviews.first?.layer
        backdropLayer?.filters = [variableBlur]
        let scale = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.scale ?? 3.0
        backdropLayer?.setValue(scale, forKey: "scale")
    }

    /// Маска блюра. `.linear` — прежнее поведение (жёсткий линейный спад).
    /// `.easeOut` — растушёванный спад с длинным мягким хвостом: блюр держится
    /// сильным у края и долго «тлеет», создавая ореол рассеивания.
    private static func createMaskImage(direction: VariableBlurRepresentable.BlurDirection, easing: MaskEasing) -> CGImage? {
        let isHorizontal = (direction == .blurredLeadingClearTrailing || direction == .blurredTrailingClearLeading)
        let size: CGFloat = 256
        let width: CGFloat = isHorizontal ? size : 1
        let height: CGFloat = isHorizontal ? 1 : size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: Int(width) * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }

        // Прозрачность маски по нормированной дистанции от края блюра
        let alphas: [(location: CGFloat, alpha: CGFloat)]
        switch easing {
        case .linear:
            alphas = [(0.0, 1.0), (1.0, 0.0)]
        case .easeOut:
            // Сконцентрирован у края (там, где живой контент) и полностью
            // затухает раньше конца — без блёклого хвоста через весь бар
            alphas = [
                (0.0, 1.0),
                (0.14, 0.92),
                (0.32, 0.55),
                (0.50, 0.22),
                (0.68, 0.0),
                (1.0, 0.0)
            ]
        }

        let colors = alphas.map { location, alpha in
            UIColor(white: 0, alpha: alpha).cgColor
        } as CFArray
        let locations = alphas.map { $0.location }
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
            return nil
        }

        let startPoint: CGPoint
        let endPoint: CGPoint

        switch direction {
        case .blurredTopClearBottom:
            startPoint = CGPoint(x: 0, y: height)
            endPoint = CGPoint(x: 0, y: 0)
        case .blurredBottomClearTop:
            startPoint = CGPoint(x: 0, y: 0)
            endPoint = CGPoint(x: 0, y: height)
        case .blurredLeadingClearTrailing:
            startPoint = CGPoint(x: 0, y: 0)
            endPoint = CGPoint(x: width, y: 0)
        case .blurredTrailingClearLeading:
            startPoint = CGPoint(x: width, y: 0)
            endPoint = CGPoint(x: 0, y: 0)
        }

        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
        return context.makeImage()
    }
}
