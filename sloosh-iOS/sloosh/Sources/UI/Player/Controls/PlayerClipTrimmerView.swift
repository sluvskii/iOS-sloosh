import SwiftUI
import UIKit
import AVFoundation

// MARK: - Native Filmstrip Video Trimmer (Кинематографичная галерейная обрезка)
// Вдохновлено Telegram и Apple Photos:
// 1. Непрерывная лента РЕАЛЬНЫХ кадров (thumbnails) из видеопотока.
// 2. Масштабирование дорожки (Pinch-to-zoom жестом двумя пальцами + кнопка зума 1x/2x/4x).
// 3. Иконическая желтая рамка обрезки с тактильными ручками захвата.
// 4. Свободная перемотка и навигация по кадрам без конфликтов жестов.
// 5. Нативный системный лист публикации без лишнего мусора и выдуманных тегов.

struct PlayerClipTrimmerView: View {
    @ObservedObject var vm: PlayerViewModel

    @State private var isShowingPublishSheet: Bool = false

    // Кадры киноленты (Filmstrip thumbnails)
    @State private var filmstripThumbnails: [Int: UIImage] = [:]
    @State private var lastRequestedWindow: (start: Double, end: Double)? = nil
    @State private var isGeneratingThumbnails: Bool = false

    // Масштабирование дорожки (Span времени в секундах)
    // 30с = микро-подгонка кадров, 60с = детальная сцена, 120с = стандарт, 300с = общий план
    @State private var sceneSpan: Double = 90.0
    @State private var basePinchSpan: Double? = nil
    @State private var sceneCenterTime: Double = 0.0

    // Координатор жестов на дорожке
    private enum DragTarget {
        case none
        case leftHandle
        case rightHandle
        case middleFrame
        case playhead
    }

    @State private var activeDragTarget: DragTarget = .none
    @State private var dragInitialStart: Double = 0.0
    @State private var dragInitialEnd: Double = 0.0
    @State private var dragInitialTouchX: CGFloat = 0.0

    // Иконический желтый цвет обрезки Apple Photos
    private let appleYellow = Color(red: 1.0, green: 0.83, blue: 0.04)

    // Количество кадров в ленте по ширине экрана
    private let thumbnailSlotCount = 14

    var body: some View {
        ZStack {
            // Градиенты сверху и снизу для читаемости интерфейса поверх видео
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.85), Color.black.opacity(0.3), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 75)
                .ignoresSafeArea()

                Spacer()

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.4), Color.black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)
                .ignoresSafeArea()
            }
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
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 68, height: 68)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .shadow(color: .black.opacity(0.4), radius: 10)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

            // Основной интерфейс: Верхняя шапка + Нижняя кинолента
            VStack(spacing: 0) {
                // Шапка: Отмена • Зум / Длительность • Готово
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                Spacer()

                // Нижний блок: Кинолента кадров с желтой рамкой
                filmstripTrimmerSection
                    .padding(.horizontal, 20)
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
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()

            // Центральный блок: Длительность клипа + Кнопка зума (масштабирования)
            HStack(spacing: 8) {
                // Длительность
                Text(formattedDuration(vm.clipEndTime - vm.clipStartTime))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                Text("•")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))

                // Кнопка масштабирования дорожки (1x / 2x / 4x)
                Button {
                    cycleZoom()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.left.and.right")
                            .font(.system(size: 11, weight: .bold))
                        Text(currentZoomLabel)
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.slooshAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)

            Spacer()

            // Кнопка «Готово»
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isShowingPublishSheet = true
            } label: {
                Text("Готово")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.white.opacity(0.2), radius: 6)
            }
            .buttonStyle(.glassPress)
        }
    }

    // MARK: - Filmstrip Trimmer Section

    private var filmstripTrimmerSection: some View {
        VStack(spacing: 6) {
            // Основная дорожка с реальными кадрами и желтой рамкой
            filmstripTrackView
                .frame(height: 54)
                // Pinch-to-zoom двумя пальцами для масштабирования дорожки
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            if basePinchSpan == nil {
                                basePinchSpan = sceneSpan
                            }
                            guard let base = basePinchSpan, scale > 0.1 else { return }
                            let target = max(20.0, min(360.0, base / Double(scale)))
                            sceneSpan = target
                        }
                        .onEnded { _ in
                            basePinchSpan = nil
                            UISelectionFeedbackGenerator().selectionChanged()
                            loadThumbnailsForCurrentWindow()
                        }
                )

            // Подписи точного времени начала и конца под ручками
            HStack {
                Text(formatTimecode(vm.clipStartTime))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))

                Spacer()

                Text("Щипок для зума кадров")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))

                Spacer()

                Text(formatTimecode(vm.clipEndTime))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Filmstrip Track View (Кадры из фильма + Желтая рамка Apple)

    private var filmstripTrackView: some View {
        GeometryReader { proxy in
            let totalW = max(100.0, proxy.size.width)
            let (wStart, wEnd) = currentSceneWindow()
            let span = max(1.0, wEnd - wStart)

            // Координаты начала и конца клипа
            let startNorm = max(0.0, min(1.0, (vm.clipStartTime - wStart) / span))
            let endNorm = max(startNorm + 0.02, min(1.0, (vm.clipEndTime - wStart) / span))

            let startX = startNorm * totalW
            let endX = endNorm * totalW
            let frameW = max(34.0, endX - startX)

            // Позиция бегунка
            let playNorm = max(0.0, min(1.0, (vm.currentTime - wStart) / span))
            let playX = max(0.0, min(totalW - 2.5, playNorm * totalW))

            ZStack(alignment: .leading) {
                // 1. ЛЕНТА КАДРОВ ИЗ ФИЛЬМА (Filmstrip Thumbnails)
                HStack(spacing: 0) {
                    ForEach(0..<thumbnailSlotCount, id: \.self) { slotIdx in
                        if let img = filmstripThumbnails[slotIdx] {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: totalW / CGFloat(thumbnailSlotCount), height: 54)
                                .clipped()
                        } else {
                            // Аккуратный тёмный плейсхолдер с легким делением
                            ZStack {
                                Color.black.opacity(0.75)
                                Rectangle()
                                    .fill(Color.white.opacity(0.06))
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(width: totalW / CGFloat(thumbnailSlotCount), height: 54)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

                // 2. Затемнение слева от рамки (кадры вне клипа приглушены)
                if startX > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: startX)
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
                if endX < totalW {
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: totalW - endX)
                        .offset(x: endX)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 10,
                                topTrailingRadius: 10
                            )
                        )
                }

                // 4. ИКОНИЧЕСКАЯ ЖЕЛТАЯ РАМКА ОБРЕЗКИ APPLE PHOTOS
                ZStack {
                    // Верхняя и нижняя границы
                    VStack {
                        Rectangle()
                            .fill(appleYellow)
                            .frame(height: 3)
                        Spacer()
                        Rectangle()
                            .fill(appleYellow)
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
                            .fill(appleYellow)
                            .frame(width: 16)

                            VStack(spacing: 3) {
                                Capsule().fill(Color.black.opacity(0.75)).frame(width: 2, height: 14)
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
                            .fill(appleYellow)
                            .frame(width: 16)

                            VStack(spacing: 3) {
                                Capsule().fill(Color.black.opacity(0.75)).frame(width: 2, height: 14)
                            }
                        }
                    }
                }
                .frame(width: frameW)
                .offset(x: startX)

                // 5. Белый бегунок текущего кадра (Playhead)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2.5, height: 54)
                    .shadow(color: .black.opacity(0.8), radius: 3)
                    .offset(x: playX)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            // Единый координатор жестов без конфликтов
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let touchX = val.location.x

                        if activeDragTarget == .none {
                            dragInitialTouchX = touchX
                            dragInitialStart = vm.clipStartTime
                            dragInitialEnd = vm.clipEndTime

                            let hitSlop: CGFloat = 24.0
                            if abs(touchX - startX) <= hitSlop {
                                activeDragTarget = .leftHandle
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else if abs(touchX - endX) <= hitSlop {
                                activeDragTarget = .rightHandle
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else if touchX > startX && touchX < endX {
                                activeDragTarget = .middleFrame
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else {
                                activeDragTarget = .playhead
                            }
                        }

                        let deltaX = touchX - dragInitialTouchX
                        let deltaSec = Double(deltaX / totalW) * span
                        let maxLimit = vm.currentDuration > 0 ? vm.currentDuration : (vm.clipEndTime + 300)

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

                        case .playhead, .none:
                            let targetSec = max(0.0, min(maxLimit, wStart + (Double(touchX / totalW) * span)))
                            vm.seekClip(to: targetSec)
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
        let center = sceneCenterTime > 0 ? sceneCenterTime : ((vm.clipStartTime + vm.clipEndTime) / 2.0)
        let maxLimit = vm.currentDuration > 0 ? vm.currentDuration : (center + sceneSpan)
        let half = sceneSpan / 2.0
        var wStart = max(0.0, center - half)
        var wEnd = min(maxLimit, wStart + sceneSpan)

        if wStart > vm.clipStartTime {
            wStart = max(0.0, vm.clipStartTime - 5.0)
            wEnd = min(maxLimit, wStart + sceneSpan)
        }
        if wEnd < vm.clipEndTime {
            wEnd = min(maxLimit, vm.clipEndTime + 5.0)
            wStart = max(0.0, wEnd - sceneSpan)
        }

        return (wStart, max(wStart + 10.0, wEnd))
    }

    private func syncSceneCenter() {
        sceneCenterTime = (vm.clipStartTime + vm.clipEndTime) / 2.0
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
                // Находим ближайший слот
                if let closestSlot = slotMap.min(by: { abs($0.key - t) < abs($1.key - t) })?.value {
                    filmstripThumbnails[closestSlot] = img
                }
            }
        }
    }

    // MARK: - Zoom Controls

    private var currentZoomLabel: String {
        if sceneSpan <= 35.0 {
            return "4x"
        } else if sceneSpan <= 75.0 {
            return "2x"
        } else if sceneSpan <= 150.0 {
            return "1x"
        } else {
            return "0.5x"
        }
    }

    private func cycleZoom() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if sceneSpan <= 35.0 {
                sceneSpan = 120.0 // 1x
            } else if sceneSpan <= 75.0 {
                sceneSpan = 30.0  // 4x
            } else if sceneSpan <= 150.0 {
                sceneSpan = 60.0  // 2x
            } else {
                sceneSpan = 120.0 // 1x
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
                    Text("Момент будет опубликован в ленту моментов.")
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
