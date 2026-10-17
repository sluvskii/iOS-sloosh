import SwiftUI
import UIKit

// MARK: - Clip Trim Session (Единый источник правды режима «Создать момент»)
//
// Взаимодействие построено по канонам нативных редакторов Apple (Photos / iMovie):
//  • По умолчанию открыто «окно сцены» ~2 минуты вокруг выделения (как в iMovie) —
//    на таком зуме ручки двигаются заметно; пинчем можно отдалиться до всего фильма.
//  • Плёнка кадров — честные кадры фильма, отсканированные из живого декодера плеера
//    (последовательные точные seek'и + AVPlayerItemVideoOutput; работает всегда, когда
//    работает само видео).
//  • Ручка выделения — обрезка; кадр за ручкой показывается в видео (грубый скраб в движении,
//    точный на отпускании). Зона захвата ручки шире её видимой ширины, активная ручка
//    подсвечивается белым. Воспроизведение на время обрезки ставится на паузу.
//  • Перетаскивание тела выделения — перенос момента без прыжков видео.
//  • Перетаскивание фона дорожки — панорама плёнки (не трогает выделение и видео).
//  • Лимиты (3 с – 10 мин и края фильма): минимальная длина — жёсткий упор (как в Photos),
//    остальные границы — упругая пиксельная «резина» с хаптикой и пружинным возвратом.
//  • Выделение фиксируется в PlayerViewModel один раз — при отпускании пальца.

@MainActor
final class ClipTrimSession: ObservableObject {

    // MARK: - Published State

    @Published private(set) var selectionStart: Double
    @Published private(set) var selectionEnd: Double
    @Published private(set) var viewStart: Double
    @Published private(set) var viewSpan: Double
    @Published private(set) var frames: [Double: UIImage] = [:]
    @Published private(set) var duration: Double
    @Published private(set) var isPinching = false
    /// Какая ручка перетаскивается — для подсветки и укрупнения зоны отклика.
    @Published private(set) var activeHandle: ActiveHandle = .none

    enum ActiveHandle {
        case none
        case start
        case end
    }

    let minSelection = PlayerViewModel.clipMinDuration
    let maxSelection = PlayerViewModel.clipMaxDuration

    // MARK: - Dependencies

    private unowned let vm: PlayerViewModel
    private var reloadTask: Task<Void, Never>?
    private var trackWidth: CGFloat = 0
    /// Активный проход сканирования кадров и его поколение:
    /// новый жест/панорама отменяет предыдущий проход (отклик не применяется).
    private var captureTask: Task<Void, Never>?
    private var captureGeneration = 0

    // MARK: - Gesture State (арбитраж: побеждает жест, начавшийся первым)

    enum DragTarget {
        case none
        case trimStart
        case trimEnd
        case moveSelection
        case panTrack
    }

    private(set) var dragTarget: DragTarget = .none
    private var dragOriginStart: Double = 0
    private var dragOriginEnd: Double = 0
    private var dragOriginTouchX: CGFloat = 0
    private var dragOriginViewStart: Double = 0
    private var pinchOriginSpan: Double = 0
    private var tickedLimits: Set<String> = []
    private var lastPreviewSeek: CFAbsoluteTime = 0

    private static let maxCachedFrames = 220
    /// Ширина слота кадра в точках (16:9 при высоте дорожки 64).
    private static let slotPixelWidth: Double = 64.0 * 16.0 / 9.0
    /// Ход «резины» на границах в экранных точках (нативный, пиксельный скролл-фидбек).
    private static let rubberBandPoints: CGFloat = 44.0
    /// Зона захвата ручки: шире видимой ширины, чтобы «попадать» пальцем без прицеливания.
    private static let handleHitPoints: CGFloat = 38.0

    // MARK: - Init

    init(vm: PlayerViewModel) {
        self.vm = vm
        let minSel = PlayerViewModel.clipMinDuration
        let rawDuration = vm.currentDuration
        let resolvedDuration = (rawDuration.isFinite && !rawDuration.isNaN && rawDuration > 1.0)
            ? rawDuration
            : max(vm.clipEndTime + 60.0, 300.0)
        let rawStart = max(0.0, vm.clipStartTime)
        let rawEnd = max(rawStart + minSel, min(resolvedDuration, vm.clipEndTime))
        self.duration = resolvedDuration
        self.selectionStart = rawStart
        self.selectionEnd = min(resolvedDuration, rawEnd)
        // Нативный старт (как в iMovie): окно сцены ~2 минуты вокруг выделения,
        // чтобы ручки двигались заметно. Пинчем отдаляется до всего фильма.
        let initialSpan = min(120.0, resolvedDuration)
        self.viewSpan = initialSpan
        let selectionCenter = (rawStart + rawEnd) / 2.0
        let maxWindowStart = max(0.0, resolvedDuration - initialSpan)
        self.viewStart = max(0.0, min(maxWindowStart, selectionCenter - initialSpan / 2.0))
    }

    // MARK: - Lifecycle

    func activate() {
        scheduleFilmstripReload()
        // Захватываем начальный кадр выделения без лишних перемоток
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard let self, !self.vm.isPlaying else { return }
            if let frame = self.vm.captureCurrentFrame() {
                let key = self.bucketKey(for: self.selectionStart)
                if self.frames[key] == nil {
                    self.frames[key] = frame
                }
            }
        }
    }

    // MARK: - Presets & Quick Zoom

    var isZoomedOut: Bool {
        viewSpan >= duration - 1.0
    }

    func toggleZoomFit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            if isZoomedOut {
                let selSpan = selectionEnd - selectionStart
                let targetSpan = min(duration, max(90.0, selSpan * 2.0))
                let center = (selectionStart + selectionEnd) / 2.0
                viewSpan = targetSpan
                let maxStart = max(0.0, duration - targetSpan)
                viewStart = max(0.0, min(maxStart, center - targetSpan / 2.0))
            } else {
                viewStart = 0
                viewSpan = duration
            }
        }
        scheduleFilmstripReload()
    }

    func applyPreset(seconds: Double) {
        let center = (selectionStart + selectionEnd) / 2.0
        let newLen = min(duration, max(minSelection, seconds))
        var newStart = max(0.0, center - newLen / 2.0)
        var newEnd = newStart + newLen
        if newEnd > duration {
            newEnd = duration
            newStart = max(0.0, duration - newLen)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selectionStart = newStart
            selectionEnd = newEnd
            let span = max(viewSpan, newLen * 1.35)
            viewSpan = min(duration, span)
            let maxStart = max(0.0, duration - viewSpan)
            viewStart = max(0.0, min(maxStart, center - viewSpan / 2.0))
        }
        commitSelection()
        vm.seekClip(to: newStart)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        scheduleFilmstripReload()

        // Захватываем кадр нового начала
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard let self, !self.vm.isPlaying else { return }
            if let frame = self.vm.captureCurrentFrame() {
                let key = self.bucketKey(for: self.selectionStart)
                self.frames[key] = frame
            }
        }
    }

    func samplePlayingFrame(at time: Double) {
        let key = bucketKey(for: time)
        guard frames[key] == nil else { return }
        if let frame = vm.captureCurrentFrame() {
            frames[key] = frame
        }
    }

    func deactivate() {
        reloadTask?.cancel()
        reloadTask = nil
        cancelCapture()
        // Превью могло играть — останавливаем вместе с режимом обрезки.
        vm.pauseClipPreview()
    }

    /// Отмена активного прохода сканирования кадров.
    func cancelCapture() {
        captureGeneration += 1
        captureTask?.cancel()
        captureTask = nil
    }

    /// Если реальная длительность фильма уточнилась позже — мягко расширяем модель.
    func externalDurationChanged(to newDuration: Double) {
        guard newDuration.isFinite && !newDuration.isNaN && newDuration > duration else { return }
        duration = newDuration
        selectionEnd = min(duration, max(selectionStart + minSelection, selectionEnd))
        viewSpan = min(duration, viewSpan)
        viewStart = min(viewStart, max(0.0, duration - viewSpan))
        scheduleFilmstripReload()
    }

    // MARK: - Coordinate Mapping

    func screenX(for time: Double, width: CGFloat) -> CGFloat {
        guard viewSpan > 0, width > 0 else { return 0 }
        return CGFloat((time - viewStart) / viewSpan) * width
    }

    func time(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return viewStart }
        return viewStart + (Double(x / width) * viewSpan)
    }

    func bucketKey(for time: Double) -> Double {
        (time / 0.5).rounded() * 0.5
    }

    // MARK: - Drag Gesture

    func dragBegan(atX x: CGFloat, width: CGFloat) {
        guard !isPinching else { return }
        let startX = screenX(for: selectionStart, width: width)
        let endX = screenX(for: selectionEnd, width: width)

        dragOriginTouchX = x
        dragOriginStart = selectionStart
        dragOriginEnd = selectionEnd
        dragOriginViewStart = viewStart
        tickedLimits.removeAll()

        let hit = Self.handleHitPoints
        if abs(x - startX) <= hit {
            dragTarget = .trimStart
            activeHandle = .start
        } else if abs(x - endX) <= hit {
            dragTarget = .trimEnd
            activeHandle = .end
        } else if x >= startX && x <= endX {
            dragTarget = .moveSelection
        } else {
            dragTarget = .panTrack
        }

        // Нативно: любое взаимодействие с дорожкой ставит видео (и превью) на паузу.
        cancelCapture()
        vm.pauseForTrim()
        vm.pauseClipPreview()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func dragChanged(toX x: CGFloat, width: CGFloat) {
        guard !isPinching, dragTarget != .none, width > 0 else { return }
        let deltaSec = time(atX: x, width: width) - time(atX: dragOriginTouchX, width: width)
        // «Резина» задаётся в точках экрана и пересчитывается в секунды по текущему зуму —
        // ход упора ощущается одинаково на любом масштабе (как системный скролл).
        let overshoot = Double(Self.rubberBandPoints / width) * viewSpan

        switch dragTarget {
        case .trimStart:
            // Вниз: резина на краях фильма и лимите длительности. Вверх: жёсткий упор в
            // (end − мин.длина) — рамка никогда не выворачивается (как в Photos).
            let raw = dragOriginStart + deltaSec
            let lengthLimit = max(0.0, dragOriginEnd - maxSelection)
            var value = rubberBandMin(raw, minimum: lengthLimit, maxOvershoot: overshoot)
            value = rubberBandMin(value, minimum: 0.0, maxOvershoot: overshoot)
            value = min(value, dragOriginEnd - minSelection)
            tickLimit("start-max", when: raw < lengthLimit)
            tickLimit("start-edge", when: raw < 0.0)
            tickLimit("start-minlen", when: raw > dragOriginEnd - minSelection)
            selectionStart = value
            ensureVisible(selectionStart, width: width)
            previewSeek(to: max(0.0, value))

        case .trimEnd:
            // Вверх: резина на краях фильма и лимите длительности. Вниз: жёсткий упор в
            // (start + мин.длина).
            let raw = dragOriginEnd + deltaSec
            let lengthLimit = min(duration, dragOriginStart + maxSelection)
            var value = rubberBandMax(raw, maximum: lengthLimit, maxOvershoot: overshoot)
            value = rubberBandMax(value, maximum: duration, maxOvershoot: overshoot)
            value = max(value, dragOriginStart + minSelection)
            tickLimit("end-max", when: raw > lengthLimit)
            tickLimit("end-edge", when: raw > duration)
            tickLimit("end-minlen", when: raw < dragOriginStart + minSelection)
            selectionEnd = value
            ensureVisible(selectionEnd, width: width)
            previewSeek(to: max(selectionStart, value - 0.3))

        case .moveSelection:
            let length = dragOriginEnd - dragOriginStart
            let value = rubberBand(
                dragOriginStart + deltaSec,
                lower: 0,
                upper: duration - length,
                maxOvershoot: overshoot
            )
            selectionStart = value
            selectionEnd = value + length
            ensureVisible(selectionStart, width: width)
            ensureVisible(selectionEnd, width: width)

        case .panTrack:
            let maxStart = max(0.0, duration - viewSpan)
            let value = rubberBand(
                dragOriginViewStart - deltaSec,
                lower: 0,
                upper: maxStart,
                maxOvershoot: overshoot
            )
            viewStart = value

        case .none:
            break
        }
    }

    func dragEnded(width: CGFloat) {
        let target = dragTarget
        guard target != .none else { return }
        dragTarget = .none
        activeHandle = .none
        tickedLimits.removeAll()

        // Пружинный возврат резины в жёсткие границы (нативное «дожатие»).
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            settleToHardBounds()
        }

        switch target {
        case .trimStart, .moveSelection:
            commitSelection()
            // Показываем кадр начала момента (для длинных выделений — не дальше конца фильма)
            vm.seekClip(to: min(selectionStart, max(0.0, duration - 0.5)))
        case .trimEnd:
            commitSelection()
            // Показываем кадр конца момента
            vm.seekClip(to: max(0.0, min(duration - 0.5, selectionEnd - 0.25)))
        case .panTrack, .none:
            break
        }

        UISelectionFeedbackGenerator().selectionChanged()
        scheduleFilmstripReload()

        // Захватываем точный кадр, на который встала ручка, без повторных перемоток плеера
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard let self, !self.vm.isPlaying else { return }
            if let frame = self.vm.captureCurrentFrame() {
                let key = self.bucketKey(for: self.vm.currentTime)
                self.frames[key] = frame
            }
        }
    }

    /// Отмена одиночного драга при старте пинча (арбитраж жестов).
    private func cancelDrag() {
        dragTarget = .none
        activeHandle = .none
        tickedLimits.removeAll()
        settleToHardBounds()
    }

    private func settleToHardBounds() {
        let length = min(maxSelection, max(minSelection, selectionEnd - selectionStart))
        selectionStart = max(0.0, min(selectionStart, duration - length))
        selectionEnd = selectionStart + length
        viewSpan = min(viewSpan, duration)
        let maxStart = max(0.0, duration - viewSpan)
        viewStart = max(0.0, min(viewStart, maxStart))
    }

    private func commitSelection() {
        vm.commitClipSelection(start: selectionStart, end: selectionEnd)
    }

    // MARK: - Pinch Gesture (непрерывный масштаб с якорем)

    func requestPinchStart() {
        if isPinching { return }
        if dragTarget != .none {
            cancelDrag()
        }
        cancelCapture()
        isPinching = true
        pinchOriginSpan = viewSpan
    }

    func pinchChanged(magnification: Double, anchorX: CGFloat, width: CGFloat) {
        guard isPinching, width > 0, magnification > 0 else { return }
        let anchorTime = time(atX: anchorX, width: width)
        let anchorFraction = Double(max(0, min(1, anchorX / width)))

        let minSpan = min(max(20.0, (selectionEnd - selectionStart) + 6.0), duration)
        let newSpan = min(duration, max(minSpan, pinchOriginSpan / magnification))

        viewSpan = newSpan
        viewStart = max(0.0, min(duration - newSpan, anchorTime - (anchorFraction * newSpan)))
    }

    func pinchEnded() {
        guard isPinching else { return }
        isPinching = false
        settleToHardBounds()
        UISelectionFeedbackGenerator().selectionChanged()
        scheduleFilmstripReload()
    }

    // MARK: - Rubber Band & Limits

    /// Резина только снизу (значение «тянет» ниже минимума и упруго возвращается).
    private func rubberBandMin(_ value: Double, minimum: Double, maxOvershoot: Double) -> Double {
        guard value < minimum else { return value }
        let excess = minimum - value
        return minimum - (1.0 - 1.0 / (excess * 0.45 + 1.0)) * maxOvershoot
    }

    /// Резина только сверху (значение «тянет» выше максимума и упруго возвращается).
    private func rubberBandMax(_ value: Double, maximum: Double, maxOvershoot: Double) -> Double {
        guard value > maximum else { return value }
        let excess = value - maximum
        return maximum + (1.0 - 1.0 / (excess * 0.45 + 1.0)) * maxOvershoot
    }

    /// Двусторонняя резина (панорама и перенос выделения).
    private func rubberBand(_ value: Double, lower: Double, upper: Double, maxOvershoot: Double) -> Double {
        if value < lower {
            return rubberBandMin(value, minimum: lower, maxOvershoot: maxOvershoot)
        }
        if value > upper {
            return rubberBandMax(value, maximum: upper, maxOvershoot: maxOvershoot)
        }
        return value
    }

    private func tickLimit(_ id: String, when condition: Bool) {
        guard condition, !tickedLimits.contains(id) else { return }
        tickedLimits.insert(id)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// Автопанорама: держим двигающийся край выделения в зоне видимости (как в iMovie).
    private func ensureVisible(_ time: Double, width: CGFloat) {
        guard viewSpan < duration else { return }
        let edgeFraction = 0.05
        let lowerBound = viewStart + viewSpan * edgeFraction
        let upperBound = viewStart + viewSpan * (1.0 - edgeFraction)
        if time < lowerBound {
            viewStart = max(0.0, time - viewSpan * edgeFraction)
        } else if time > upperBound {
            viewStart = min(duration - viewSpan, time + viewSpan * edgeFraction - viewSpan)
        }
    }

    // MARK: - Scrub Preview (кадр следует за ручкой)

    private func previewSeek(to seconds: Double) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastPreviewSeek >= 0.05 else { return }
        lastPreviewSeek = now
        vm.seekClipFast(to: max(0.0, seconds))
    }

    // MARK: - Filmstrip (сканирование кадров из живого декодера плеера)
    //
    // Принцип: плеер ставится на паузу и последовательно перематывается по слотам
    // видимого окна; после каждого точного seek'а кадр забирается из AVPlayerItemVideoOutput —
    // того же конвейера, что рендерит видео на экран. Поэтому кадр получается всегда,
    // когда воспроизведение вообще работает (AVAssetImageGenerator на проксированных
    // HLS-стримах давал ноль кадров — от него полностью отказались).
    // По завершении прохода плейхед возвращается на прежнее место.

    func trackLayoutChanged(width: CGFloat) {
        guard width > 0 else { return }
        let isFirstLayout = trackWidth == 0
        guard isFirstLayout || abs(width - trackWidth) > 0.5 else { return }
        trackWidth = width
        if isFirstLayout {
            scheduleFilmstripReload()
        }
    }

    func scheduleFilmstripReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            self?.reloadVisibleFilmstrip()
        }
    }

    private func reloadVisibleFilmstrip() {
        guard trackWidth > 0, viewSpan > 0 else { return }
        // Во время превью плеер не трогаем
        guard !vm.isPlaying else { return }

        let slotSpan = viewSpan * (Self.slotPixelWidth / Double(trackWidth))
        guard slotSpan > 0 else { return }

        let firstIndex = max(0, Int(floor(viewStart / slotSpan)))
        let lastIndex = min(Int(ceil(duration / slotSpan)) - 1, Int(ceil((viewStart + viewSpan) / slotSpan)))
        guard firstIndex <= lastIndex else { return }

        if frames.count > Self.maxCachedFrames {
            frames.removeAll()
        }

        var missing: [Double] = []
        for index in firstIndex...lastIndex {
            let slotTime = (Double(index) + 0.5) * slotSpan
            guard slotTime >= 0, slotTime <= duration else { continue }
            let key = bucketKey(for: slotTime)
            if frames[key] == nil {
                missing.append(key)
            }
        }
        guard !missing.isEmpty else { return }

        // Новый проход сканирования отменяет предыдущий
        cancelCapture()
        let generation = captureGeneration

        // 1. Асинхронное фоновое извлечение кадров через AVAssetImageGenerator (без перемоток плеера)
        vm.generateFilmstrip(times: missing) { [weak self] newFrames in
            guard let self, generation == self.captureGeneration, !newFrames.isEmpty else { return }
            for (time, img) in newFrames {
                let key = self.bucketKey(for: time)
                if self.frames[key] == nil {
                    self.frames[key] = img
                }
            }
        }

        // 2. Если декодер плеера прямо сейчас отображает кадр (плеер на паузе), сохраняем его
        if let currentFrame = vm.captureCurrentFrame() {
            let key = bucketKey(for: vm.currentTime)
            if frames[key] == nil {
                frames[key] = currentFrame
            }
        }
    }
}

// MARK: - Native Trimmer View (дорожка в стиле Photos / iMovie)

struct PlayerClipTrimmerView: View {
    @ObservedObject var vm: PlayerViewModel
    @StateObject private var session: ClipTrimSession
    @State private var isShowingPublishSheet: Bool = false
    @AppStorage("clipTrimmerPinchHintShown") private var pinchHintShown: Bool = false

    private let trackHeight: CGFloat = 64
    private let trimmerAccent = Color.slooshAccent

    init(vm: PlayerViewModel) {
        self.vm = vm
        _session = StateObject(wrappedValue: ClipTrimSession(vm: vm))
    }

    var body: some View {
        ZStack {
            // Кинематографичный скрим
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.82), location: 0.0),
                    .init(color: Color.black.opacity(0.25), location: 0.22),
                    .init(color: .clear, location: 0.42),
                    .init(color: .clear, location: 0.62),
                    .init(color: Color.black.opacity(0.40), location: 0.78),
                    .init(color: Color.black.opacity(0.94), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Центр: тап = превью выбранного момента (play/pause с зацикливанием)
            centerPreviewArea

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 14)
                    .padding(.horizontal, 24)

                Spacer()

                bottomStudio
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
        .onAppear { session.activate() }
        .onDisappear { session.deactivate() }
        .onChange(of: vm.currentDuration) { _, newDuration in
            session.externalDurationChanged(to: newDuration)
        }
        .onChange(of: vm.isPlaying) { _, playing in
            // После паузы превью добираем кадры, пропущенные во время проигрывания
            if !playing {
                session.scheduleFilmstripReload()
            }
        }
        .onChange(of: vm.currentTime) { _, newTime in
            if vm.isClipMode && vm.isPlaying {
                session.samplePlayingFrame(at: newTime)
            }
        }
        .sheet(isPresented: $isShowingPublishSheet) {
            PublishMomentSheet(
                vm: vm,
                coverImage: session.frames[session.bucketKey(for: session.selectionStart)] ?? vm.captureCurrentFrame(),
                startTime: session.selectionStart,
                endTime: session.selectionEnd
            )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.isPlaying)
    }

    // MARK: - Center Preview (нативный просмотр момента)

    private var centerPreviewArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if vm.isPlaying {
                    vm.pauseClipPreview()
                } else {
                    vm.playClipPreview()
                }
            }
            .overlay {
                if !vm.isPlaying {
                    Image(systemName: "play.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 66, height: 66)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .shadow(color: .black.opacity(0.4), radius: 10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
    }

    // MARK: - Top Bar (Отмена • Превью/Длительность • Готово)

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    vm.exitClipMode()
                }
            } label: {
                Text("Отмена")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()

            // Интерактивный бейдж превью и длительности момента
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if vm.isPlaying {
                    vm.pauseClipPreview()
                } else {
                    vm.playClipPreview()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(formattedDuration(session.selectionEnd - session.selectionStart))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isShowingPublishSheet = true
            } label: {
                HStack(spacing: 5) {
                    Text("Готово")
                        .font(.system(size: 15, weight: .bold))
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color.white)
                .clipShape(Capsule())
                .shadow(color: Color.white.opacity(0.25), radius: 6)
            }
            .buttonStyle(.glassPress)
        }
    }

    // MARK: - Bottom Studio (пресеты + дорожка + бейджи + границы окна)

    private var bottomStudio: some View {
        VStack(spacing: 10) {
            presetChipsRow
            filmstripTrack
                .frame(height: trackHeight)
            handleTimecodesRow
                .frame(height: 18)
            // Границы окна имеют смысл только в зуме (когда видно не всё полотно)
            if session.viewSpan < session.duration - 0.5 {
                viewportFooter
            }
        }
    }

    private var presetChipsRow: some View {
        HStack(spacing: 8) {
            presetChip(title: "15 с", seconds: 15)
            presetChip(title: "30 с", seconds: 30)
            presetChip(title: "1 мин", seconds: 60)
            presetChip(title: "2 мин", seconds: 120)

            Spacer()

            Button {
                session.toggleZoomFit()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: session.isZoomedOut ? "viewfinder" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text(session.isZoomedOut ? "К моменту" : "Всё видео")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }

    private func presetChip(title: String, seconds: Double) -> some View {
        let isSelected = abs((session.selectionEnd - session.selectionStart) - seconds) < 0.8
        return Button {
            session.applyPreset(seconds: seconds)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.9))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(isSelected ? Color.slooshAccent : Color.clear)
                .clipShape(Capsule())
                .glassEffect(isSelected ? .identity : .regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filmstrip Track

    private var filmstripTrack: some View {
        GeometryReader { proxy in
            let width = max(60.0, proxy.size.width)
            let slotWidth = trackHeight * 16.0 / 9.0

            ZStack(alignment: .leading) {
                // Честная база: тёмная плёнка; кадры фильма ложатся поверх по мере генерации
                trackBaseLayer

                // Плёнка: сетка привязана ко ВРЕМЕНИ, поэтому панорама и зум движутся непрерывно
                filmstripSlots(width: width, slotWidth: slotWidth)

                // Затемнение вне выделения
                dimmingOverlay(width: width)

                // Рамка выделения с ручками
                selectionFrame(width: width)
                    .offset(x: session.screenX(for: session.selectionStart, width: width))

                // Нативный плейхед (белая стрелка/игла воспроизведения)
                playheadIndicator(width: width)
            }
            .frame(width: width, height: trackHeight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(trimGestures(width: width))
            .onAppear { session.trackLayoutChanged(width: width) }
            .onChange(of: proxy.size.width) { _, newWidth in
                session.trackLayoutChanged(width: newWidth)
            }
        }
    }

    /// Тёмная основа плёнки с мягким затемнённым постером/бэкдропом фильма.
    private var trackBaseLayer: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.85))
            if let artworkUrl = vm.backdropUrl ?? vm.posterUrl {
                AsyncCachedImage(urlString: artworkUrl) {
                    Color.clear
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.28)
                }
            }
            // Мягкая индикация генерации кадров — только пока не готово ни одного кадра
            if session.frames.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .shimmer()
            }
        }
    }

    /// Слоты плёнки, привязанные ко временной сетке (сдвигаются вместе с таймлайном).
    private func filmstripSlots(width: CGFloat, slotWidth: CGFloat) -> some View {
        let slotSpan = session.viewSpan * Double(slotWidth / width)
        let firstIndex = slotSpan > 0 ? max(0, Int(floor(session.viewStart / slotSpan))) : 0
        let lastIndex = slotSpan > 0
            ? min(Int(ceil(session.duration / slotSpan)), Int(ceil((session.viewStart + session.viewSpan) / slotSpan)))
            : firstIndex

        return ZStack(alignment: .leading) {
            ForEach(firstIndex...max(firstIndex, lastIndex), id: \.self) { index in
                let slotTime = (Double(index) + 0.5) * slotSpan
                slotView(bucket: session.bucketKey(for: slotTime), slotWidth: slotWidth)
                    .offset(x: session.screenX(for: Double(index) * slotSpan, width: width))
            }
        }
        .frame(width: width, height: trackHeight, alignment: .leading)
        .clipped()
    }

    @ViewBuilder
    private func slotView(bucket: Double, slotWidth: CGFloat) -> some View {
        if let image = session.frames[bucket] {
            ZStack(alignment: .trailing) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)

                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: 1)
            }
            .frame(width: slotWidth, height: trackHeight)
            .clipped()
        }
    }

    @ViewBuilder
    private func playheadIndicator(width: CGFloat) -> some View {
        let current = vm.currentTime
        if current >= session.selectionStart - 0.2 && current <= session.selectionEnd + 0.2 {
            let x = session.screenX(for: current, width: width)
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: trackHeight)
                    .shadow(color: Color.black.opacity(0.6), radius: 3)

                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
                    .shadow(color: Color.black.opacity(0.5), radius: 2)
                    .offset(y: -2)
            }
            .offset(x: x - 1.5)
            .allowsHitTesting(false)
            .animation(.linear(duration: 0.1), value: current)
        }
    }

    private func dimmingOverlay(width: CGFloat) -> some View {
        let startX = session.screenX(for: session.selectionStart, width: width)
        let endX = session.screenX(for: session.selectionEnd, width: width)
        return HStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.70))
                .frame(width: max(0, startX))
            Rectangle()
                .fill(Color.clear)
                .frame(width: max(0, endX - startX))
            Rectangle()
                .fill(Color.black.opacity(0.70))
                .frame(width: max(0, width - endX))
        }
        .allowsHitTesting(false)
    }

    private func selectionFrame(width: CGFloat) -> some View {
        let startX = session.screenX(for: session.selectionStart, width: width)
        let endX = session.screenX(for: session.selectionEnd, width: width)
        let frameWidth = max(24, endX - startX)
        // Активная (перетаскиваемая) рамка подсвечивается белым — понятный отклик на захват
        let isActive = session.activeHandle != .none

        return HStack(spacing: 0) {
            handleGrip(isLeft: true, isActive: isActive)

            VStack {
                Rectangle()
                    .fill(isActive ? Color.white : trimmerAccent)
                    .frame(height: isActive ? 4 : 3)
                Spacer()
                Rectangle()
                    .fill(isActive ? Color.white : trimmerAccent)
                    .frame(height: isActive ? 4 : 3)
            }
            .frame(maxWidth: .infinity)

            handleGrip(isLeft: false, isActive: isActive)
        }
        .frame(width: frameWidth, height: trackHeight)
        .allowsHitTesting(false)
    }

    private func handleGrip(isLeft: Bool, isActive: Bool) -> some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: isLeft ? 8 : 0,
                bottomLeadingRadius: isLeft ? 8 : 0,
                bottomTrailingRadius: isLeft ? 0 : 8,
                topTrailingRadius: isLeft ? 0 : 8
            )
            .fill(isActive ? Color.white : trimmerAccent)
            .frame(width: 14)

            HStack(spacing: 2) {
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 2, height: 16)
                Capsule()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 2, height: 16)
            }
        }
        .frame(width: 14)
    }

    // MARK: - Gestures (драг + пинч с арбитражем)

    private func trimGestures(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if session.dragTarget == .none, !session.isPinching {
                    session.dragBegan(atX: value.startLocation.x, width: width)
                }
                session.dragChanged(toX: value.location.x, width: width)
            }
            .onEnded { _ in
                session.dragEnded(width: width)
            }
            .simultaneously(with:
                MagnifyGesture()
                    .onChanged { value in
                        session.requestPinchStart()
                        let anchorX = value.startAnchor.x * width
                        session.pinchChanged(
                            magnification: Double(value.magnification),
                            anchorX: anchorX,
                            width: width
                        )
                    }
                    .onEnded { _ in
                        session.pinchEnded()
                    }
            )
    }

    // MARK: - Timecode Badges (следуют за ручками, не наезжают друг на друга)

    private var handleTimecodesRow: some View {
        GeometryReader { proxy in
            let width = max(60.0, proxy.size.width)
            let startX = session.screenX(for: session.selectionStart, width: width)
            let endX = session.screenX(for: session.selectionEnd, width: width)
            let badgeWidth: CGFloat = 58
            let sPos = max(0, min(width - badgeWidth, startX - badgeWidth / 2))
            let ePos = max(0, min(width - badgeWidth, endX - badgeWidth / 2))

            ZStack(alignment: .leading) {
                if ePos - sPos < badgeWidth + 4 {
                    // Узкое выделение: один общий бейдж «начало – конец» вместо наезжающих
                    combinedBadge(
                        formatTimecode(session.selectionStart),
                        formatTimecode(session.selectionEnd)
                    )
                    .offset(x: max(0, min(width - 104, (startX + endX) / 2 - 52)))
                } else {
                    timecodeBadge(formatTimecode(session.selectionStart))
                        .offset(x: sPos)

                    timecodeBadge(formatTimecode(session.selectionEnd))
                        .offset(x: ePos)
                }
            }
        }
    }

    private func timecodeBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(trimmerAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
    }

    private func combinedBadge(_ start: String, _ end: String) -> some View {
        Text("\(start) – \(end)")
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(trimmerAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
    }

    // MARK: - Viewport Footer

    private var viewportFooter: some View {
        HStack {
            Text(formatTimecode(session.viewStart))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.35))

            Spacer()

            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.30))

            Spacer()

            Text(formatTimecode(min(session.viewStart + session.viewSpan, session.duration)))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Formatters

    private func formattedDuration(_ interval: Double) -> String {
        let total = Int(round(max(1.0, interval)))
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return String(format: "0:%02d", seconds)
    }

    private func formatTimecode(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Native Publish Sheet (Флагманская карточка публикации момента)

private struct PublishMomentSheet: View {
    @ObservedObject var vm: PlayerViewModel
    let coverImage: UIImage?
    let startTime: Double
    let endTime: Double
    @Environment(\.dismiss) private var dismiss

    @State private var caption: String = ""
    @State private var isPublishing: Bool = false
    @State private var errorMessage: String? = nil
    @FocusState private var isCaptionFocused: Bool

    private var duration: Double {
        max(1.0, endTime - startTime)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Превью момента с бейджами и длительностью
                    mediaPreviewCard

                    // 2. Ввод подписи к моменту
                    captionCard

                    // 3. Бейдж автора
                    authorCard

                    if let errorMessage {
                        errorCard(errorMessage)
                    }

                    // 4. Кнопка публикации
                    publishButton
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Новый момент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .disabled(isPublishing)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            caption = vm.clipCaption
        }
    }

    // MARK: - Media Preview Card

    private var mediaPreviewCard: some View {
        HStack(spacing: 14) {
            // Кадр момента с плашкой длительности
            ZStack(alignment: .bottomTrailing) {
                if let coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if let artworkUrl = vm.backdropUrl ?? vm.posterUrl {
                    AsyncCachedImage(urlString: artworkUrl) {
                        Rectangle().fill(Color.white.opacity(0.08))
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                }

                Text(formattedDuration(duration))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(6)
            }
            .frame(width: 120, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )

            // Данные фильма / серии
            VStack(alignment: .leading, spacing: 4) {
                Text(!vm.fallbackTitle.isEmpty ? vm.fallbackTitle : (vm.isMovie ? "Фильм" : "Сериал"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if !vm.isMovie, let s = vm.currentSeason, let e = vm.currentEpisode {
                        Text("\(s) сезон, \(e) серия")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    if let voice = vm.currentTranslationName, !voice.isEmpty {
                        Text(voice)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.slooshAccent)
                            .lineLimit(1)
                    }
                }

                Text(timecodeRangeFormatted)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Caption Card

    private var captionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Подпись к моменту", systemImage: "quote.bubble.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Text("\(caption.count)/200")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(caption.count > 200 ? Color.red : .white.opacity(0.4))
            }

            TextField("Добавьте яркую подпись к моменту...", text: $caption, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(3...5)
                .focused($isCaptionFocused)
                .onChange(of: caption) { _, newVal in
                    if newVal.count > 200 {
                        caption = String(newVal.prefix(200))
                    }
                    vm.clipCaption = caption
                }

            Text("Момент увидят зрители в общей ленте и в вашем профиле.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: - Author Card

    private var authorCard: some View {
        HStack(spacing: 12) {
            let user = AuthRepository.shared.currentUser
            let authorName = (user?.displayName?.isEmpty == false ? user?.displayName : nil) ?? user?.displayTitle ?? "Зритель"

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 36, height: 36)

                if let photoUrl = user?.photoURL, let url = URL(string: photoUrl) {
                    AsyncCachedImage(url: url) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.6))
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(authorName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Автор момента")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.slooshAccent.opacity(0.85))
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Publish Button

    private var publishButton: some View {
        Button {
            publish()
        } label: {
            HStack(spacing: 8) {
                if isPublishing {
                    ProgressView()
                        .tint(.black)
                    Text("Публикуем момент...")
                        .font(.system(size: 16, weight: .bold))
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                    Text("Опубликовать момент")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Color.slooshAccent)
            .clipShape(Capsule())
            .shadow(color: Color.slooshAccent.opacity(0.35), radius: 10, y: 3)
        }
        .buttonStyle(.glassPress)
        .disabled(isPublishing)
    }

    private func publish() {
        guard !isPublishing else { return }
        isPublishing = true
        errorMessage = nil
        vm.clipCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                try await vm.publishClip()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
                ToastManager.shared.show(
                    title: "Момент опубликован! ✨",
                    icon: "sparkles.tv.fill",
                    iconColor: Color.slooshAccent
                )
            } catch {
                isPublishing = false
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = "Не удалось опубликовать момент. Проверьте интернет."
            }
        }
    }

    private var timecodeRangeFormatted: String {
        func fmt(_ sec: Double) -> String {
            let total = Int(max(0, sec))
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            if h > 0 {
                return String(format: "%d:%02d:%02d", h, m, s)
            }
            return String(format: "%02d:%02d", m, s)
        }
        return "\(fmt(startTime)) – \(fmt(endTime))"
    }

    private func formattedDuration(_ interval: Double) -> String {
        let total = Int(round(max(1.0, interval)))
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return String(format: "0:%02d", seconds)
    }
}
