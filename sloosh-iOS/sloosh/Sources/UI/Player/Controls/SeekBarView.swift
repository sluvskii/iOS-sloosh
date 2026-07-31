import SwiftUI

// MARK: - Seek Bar с нативным Liquid Glass (iOS 26)

struct SeekBarView: View {
    @ObservedObject var vm: PlayerViewModel
    @Binding var isInteracting: Bool
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var isHStackScrubbing = false
    @State private var screenScrubInitialTime: Double = 0
    @State private var scrubStartLocationX: CGFloat = 0
    @State private var sliderWidth: CGFloat = 260

    private var progress: Double {
        guard vm.currentDuration > 0 else { return 0 }
        if let scrub = vm.screenScrubTime { return scrub / vm.currentDuration }
        return isDragging ? dragProgress : (vm.currentTime / vm.currentDuration)
    }

    private var displayTime: Double {
        if let scrub = vm.screenScrubTime { return scrub }
        return isDragging ? (dragProgress * vm.currentDuration) : vm.currentTime
    }

    var body: some View {
        VStack(spacing: 12) {
            // Плавающая карточка превью
            if isDragging || isHStackScrubbing || vm.screenScrubTime != nil {
                let ratio = max(0.5, min(2.4, vm.scrubPreviewAspectRatio))
                let cardWidth: CGFloat = 132
                let cardHeight: CGFloat = min(88, max(52, cardWidth / ratio))
                
                // Вычисляем офсет карточки ровно над пальцем пользователя
                let rawThumbX = CGFloat(progress) * sliderWidth
                let centerSliderX = sliderWidth / 2
                let rawOffset = rawThumbX - centerSliderX
                let maxAllowedOffset = max(0, (sliderWidth - cardWidth) / 2)
                let cardOffset = max(-maxAllowedOffset, min(maxAllowedOffset, rawOffset))

                ZStack {
                    if let preview = vm.scrubPreviewImage {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(ratio, contentMode: .fit)
                            .frame(width: cardWidth, height: cardHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        ZStack {
                            Rectangle()
                                .fill(Color.black.opacity(0.6))
                            
                            if let logoUrl = vm.displayLogoUrl {
                                AsyncCachedImage(url: logoUrl) { img in
                                    img.resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .padding(12)
                                } placeholder: {
                                    Image(systemName: "film")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                            } else {
                                Image(systemName: "film")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                        .frame(width: cardWidth, height: cardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(4)
                .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
                .offset(x: cardOffset)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.85)))
                .animation(.spring(response: 0.15, dampingFraction: 0.85), value: progress)
            }

            // Капсула слайдера
            HStack(spacing: 12) {
                Text(formatTime(displayTime))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
                    .blendMode(.plusLighter)

                // Нативный слайдер
                SystemUISliderView(
                    value: Binding(
                        get: { progress },
                        set: { dragProgress = $0 }
                    ),
                    isDragging: $isDragging,
                    onSeek: { val in
                        vm.seek(to: val * vm.currentDuration)
                    }
                )
                .frame(height: 24)
                .colorMultiply(.white.opacity(0.65))
                .blendMode(.plusLighter)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { sliderWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in sliderWidth = w }
                    }
                )

                Text("-" + formatTime(max(0, vm.currentDuration - displayTime)))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
                    .blendMode(.plusLighter)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            // Liquid Glass — нативный iOS 26, без fallback
            .glassEffect(.regular, in: .capsule)
        }
        .onChange(of: displayTime) { _, newTime in
            if isDragging || isHStackScrubbing || vm.screenScrubTime != nil {
                vm.generateScrubThumbnail(at: newTime)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Прогресс воспроизведения")
        .accessibilityValue("\(formatTime(displayTime)) из \(formatTime(vm.currentDuration))")
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width) && !isHStackScrubbing {
                        return
                    }
                    guard vm.currentDuration > 0 else { return }
                    if !isHStackScrubbing {
                        isHStackScrubbing = true
                        screenScrubInitialTime = vm.currentTime
                        scrubStartLocationX = value.startLocation.x
                        isInteracting = true
                    }
                    
                    let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
                    let trackWidth = (screen?.bounds.width ?? 393) - 32 // Примерная ширина рабочей области
                    let startX = max(1, min(trackWidth - 1, scrubStartLocationX))
                    
                    let thumbX = (screenScrubInitialTime / vm.currentDuration) * Double(trackWidth)
                    let distanceToThumb = abs(Double(startX) - thumbX)
                    
                    // Чем дальше тап от ползунка, тем быстрее свайп (до 6 раз быстрее)
                    let speedFactor = 1.0 + (distanceToThumb / Double(trackWidth)) * 5.0
                    
                    let baseMultiplier = vm.currentDuration / Double(trackWidth)
                    let deltaSeconds = Double(value.translation.width) * baseMultiplier * speedFactor
                    
                    vm.screenScrubTime = max(0, min(vm.currentDuration, screenScrubInitialTime + deltaSeconds))
                }
                .onEnded { value in
                    guard isHStackScrubbing else { return }
                    isHStackScrubbing = false
                    isInteracting = false
                    if let target = vm.screenScrubTime {
                        vm.seek(to: target)
                        vm.screenScrubTime = nil
                    }
                }
        )
        .onChange(of: isDragging) { _, dragging in
            if dragging { isInteracting = true }
            else if !isHStackScrubbing { isInteracting = false }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, !seconds.isNaN else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

// MARK: - Native UISlider Wrapper

struct SystemUISliderView: UIViewRepresentable {
    @Binding var value: Double
    @Binding var isDragging: Bool
    let onSeek: (Double) -> Void

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        
        // Убираем кружок-ползунок, как в нативном плеере
        slider.setThumbImage(UIImage(), for: .normal)
        
        // В iOS 26 нативный слайдер имеет Liquid Glass эффект на ползунке
        slider.tintColor = .white
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = .white.withAlphaComponent(0.25)
        
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.editingDidBegin(_:)), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.editingDidEnd(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        
        return slider
    }

    func updateUIView(_ uiView: UISlider, context: Context) {
        if !context.coordinator.isEditing {
            uiView.value = Float(value)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, isDragging: $isDragging, onSeek: onSeek)
    }

    class Coordinator: NSObject {
        var value: Binding<Double>
        var isDragging: Binding<Bool>
        let onSeek: (Double) -> Void
        var isEditing = false

        init(value: Binding<Double>, isDragging: Binding<Bool>, onSeek: @escaping (Double) -> Void) {
            self.value = value
            self.isDragging = isDragging
            self.onSeek = onSeek
        }

        @objc func valueChanged(_ sender: UISlider) {
            value.wrappedValue = Double(sender.value)
        }

        @objc func editingDidBegin(_ sender: UISlider) {
            isEditing = true
            isDragging.wrappedValue = true
        }

        @objc func editingDidEnd(_ sender: UISlider) {
            isEditing = false
            isDragging.wrappedValue = false
            onSeek(Double(sender.value))
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
