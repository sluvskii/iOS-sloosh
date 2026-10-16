import SwiftUI
import UIKit
import AVFoundation

// MARK: - Native Filmstrip Video Trimmer (Кинематографичная обрезка в фирменном стиле sloosh)
// 1. Полное масштабирование: от 20 секунд (микро-точность) до 100% хронометража фильма («Весь фильм»).
// 2. Фирменный акцентный стиль Color.slooshAccent без чужеродных цветов и белых палок.
// 3. Непрерывная кинолента: кадры из фильма и живые кадры из плеера (никаких черных полос).
// 4. Лаконичный верхний бар: только длительность момента, без лишних надписей зума.
// 5. Бесшовный сплошной градиент без ступенек и обрывов.
// 6. Нативный системный лист публикации без лишнего мусора.

struct PlayerClipTrimmerView: View {
    @ObservedObject var vm: PlayerViewModel

    @State private var isShowingPublishSheet: Bool = false

    // Кадры киноленты (Filmstrip thumbnails)
    @State private var filmstripThumbnails: [Int: UIImage] = [:]
    @State private var lastRequestedWindow: (start: Double, end: Double)? = nil

    // Масштабирование дорожки (Span времени в секундах)
    // По умолчанию: 90 секунд (детальный обзор сцены)
    @State private var sceneSpan: Double = 90.0
    @State private var basePinchSpan: Double? = nil
    @State private var sceneCenterTime: Double = 0.0

    // Фирменный акцент sloosh
    private let trimmerAccent = Color.slooshAccent

    // Координатор жестов на дорожке
    private enum DragTarget {
        case none
        case leftHandle
        case rightHandle
        case middleFrame
    }

    @State private var activeDragTarget: DragTarget = .none
    @State private var dragInitialStart: Double = 0.0
    @State private var dragInitialEnd: Double = 0.0
    @State private var dragInitialTouchX: CGFloat = 0.0

    // Количество кадров в ленте по ширине экрана
    private let thumbnailSlotCount = 14

    private var totalMovieDuration: Double {
        let dur = vm.currentDuration
        return (dur.isFinite && !dur.isNaN && dur > 1.0) ? dur : max(vm.clipEndTime + 60.0, 1800.0)
    }

    var body: some View {
        ZStack {
            // Плавный сплошной градиент на весь экран без обрывов и ступенек
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.80), location: 0.0),
                    .init(color: Color.black.opacity(0.25), location: 0.22),
                    .init(color: .clear, location: 0.42),
                    .init(color: .clear, location: 0.62),
                    .init(color: Color.black.opacity(0.40), location: 0.78),
                    .init(color: Color.black.opacity(0.92), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Центральная область: тап для Play / Pause видео
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    vm.togglePlayPause()
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

            // Основной интерфейс: Верхняя шапка + Нижняя кинолента
            VStack(spacing: 0) {
                // Шапка: Отмена • Длительность (например 0:30) • Готово
                topBar
                    .padding(.top, 14)
                    .padding(.horizontal, 24)

                Spacer()

                // Нижний блок: Кинолента кадров с фирменной рамкой sloosh
                filmstripTrimmerSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
        }
        .onAppear {
            sceneCenterTime = (vm.clipStartTime + vm.clipEndTime) / 2.0
            loadThumbnailsForCurrentWindow()
        }
        .sheet(isPresented: $isShowingPublishSheet) {
            PublishMomentSheet(vm: vm)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.isPlaying)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Кнопка «Отмена»
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

            // Центральный блок: Только длительность момента (например «0:30»), без лишних слов
            Text(formattedDuration(vm.clipEndTime - vm.clipStartTime))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)

            Spacer()

            // Кнопка «Готово»
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

    // MARK: - Filmstrip Trimmer Section

    private var filmstripTrimmerSection: some View {
        VStack(spacing: 8) {
            // Дорожка с кадрами из фильма и фирменной рамкой sloosh
            filmstripTrackView
                .frame(height: 56)
                // Двойной тап по дорожке: мгновенное переключение между сценой и всем фильмом
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            toggleTimelineZoom()
                        }
                )
                // Pinch-to-zoom двумя пальцами для масштабирования дорожки от 20с до всего фильма
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            if basePinchSpan == nil {
                                basePinchSpan = sceneSpan
                            }
                            guard let base = basePinchSpan, scale > 0.05 else { return }
                            let clipLength = vm.clipEndTime - vm.clipStartTime
                            let minSpan = max(20.0, clipLength + 4.0)
                            let maxLimit = totalMovieDuration
                            let target = max(minSpan, min(maxLimit, base / Double(scale)))
                            sceneSpan = target
                        }
                        .onEnded { _ in
                            basePinchSpan = nil
                            UISelectionFeedbackGenerator().selectionChanged()
                            loadThumbnailsForCurrentWindow()
                        }
                )

            // Подписи точного времени начала и конца под ручками обрезки
            HStack {
                Text(formatTimecode(vm.clipStartTime))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                Text(formatTimecode(vm.clipEndTime))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Filmstrip Track View (Кадры из фильма + Рамка sloosh)

    private var filmstripTrackView: some View {
        GeometryReader { proxy in
            let totalW = max(100.0, proxy.size.width)
            let (wStart, wEnd) = currentSceneWindow()
            let span = max(1.0, wEnd - wStart)

            // Координаты начала и конца клипа
            let startNorm = max(0.0, min(1.0, (vm.clipStartTime - wStart) / span))
            let endNorm = max(startNorm + 0.005, min(1.0, (vm.clipEndTime - wStart) / span))

            let startX = startNorm * totalW
            let endX = endNorm * totalW
            let rawFrameW = max(0.0, endX - startX)
            let frameW = max(32.0, rawFrameW)

            let visualStartX = startX
            let visualEndX = startX + frameW

            ZStack(alignment: .leading) {
                // 1. ЛЕНТА КАДРОВ ИЗ ФИЛЬМА (Фон фильма + Кадры)
                ZStack {
                    // Фоновая панорама фильма: дорожка никогда не остаётся пустой черной полосой
                    if let backdropStr = vm.backdropUrl ?? vm.posterUrl, let url = URL(string: backdropStr) {
                        AsyncCachedImage(url: url) { img in
                            img
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: totalW, height: 56)
                                .clipped()
                                .opacity(0.82)
                        } placeholder: {
                            Color.black.opacity(0.75)
                        }
                    }

                    // Сетка слотов кадров с разделителями кинопленки
                    HStack(spacing: 0) {
                        ForEach(0..<thumbnailSlotCount, id: \.self) { slotIdx in
                            let slotWidth = totalW / CGFloat(thumbnailSlotCount)
                            let slotCenterSec = wStart + (Double(slotIdx) + 0.5) * (span / Double(thumbnailSlotCount))
                            let frameImg = filmstripThumbnails[slotIdx] ?? closestLiveFrame(near: slotCenterSec)

                            ZStack {
                                if let img = frameImg {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: slotWidth, height: 56)
                                        .clipped()
                                }

                                // Вертикальный разделитель кадров
                                HStack {
                                    Spacer()
                                    Rectangle()
                                        .fill(Color.white.opacity(0.12))
                                        .frame(width: 1, height: 56)
                                }
                            }
                            .frame(width: slotWidth, height: 56)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )

                // 2. Затемнение слева от рамки (кадры вне клипа приглушены)
                if visualStartX > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.65))
                        .frame(width: visualStartX)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 10,
                                bottomLeadingRadius: 10,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 0
                            )
                        )
                }

                // 3. Затемнение справа от рамки
                if visualEndX < totalW {
                    Rectangle()
                        .fill(Color.black.opacity(0.65))
                        .frame(width: totalW - visualEndX)
                        .offset(x: visualEndX)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 10,
                                topTrailingRadius: 10
                            )
                        )
                }

                // 4. ФИРМЕННАЯ РАМКА ОБРЕЗКИ SLOOSH
                ZStack {
                    // Верхняя и нижняя границы
                    VStack {
                        Rectangle()
                            .fill(trimmerAccent)
                            .frame(height: 3)
                        Spacer()
                        Rectangle()
                            .fill(trimmerAccent)
                            .frame(height: 3)
                    }

                    // Левая и правая ручки захвата
                    HStack {
                        // Левая ручка
                        ZStack {
                            UnevenRoundedRectangle(
                                topLeadingRadius: 8,
                                bottomLeadingRadius: 8,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 0
                            )
                            .fill(trimmerAccent)
                            .frame(width: 16)

                            VStack(spacing: 3) {
                                Capsule().fill(Color.black.opacity(0.85)).frame(width: 2, height: 14)
                            }
                        }

                        Spacer()

                        // Правая ручка
                        ZStack {
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 8,
                                topTrailingRadius: 8
                            )
                            .fill(trimmerAccent)
                            .frame(width: 16)

                            VStack(spacing: 3) {
                                Capsule().fill(Color.black.opacity(0.85)).frame(width: 2, height: 14)
                            }
                        }
                    }
                }
                .frame(width: frameW)
                .offset(x: visualStartX)
            }
            .contentShape(Rectangle())
            // Единый координатор жестов: перемещение ручек, сдвиг клипа и быстрый переход
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let touchX = val.location.x

                        if activeDragTarget == .none {
                            dragInitialTouchX = touchX
                            dragInitialStart = vm.clipStartTime
                            dragInitialEnd = vm.clipEndTime

                            let hitSlop: CGFloat = 22.0
                            let leftHandleCenter = visualStartX + 8.0
                            let rightHandleCenter = visualEndX - 8.0

                            if abs(touchX - leftHandleCenter) <= hitSlop {
                                activeDragTarget = .leftHandle
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else if abs(touchX - rightHandleCenter) <= hitSlop {
                                activeDragTarget = .rightHandle
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else if touchX >= visualStartX && touchX <= visualEndX {
                                activeDragTarget = .middleFrame
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else {
                                // Касание вне рамки: мгновенно центрируем рамку момента на этой сцене
                                activeDragTarget = .middleFrame
                                let clipLen = vm.clipEndTime - vm.clipStartTime
                                let touchSec = max(0.0, min(totalMovieDuration, wStart + (Double(touchX / totalW) * span)))
                                var newStart = max(0.0, touchSec - clipLen / 2.0)
                                var newEnd = newStart + clipLen
                                if newEnd > totalMovieDuration {
                                    newEnd = totalMovieDuration
                                    newStart = max(0.0, newEnd - clipLen)
                                }
                                vm.clipStartTime = newStart
                                vm.clipEndTime = newEnd
                                vm.seekClip(to: newStart)
                                dragInitialTouchX = touchX
                                dragInitialStart = newStart
                                dragInitialEnd = newEnd
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }

                        let deltaX = touchX - dragInitialTouchX
                        let deltaSec = Double(deltaX / totalW) * span
                        let maxLimit = totalMovieDuration

                        switch activeDragTarget {
                        case .leftHandle:
                            let newStart = max(0.0, min(vm.clipEndTime - 2.0, dragInitialStart + deltaSec))
                            vm.clipStartTime = newStart
                            vm.seekClip(to: newStart)

                        case .rightHandle:
                            let newEnd = min(maxLimit, max(vm.clipStartTime + 2.0, dragInitialEnd + deltaSec))
                            vm.clipEndTime = newEnd
                            vm.seekClip(to: max(vm.clipStartTime, newEnd - 1.0))

                        case .middleFrame:
                            let clipLength = dragInitialEnd - dragInitialStart
                            var newStart = max(0.0, dragInitialStart + deltaSec)
                            var newEnd = newStart + clipLength
                            if newEnd > maxLimit {
                                newEnd = maxLimit
                                newStart = max(0.0, newEnd - clipLength)
                            }
                            vm.clipStartTime = newStart
                            vm.clipEndTime = newEnd
                            vm.seekClip(to: newStart)

                        case .none:
                            break
                        }
                    }
                    .onEnded { _ in
                        activeDragTarget = .none
                        UISelectionFeedbackGenerator().selectionChanged()
                        syncSceneCenter()
                        loadThumbnailsForCurrentWindow()
                    }
            )
        }
    }

    // MARK: - Scene Window & Thumbnails Loader

    private func currentSceneWindow() -> (Double, Double) {
        let total = totalMovieDuration
        // Если масштаб равен или больше всего фильма — показываем весь хронометраж целиком!
        if sceneSpan >= total - 1.0 {
            return (0.0, total)
        }

        let center = sceneCenterTime > 0 ? sceneCenterTime : ((vm.clipStartTime + vm.clipEndTime) / 2.0)
        let half = sceneSpan / 2.0
        var wStart = max(0.0, center - half)
        var wEnd = min(total, wStart + sceneSpan)

        if wStart > vm.clipStartTime {
            wStart = max(0.0, vm.clipStartTime - 5.0)
            wEnd = min(total, wStart + sceneSpan)
        }
        if wEnd < vm.clipEndTime {
            wEnd = min(total, vm.clipEndTime + 5.0)
            wStart = max(0.0, wEnd - sceneSpan)
        }

        return (wStart, max(wStart + 10.0, wEnd))
    }

    private func syncSceneCenter() {
        sceneCenterTime = (vm.clipStartTime + vm.clipEndTime) / 2.0
    }

    private func closestLiveFrame(near time: Double) -> UIImage? {
        guard !vm.liveClipFrames.isEmpty else { return nil }
        let threshold = max(2.5, sceneSpan / Double(thumbnailSlotCount))
        if let match = vm.liveClipFrames.min(by: { abs($0.key - time) < abs($1.key - time) }),
           abs(match.key - time) <= threshold {
            return match.value
        }
        return nil
    }

    private func loadThumbnailsForCurrentWindow() {
        let (wStart, wEnd) = currentSceneWindow()
        if let last = lastRequestedWindow, abs(last.start - wStart) < 3.0 && abs(last.end - wEnd) < 3.0 {
            return
        }
        lastRequestedWindow = (wStart, wEnd)

        let span = max(1.0, wEnd - wStart)
        let step = span / Double(thumbnailSlotCount)
        var times: [Double] = []
        var slotMap: [Double: Int] = [:]

        for i in 0..<thumbnailSlotCount {
            let t = wStart + (Double(i) + 0.5) * step
            times.append(t)
            slotMap[t] = i
        }

        vm.generateFilmstrip(times: times) { results in
            for (t, img) in results {
                if let closestSlot = slotMap.min(by: { abs($0.key - t) < abs($1.key - t) })?.value {
                    filmstripThumbnails[closestSlot] = img
                }
            }
        }
    }

    // MARK: - Zoom Controls

    private func toggleTimelineZoom() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let total = totalMovieDuration

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if sceneSpan >= total - 10.0 {
                // Из «Весь фильм» переходим в детальную сцену (90 сек)
                sceneSpan = min(90.0, total)
                syncSceneCenter()
            } else {
                // Из сцены разворачиваем на «Весь фильм» целиком
                sceneSpan = total
            }
        }
        loadThumbnailsForCurrentWindow()
    }

    // MARK: - Formatters

    private func formattedDuration(_ dur: Double) -> String {
        let total = Int(round(max(1.0, dur)))
        let m = total / 60
        let s = total % 60
        if m > 0 {
            return String(format: "%d:%02d", m, s)
        }
        return String(format: "0:%02d", s)
    }

    private func formatTimecode(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
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
