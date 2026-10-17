import SwiftUI
import UIKit
import AVFoundation

// MARK: - Clip Trim Session (Единый источник правды режима «Создать момент»)
//
// Взаимодействие построено по канонам нативных редакторов Apple (Photos / iMovie):
//  • Плёнка кадров — честные кадры фильма через AVAssetImageGenerator (как скраб-превью плеера).
//  • Пинч по дорожке — непрерывный масштаб с якорем под пальцами (без режимов «Сцена/Фильм»).
//  • Ручка выделения — обрезка; кадр за ручкой показывается в видео (грубый скраб в движении,
//    точный на отпускании). Воспроизведение на время обрезки становится на паузу.
//  • Перетаскивание тела выделения — перенос момента без прыжков видео.
//  • Перетаскивание фона дорожки — панорама плёнки (не трогает выделение и видео).
//  • Лимиты (3–60 с и края фильма) — упругая «резина» с пружинным возвратом, хаптика на границах.
//  • Выделение фиксируется в PlayerViewModel один раз — при отпускании пальца.

@MainActor
final class ClipTrimSession: ObservableObject {

    // MARK: - Published State

    @Published private(set) var selectionStart: Double
    @Published private(set) var selectionEnd: Double
    @Published private(set) var viewStart: Double
    @Published private(set) var viewSpan: Double
    @Published private(set) var frames: [Double: UIImage] = [:]
    @Published private(set) var playheadTime: Double = 0
    @Published private(set) var duration: Double
    @Published private(set) var isPinching = false

    let minSelection = PlayerViewModel.clipMinDuration
    let maxSelection = PlayerViewModel.clipMaxDuration

    // MARK: - Dependencies

    private unowned let vm: PlayerViewModel
    private var generator: AVAssetImageGenerator?
    private var filmstripTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var playheadTimer: Timer?
    private var trackWidth: CGFloat = 0

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
    private var lastReloadSchedule: CFAbsoluteTime = 0

    private static let frameBucket: Double = 0.5
    private static let maxCachedFrames = 700

    // MARK: - Init

    init(vm: PlayerViewModel) {
        self.vm = vm
        let minSel = PlayerViewModel.clipMinDuration
        let rawDuration = vm.currentDuration
        let safeDuration = (rawDuration.isFinite && !rawDuration.isNaN && rawDuration > 1.0) ? rawDuration : 0
        self.duration = safeDuration > 0 ? safeDuration : max(vm.clipEndTime + 60.0, 300.0)
        let rawStart = max(0.0, vm.clipStartTime)
        let rawEnd = max(rawStart + minSel, min(duration, vm.clipEndTime))
        self.selectionStart = rawStart
        self.selectionEnd = min(duration, rawEnd)
        // Нативное поведение по умолчанию: дорожка показывает весь фильм (как Photos),
        // кадры уточняются при пинче.
        self.viewSpan = duration
        self.viewStart = 0
        self.playheadTime = min(max(vm.currentTime, 0), duration)
    }

    // MARK: - Lifecycle

    func activate() {
        syncPlayhead()
        startPlayheadTimer()
        scheduleFilmstripReload()
    }

    func deactivate() {
        playheadTimer?.invalidate()
        playheadTimer = nil
        filmstripTask?.cancel()
        filmstripTask = nil
        reloadTask?.cancel()
        reloadTask = nil
        generator?.cancelAllCGImageGeneration()
        generator = nil
    }

    private func startPlayheadTimer() {
        playheadTimer?.invalidate()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncPlayhead()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playheadTimer = timer
    }

    private func syncPlayhead() {
        let t = vm.currentTime
        if t.isFinite && !t.isNaN && t >= 0 {
            playheadTime = min(t, duration)
        }
        // Длительность могла уточниться после входа в триммер — мягко расширяем модель.
        let d = vm.currentDuration
        if d.isFinite && !d.isNaN && d > duration {
            externalDurationChanged(to: d)
        }
    }

    /// Если реальная длительность фильма уточнилась позже — мягко расширяем модель.
    func externalDurationChanged(to newDuration: Double) {
        guard newDuration.isFinite && !newDuration.isNaN && newDuration > duration else { return }
        duration = newDuration
        selectionEnd = min(duration, max(selectionStart + minSelection, selectionEnd))
        viewSpan = min(duration, viewSpan)
        viewStart = min(viewStart, duration - viewSpan)
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
        (time / Self.frameBucket).rounded() * Self.frameBucket
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

        if abs(x - startX) <= 30 {
            dragTarget = .trimStart
        } else if abs(x - endX) <= 30 {
            dragTarget = .trimEnd
        } else if x >= startX && x <= endX {
            dragTarget = .moveSelection
        } else {
            dragTarget = .panTrack
        }

        // Нативно: любое взаимодействие с дорожкой ставит видео на паузу.
        vm.pauseForTrim()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func dragChanged(toX x: CGFloat, width: CGFloat) {
        guard !isPinching, dragTarget != .none else { return }
        let deltaSec = time(atX: x, width: width) - time(atX: dragOriginTouchX, width: width)

        switch dragTarget {
        case .trimStart:
            // Вниз: резина на краях фильма и лимите 60 с. Вверх: жёсткий упор в
            // (end − мин.длина) — рамка никогда не выворачивается (как в Photos).
            let raw = dragOriginStart + deltaSec
            let lengthLimit = max(0.0, dragOriginEnd - maxSelection)
            var value = rubberBandMin(raw, minimum: lengthLimit, maxOvershoot: 3.0)
            value = rubberBandMin(value, minimum: 0.0, maxOvershoot: 3.0)
            value = min(value, dragOriginEnd - minSelection)
            tickLimit("start-60s", when: raw < lengthLimit)
            tickLimit("start-edge", when: raw < 0.0)
            tickLimit("start-minlen", when: raw > dragOriginEnd - minSelection)
            selectionStart = value
            ensureVisible(selectionStart, width: width)
            previewSeek(to: max(0.0, value))

        case .trimEnd:
            // Вверх: резина на краях фильма и лимите 60 с. Вниз: жёсткий упор в
            // (start + мин.длина).
            let raw = dragOriginEnd + deltaSec
            let lengthLimit = min(duration, dragOriginStart + maxSelection)
            var value = rubberBandMax(raw, maximum: lengthLimit, maxOvershoot: 3.0)
            value = rubberBandMax(value, maximum: duration, maxOvershoot: 3.0)
            value = max(value, dragOriginStart + minSelection)
            tickLimit("end-60s", when: raw > lengthLimit)
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
                maxOvershoot: 3.0
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
                maxOvershoot: viewSpan * 0.12
            )
            viewStart = value

        case .none:
            break
        }

        scheduleFilmstripReload()
    }

    func dragEnded(width: CGFloat) {
        let target = dragTarget
        guard target != .none else { return }
        dragTarget = .none
        tickedLimits.removeAll()

        // Пружинный возврат резины в жёсткие границы (нативное «дожатие»).
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            settleToHardBounds()
        }

        switch target {
        case .trimStart, .moveSelection:
            commitSelection()
            vm.seekClip(to: selectionStart)
        case .trimEnd:
            commitSelection()
            vm.seekClip(to: max(selectionStart, selectionEnd - 0.1))
        case .panTrack, .none:
            break
        }

        UISelectionFeedbackGenerator().selectionChanged()
        scheduleFilmstripReload()
    }

    /// Отмена одиночного драга при старте пинча (арбитраж жестов).
    private func cancelDrag() {
        dragTarget = .none
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
        isPinching = true
        pinchOriginSpan = viewSpan
    }

    func pinchChanged(magnification: Double, anchorX: CGFloat, width: CGFloat) {
        guard isPinching, width > 0, magnification > 0 else { return }
        let anchorTime = time(atX: anchorX, width: width)
        let anchorFraction = Double(max(0, min(1, anchorX / width)))

        let minSpan = min(max(12.0, (selectionEnd - selectionStart) + 6.0), duration)
        let newSpan = min(duration, max(minSpan, pinchOriginSpan / magnification))

        viewSpan = newSpan
        viewStart = max(0.0, min(duration - newSpan, anchorTime - (anchorFraction * newSpan)))

        throttledFilmstripReload()
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

    // MARK: - Filmstrip (AVAssetImageGenerator)

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
        guard let asset = vm.trimmerAsset else { return }
        reloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 130_000_000)
            guard !Task.isCancelled else { return }
            self?.reloadVisibleFilmstrip(asset: asset)
        }
    }

    private func throttledFilmstripReload() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastReloadSchedule >= 0.1 else { return }
        lastReloadSchedule = now
        scheduleFilmstripReload()
    }

    private func reloadVisibleFilmstrip(asset: AVAsset) {
        guard trackWidth > 0, viewSpan > 0 else { return }

        let slotWidth: CGFloat = 64.0 * 16.0 / 9.0
        let slotSpan = viewSpan * Double(slotWidth / trackWidth)
        guard slotSpan > 0 else { return }

        let firstIndex = max(0, Int(floor(viewStart / slotSpan)))
        let lastIndex = min(Int(ceil(duration / slotSpan)), Int(ceil((viewStart + viewSpan) / slotSpan)))
        guard firstIndex <= lastIndex else { return }

        if frames.count > Self.maxCachedFrames {
            frames.removeAll()
        }

        var requested: [CMTime] = []
        for index in firstIndex...lastIndex {
            let slotTime = (Double(index) + 0.5) * slotSpan
            guard slotTime >= 0, slotTime <= duration else { continue }
            let key = bucketKey(for: slotTime)
            if frames[key] == nil {
                requested.append(CMTime(seconds: key, preferredTimescale: 600))
            }
        }
        guard !requested.isEmpty else { return }

        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 320, height: 180)
        let tolerance = CMTime(
            seconds: min(max(slotSpan * 0.5, 0.5), 6.0),
            preferredTimescale: 600
        )
        gen.requestedTimeToleranceBefore = tolerance
        gen.requestedTimeToleranceAfter = tolerance

        generator?.cancelAllCGImageGeneration()
        generator = gen
        filmstripTask?.cancel()

        filmstripTask = Task { [weak self] in
            for await result in gen.images(for: requested) {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                if case .success(let success) = result {
                    let image = UIImage(cgImage: success.image)
                    let key = self.bucketKey(for: success.requestedTime.seconds)
                    if self.frames[key] == nil {
                        self.frames[key] = image
                    }
                }
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

            // Центр: тап = превью момента (play/pause с зацикливанием в выделении)
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
        .sheet(isPresented: $isShowingPublishSheet) {
            PublishMomentSheet(vm: vm)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.isPlaying)
    }

    // MARK: - Center Preview (нативный просмотр момента)

    private var centerPreviewArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                let start = session.selectionStart
                let end = session.selectionEnd
                // Если плейхед вне момента — начинаем превью с его начала (как в Photos)
                if vm.currentTime < start - 0.5 || vm.currentTime >= end - 0.05 {
                    vm.seekClip(to: start)
                }
                vm.togglePlayPause()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

    // MARK: - Top Bar (Отмена • Длительность • Готово)

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

            // Длительность момента — главный параметр редактора
            Text(formattedDuration(session.selectionEnd - session.selectionStart))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isShowingPublishSheet = true
            } label: {
                Text("Готово")
                    .font(.system(size: 15, weight: .bold))
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

    // MARK: - Bottom Studio (дорожка + бейджи + границы окна)

    private var bottomStudio: some View {
        VStack(spacing: 10) {
            if !pinchHintShown {
                pinchHint
            }
            filmstripTrack
                .frame(height: trackHeight)
            handleTimecodesRow
                .frame(height: 18)
            viewportFooter
        }
    }

    private var pinchHint: some View {
        Text("Сведите или разведите пальцы, чтобы изменить масштаб дорожки")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .task {
                try? await Task.sleep(nanoseconds: 4_500_000_000)
                withAnimation(.easeOut(duration: 0.4)) {
                    pinchHintShown = true
                }
            }
    }

    // MARK: - Filmstrip Track

    private var filmstripTrack: some View {
        GeometryReader { proxy in
            let width = max(60.0, proxy.size.width)
            let slotWidth = trackHeight * 16.0 / 9.0

            ZStack(alignment: .leading) {
                // База (исключает чёрные прорехи до загрузки кадров)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.85))

                // Плёнка: сетка привязана ко ВРЕМЕНИ, поэтому панорама и зум движутся непрерывно
                filmstripSlots(width: width, slotWidth: slotWidth)

                // Затемнение вне выделения
                dimmingOverlay(width: width)

                // Рамка выделения с ручками
                selectionFrame(width: width)
                    .offset(x: session.screenX(for: session.selectionStart, width: width))

                // Плейхед (позиция превью)
                playheadMarker(width: width)
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

    private func slotView(bucket: Double, slotWidth: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            if let image = session.frames[bucket] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .shimmer()
            }

            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 1)
        }
        .frame(width: slotWidth, height: trackHeight)
        .clipped()
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

        return HStack(spacing: 0) {
            handleGrip(isLeft: true)

            VStack {
                Rectangle().fill(trimmerAccent).frame(height: 3)
                Spacer()
                Rectangle().fill(trimmerAccent).frame(height: 3)
            }
            .frame(maxWidth: .infinity)

            handleGrip(isLeft: false)
        }
        .frame(width: frameWidth, height: trackHeight)
        .allowsHitTesting(false)
    }

    private func handleGrip(isLeft: Bool) -> some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: isLeft ? 8 : 0,
                bottomLeadingRadius: isLeft ? 8 : 0,
                bottomTrailingRadius: isLeft ? 0 : 8,
                topTrailingRadius: isLeft ? 0 : 8
            )
            .fill(trimmerAccent)
            .frame(width: 14)

            HStack(spacing: 2) {
                Capsule().fill(Color.black.opacity(0.85)).frame(width: 2, height: 16)
                Capsule().fill(Color.black.opacity(0.85)).frame(width: 2, height: 16)
            }
        }
        .frame(width: 14)
    }

    private func playheadMarker(width: CGFloat) -> some View {
        let px = session.screenX(for: session.playheadTime, width: width)
        return Group {
            if px >= 0 && px <= width {
                Rectangle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 2)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .offset(x: px - 1)
            }
        }
        .allowsHitTesting(false)
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

    // MARK: - Timecode Badges (следуют за ручками)

    private var handleTimecodesRow: some View {
        GeometryReader { proxy in
            let width = max(60.0, proxy.size.width)
            let startX = session.screenX(for: session.selectionStart, width: width)
            let endX = session.screenX(for: session.selectionEnd, width: width)

            ZStack(alignment: .leading) {
                timecodeBadge(formatTimecode(session.selectionStart))
                    .offset(x: max(0, min(width - 64, startX - 14)))

                timecodeBadge(formatTimecode(session.selectionEnd))
                    .offset(x: max(0, min(width - 64, endX - 50)))
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

    private func formattedDuration(_ duration: Double) -> String {
        let total = Int(round(max(1.0, duration)))
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

// MARK: - Native Publish Sheet

private struct PublishMomentSheet: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Подпись к моменту (необязательно)", text: $vm.clipCaption, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("Момент будет опубликован в общую ленту моментов.")
                }

                if let error = vm.clipPublishErrorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.system(size: 13))
                    }
                }
            }
            .navigationTitle("Новый момент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        publish()
                    } label: {
                        if vm.isClipPublishing {
                            ProgressView()
                        } else {
                            Text("Опубликовать")
                                .fontWeight(.bold)
                        }
                    }
                    .disabled(vm.isClipPublishing)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func publish() {
        guard !vm.isClipPublishing else { return }
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
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                vm.clipPublishErrorMessage = "Не удалось опубликовать момент. Проверьте интернет."
            }
        }
    }
}
