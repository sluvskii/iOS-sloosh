import SwiftUI
import UIKit

// MARK: - Clip Trim Session (Единый источник правды режима «Создать момент»)
//
// Взаимодействие построено по канонам нативных редакторов Apple (Photos / iMovie):
//  • По умолчанию открыто «окно сцены» ~2 минуты вокруг выделения (как в iMovie) —
//    на таком зуме ручки двигаются заметно; пинчем можно отдалиться до всего фильма.
//  • Плёнка кадров — реальные кадры фильма через AVAssetImageGenerator (проверенный путь
//    скраб-превью плеера), поверх подложки из постера/бэкдропа — дорожка никогда не «чернеет».
//  • Ручка выделения — обрезка; кадр за ручкой показывается в видео (грубый скраб в движении,
//    точный на отпускании). Воспроизведение на время обрезки становится на паузу.
//  • Перетаскивание тела выделения — перенос момента без прыжков видео.
//  • Перетаскивание фона дорожки — панорама плёнки (не трогает выделение и видео).
//  • Лимиты (3–60 с и края фильма): минимальная длина — жёсткий упор (как в Photos),
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

    let minSelection = PlayerViewModel.clipMinDuration
    let maxSelection = PlayerViewModel.clipMaxDuration

    // MARK: - Dependencies

    private unowned let vm: PlayerViewModel
    private var filmstripTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
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

    private static let maxCachedFrames = 700
    /// Ширина слота кадра в точках (16:9 при высоте дорожки 64).
    private static let slotPixelWidth: Double = 64.0 * 16.0 / 9.0
    /// Ход «резины» на границах в экранных точках (нативный, пиксельный скролл-фидбек).
    private static let rubberBandPoints: CGFloat = 44.0

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
    }

    func deactivate() {
        filmstripTask?.cancel()
        filmstripTask = nil
        reloadTask?.cancel()
        reloadTask = nil
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
        guard !isPinching, dragTarget != .none, width > 0 else { return }
        let deltaSec = time(atX: x, width: width) - time(atX: dragOriginTouchX, width: width)
        // «Резина» задаётся в точках экрана и пересчитывается в секунды по текущему зуму —
        // ход упора ощущается одинаково на любом масштабе (как системный скролл).
        let overshoot = Double(Self.rubberBandPoints / width) * viewSpan

        switch dragTarget {
        case .trimStart:
            // Вниз: резина на краях фильма и лимите 60 с. Вверх: жёсткий упор в
            // (end − мин.длина) — рамка никогда не выворачивается (как в Photos).
            let raw = dragOriginStart + deltaSec
            let lengthLimit = max(0.0, dragOriginEnd - maxSelection)
            var value = rubberBandMin(raw, minimum: lengthLimit, maxOvershoot: overshoot)
            value = rubberBandMin(value, minimum: 0.0, maxOvershoot: overshoot)
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
            var value = rubberBandMax(raw, maximum: lengthLimit, maxOvershoot: overshoot)
            value = rubberBandMax(value, maximum: duration, maxOvershoot: overshoot)
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

        throttledFilmstripReload()
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

        let minSpan = min(max(20.0, (selectionEnd - selectionStart) + 6.0), duration)
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

    // MARK: - Filmstrip (AVAssetImageGenerator через PlayerViewModel)

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

    private func throttledFilmstripReload() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastReloadSchedule >= 0.15 else { return }
        lastReloadSchedule = now
        scheduleFilmstripReload()
    }

    private func reloadVisibleFilmstrip() {
        guard trackWidth > 0, viewSpan > 0 else { return }

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

        filmstripTask?.cancel()
        filmstripTask = Task { [weak self] in
            guard let self else { return }
            let generated = await vm.generateTrimmerFrames(for: missing)
            guard !Task.isCancelled, !generated.isEmpty else { return }
            for (key, image) in generated where self.frames[key] == nil {
                self.frames[key] = image
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
                // БАЗОВАЯ ПОДЛОЖКА: постер/бэкдроп фильма — дорожка никогда не выглядит сломанной,
                // пока реальные кадры генерируются
                trackBaseLayer(width: width)

                // Плёнка: сетка привязана ко ВРЕМЕНИ, поэтому панорама и зум движутся непрерывно
                filmstripSlots(width: width, slotWidth: slotWidth)

                // Затемнение вне выделения
                dimmingOverlay(width: width)

                // Рамка выделения с ручками
                selectionFrame(width: width)
                    .offset(x: session.screenX(for: session.selectionStart, width: width))
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

    @ViewBuilder
    private func trackBaseLayer(width: CGFloat) -> some View {
        if let artworkStr = vm.backdropUrl ?? vm.posterUrl, let url = URL(string: artworkStr) {
            AsyncCachedImage(
                url: url,
                placeholder: {
                    Color.black.opacity(0.85)
                },
                content: { uiImage in
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: width, height: trackHeight)
                        .clipped()
                        .overlay(Color.black.opacity(0.35))
                }
            )
        } else {
            Color.black.opacity(0.85)
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
