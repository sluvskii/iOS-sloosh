import SwiftUI
import UIKit
import AVFoundation

// MARK: - Native Cinema Filmstrip Video Trimmer (Флагманская обрезка моментов sloosh)
// 1. Двухуровневый масштаб: детальная «Сцена» (точная подгонка) ↔ «Весь фильм» (охват 100% хронометража).
// 2. Безупречное затемнение (HStack-маска без глитчей и оборванных краев).
// 3. Кинематографичная лента 35мм с перфорацией и живыми декодированными кадрами из AVPlayerItemVideoOutput.
// 4. Бейджи точного времени привязаны прямо к ручкам обрезки и следуют за пальцем.
// 5. Минималистичный верхний бар: только длительность момента (0:30), без лишнего текста.
// 6. Плавный бесшовный полноэкранный градиент.

struct PlayerClipTrimmerView: View {
    @ObservedObject var vm: PlayerViewModel

    @State private var isShowingPublishSheet: Bool = false

    // Масштабирование дорожки (Span времени в секундах)
    // По умолчанию: детальный обзор сцены (90 секунд)
    @State private var sceneSpan: Double = 90.0
    @State private var isFullMovieScale: Bool = false
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

            // Основной интерфейс: Верхняя шапка + Нижний блок монтажа
            VStack(spacing: 0) {
                // Шапка: Отмена • Длительность (например 0:30) • Готово
                topBar
                    .padding(.top, 14)
                    .padding(.horizontal, 24)

                Spacer()

                // Нижний блок монтажа: Дорожка + Бейджи времени у ручек + Переключатель масштаба
                VStack(spacing: 6) {
                    filmstripTrackView
                        .frame(height: 56)

                    // Бейджи точного времени под ручками обрезки
                    handleTimecodesRow

                    // Нижняя строка: Границы видимого окна + Переключатель масштаба (Сцена ↔ Весь фильм)
                    timelineFooterRow
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .onAppear {
            sceneCenterTime = (vm.clipStartTime + vm.clipEndTime) / 2.0
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
                .font(.system(size: 15, weight: .bold, design: .rounded))
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

    // MARK: - Filmstrip Track View (35мм кинолента + Безупречное затемнение + Рамка sloosh)

    private var filmstripTrackView: some View {
        GeometryReader { proxy in
            let totalW = max(100.0, proxy.size.width)
            let (wStart, wEnd) = currentSceneWindow()
            let span = max(1.0, wEnd - wStart)

            // Координаты рамки обрезки
            let startFrac = max(0.0, min(1.0, (vm.clipStartTime - wStart) / span))
            let endFrac = max(startFrac, min(1.0, (vm.clipEndTime - wStart) / span))

            let startX = startFrac * totalW
            let endX = max(startX + 32.0, endFrac * totalW)
            let frameW = max(32.0, endX - startX)

            ZStack(alignment: .leading) {
                // 1. КИНОЛЕНТА 35ММ СО СЛОТАМИ КАДРОВ
                HStack(spacing: 0) {
                    ForEach(0..<thumbnailSlotCount, id: \.self) { slotIdx in
                        let slotW = totalW / CGFloat(thumbnailSlotCount)
                        let slotCenterSec = wStart + (Double(slotIdx) + 0.5) * (span / Double(thumbnailSlotCount))
                        let frameImg = vm.liveFrame(near: slotCenterSec)

                        ZStack {
                            // Темная кинематографичная подложка
                            Color.black.opacity(0.85)

                            // Реальный живой кадр из видео (если доступен)
                            if let img = frameImg {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: slotW, height: 56)
                                    .clipped()
                            }

                            // Перфорация кинопленки 35мм сверху и снизу
                            VStack {
                                HStack(spacing: 3) {
                                    ForEach(0..<2, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.white.opacity(0.12))
                                            .frame(width: 5, height: 3)
                                    }
                                }
                                Spacer()
                                HStack(spacing: 3) {
                                    ForEach(0..<2, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.white.opacity(0.12))
                                            .frame(width: 5, height: 3)
                                    }
                                }
                            }
                            .padding(.vertical, 3)

                            // Вертикальный разделитель кадров
                            HStack {
                                Spacer()
                                Rectangle()
                                    .fill(Color.white.opacity(0.10))
                                    .frame(width: 1, height: 56)
                            }
                        }
                        .frame(width: slotW, height: 56)
                    }
                }

                // 2. БЕЗУПРЕЧНОЕ ЗАТЕМНЕНИЕ (Слева и справа от рамки, без глитчей и обрывов)
                HStack(spacing: 0) {
                    if startX > 0 {
                        Rectangle()
                            .fill(Color.black.opacity(0.68))
                            .frame(width: startX)
                    }

                    Spacer(minLength: 0)
                        .frame(width: frameW)

                    if totalW > endX {
                        Rectangle()
                            .fill(Color.black.opacity(0.68))
                            .frame(width: totalW - endX)
                    }
                }

                // 3. ФИРМЕННАЯ РАМКА ОБРЕЗКИ SLOOSH
                HStack(spacing: 0) {
                    // Левая ручка захвата
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
                            Capsule().fill(Color.black.opacity(0.85)).frame(width: 2.5, height: 16)
                        }
                    }

                    // Верхняя и нижняя соединительные границы
                    VStack {
                        Rectangle()
                            .fill(trimmerAccent)
                            .frame(height: 3)
                        Spacer()
                        Rectangle()
                            .fill(trimmerAccent)
                            .frame(height: 3)
                    }
                    .frame(maxWidth: .infinity)

                    // Правая ручка захвата
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
                            Capsule().fill(Color.black.opacity(0.85)).frame(width: 2.5, height: 16)
                        }
                    }
                }
                .frame(width: frameW, height: 56)
                .offset(x: startX)
            }
            .frame(width: totalW, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .contentShape(Rectangle())
            // Двойной тап по дорожке: мгновенное переключение «Сцена» ↔ «Весь фильм»
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        toggleScaleMode()
                    }
            )
            // Плавный щипок двумя пальцами для масштабирования
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        if basePinchSpan == nil {
                            basePinchSpan = isFullMovieScale ? totalMovieDuration : sceneSpan
                        }
                        guard let base = basePinchSpan, scale > 0.05 else { return }
                        let clipLen = vm.clipEndTime - vm.clipStartTime
                        let minSpan = max(20.0, clipLen + 6.0)
                        let maxLimit = totalMovieDuration
                        let target = max(minSpan, min(maxLimit, base / Double(scale)))
                        sceneSpan = target
                        isFullMovieScale = (target >= totalMovieDuration - 10.0)
                    }
                    .onEnded { _ in
                        basePinchSpan = nil
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
            )
            // Единый надежный координатор жестов: перемещение ручек, сдвиг клипа и быстрый переход
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let touchX = val.location.x

                        if activeDragTarget == .none {
                            dragInitialTouchX = touchX
                            dragInitialStart = vm.clipStartTime
                            dragInitialEnd = vm.clipEndTime

                            let hitSlop: CGFloat = 24.0
                            let leftHandleX = startX
                            let rightHandleX = endX

                            if abs(touchX - leftHandleX) <= hitSlop {
                                activeDragTarget = .leftHandle
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else if abs(touchX - rightHandleX) <= hitSlop {
                                activeDragTarget = .rightHandle
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else if touchX >= startX && touchX <= endX {
                                activeDragTarget = .middleFrame
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } else {
                                // Касание вне рамки: мягко смещаем окно клипа к точке касания
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
                            let minStart = 0.0
                            let maxStart = vm.clipEndTime - 3.0 // минимум 3 секунды клип
                            let newStart = max(minStart, min(maxStart, dragInitialStart + deltaSec))
                            vm.clipStartTime = newStart
                            vm.seekClip(to: newStart)

                        case .rightHandle:
                            let minEnd = vm.clipStartTime + 3.0 // минимум 3 секунды клип
                            let maxEnd = min(maxLimit, vm.clipStartTime + 90.0) // максимум 90 секунд
                            let newEnd = min(maxEnd, max(minEnd, dragInitialEnd + deltaSec))
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
                    }
            )
        }
    }

    // MARK: - Handle Timecodes Row (Бейджи времени прямо под ручками)

    private var handleTimecodesRow: some View {
        GeometryReader { proxy in
            let totalW = max(100.0, proxy.size.width)
            let (wStart, wEnd) = currentSceneWindow()
            let span = max(1.0, wEnd - wStart)

            let startFrac = max(0.0, min(1.0, (vm.clipStartTime - wStart) / span))
            let endFrac = max(startFrac, min(1.0, (vm.clipEndTime - wStart) / span))

            let startX = startFrac * totalW
            let endX = max(startX + 32.0, endFrac * totalW)

            ZStack(alignment: .leading) {
                // Бейдж начала клипа (под левой ручкой)
                Text(formatTimecode(vm.clipStartTime))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(trimmerAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.80))
                    .clipShape(Capsule())
                    .offset(x: max(0, min(totalW - 65, startX - 16)))

                // Бейдж конца клипа (под правой ручкой)
                Text(formatTimecode(vm.clipEndTime))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(trimmerAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.80))
                    .clipShape(Capsule())
                    .offset(x: max(0, min(totalW - 65, endX - 26)))
            }
        }
        .frame(height: 20)
    }

    // MARK: - Timeline Footer Row (Границы окна + Кнопка «Сцена / Весь фильм»)

    private var timelineFooterRow: some View {
        HStack {
            let (wStart, wEnd) = currentSceneWindow()

            // Время начала видимого окна
            Text(formatTimecode(wStart))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))

            Spacer()

            // Кнопка быстрого переключения масштаба: «Сцена» (2м) ↔ «Весь фильм» (100%)
            Button {
                toggleScaleMode()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isFullMovieScale ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(isFullMovieScale ? "Сцена" : "Весь фильм")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.90))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()

            // Время конца видимого окна
            Text(formatTimecode(wEnd))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Scale & Scene Window

    private func currentSceneWindow() -> (Double, Double) {
        let total = totalMovieDuration
        if isFullMovieScale || sceneSpan >= total - 1.0 {
            return (0.0, total)
        }

        let center = sceneCenterTime > 0 ? sceneCenterTime : ((vm.clipStartTime + vm.clipEndTime) / 2.0)
        let half = sceneSpan / 2.0
        var wStart = max(0.0, center - half)
        var wEnd = min(total, wStart + sceneSpan)

        if wStart > vm.clipStartTime {
            wStart = max(0.0, vm.clipStartTime - 10.0)
            wEnd = min(total, wStart + sceneSpan)
        }
        if wEnd < vm.clipEndTime {
            wEnd = min(total, vm.clipEndTime + 10.0)
            wStart = max(0.0, wEnd - sceneSpan)
        }

        return (wStart, max(wStart + 10.0, wEnd))
    }

    private func syncSceneCenter() {
        sceneCenterTime = (vm.clipStartTime + vm.clipEndTime) / 2.0
    }

    private func toggleScaleMode() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isFullMovieScale.toggle()
            if !isFullMovieScale {
                sceneSpan = 90.0
                syncSceneCenter()
            }
        }
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
