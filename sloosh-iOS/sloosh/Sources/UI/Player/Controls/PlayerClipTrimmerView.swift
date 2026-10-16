import SwiftUI
import UIKit
import AVFoundation

// MARK: - Native Cinema Filmstrip Video Trimmer (Флагманская обрезка моментов sloosh)
// 1. Мгновенный 120 FPS отклик: независимое локальное состояние без блокировки AVPlayer и без задержек.
// 2. Двухуровневый кинематографичный масштаб: детальная «Сцена» (120с) ↔ «Весь фильм» (100% хронометража).
// 3. Безупречное затемнение (HStack-маска без глитчей и артефактов).
// 4. Кинематографичная лента 35мм с кадром из фильма, перфорацией и живыми декодированными кадрами.
// 5. Бейджи точного времени привязаны прямо к ручкам и плавно следуют за пальцем в реальном времени.
// 6. Минималистичный верхний бар: только длительность момента (0:30), без лишнего текста.
// 7. Бесшовный непрерывный градиент на весь экран без обрывов.

struct PlayerClipTrimmerView: View {
    @ObservedObject var vm: PlayerViewModel

    @State private var isShowingPublishSheet: Bool = false

    // Масштабирование дорожки (Span времени в секундах)
    // По умолчанию: детальный обзор сцены (120 секунд)
    @State private var sceneSpan: Double = 120.0
    @State private var isFullMovieScale: Bool = false
    @State private var sceneWindowStart: Double = 0.0

    // Локальное состояние для мгновенного (120 FPS) перемещения без лагов и задержек
    @State private var localStartTime: Double = 0.0
    @State private var localEndTime: Double = 0.0
    @State private var isDragging: Bool = false
    @State private var lastSeekTime: TimeInterval = 0

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
    @State private var dragInitialWindowStart: Double = 0.0

    // Количество кадров в ленте по ширине экрана
    private let thumbnailSlotCount = 14

    private var totalMovieDuration: Double {
        let dur = vm.currentDuration
        return (dur.isFinite && !dur.isNaN && dur > 1.0) ? dur : max(localEndTime + 60.0, 1800.0)
    }

    private var currentWindow: (start: Double, end: Double, span: Double) {
        if isFullMovieScale {
            let total = max(10.0, totalMovieDuration)
            return (0.0, total, total)
        } else {
            let span = min(sceneSpan, totalMovieDuration)
            let maxStart = max(0.0, totalMovieDuration - span)
            let start = max(0.0, min(maxStart, sceneWindowStart))
            let end = min(totalMovieDuration, start + span)
            return (start, end, max(1.0, end - start))
        }
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
            localStartTime = vm.clipStartTime
            localEndTime = vm.clipEndTime
            adjustSceneWindow(toInclude: vm.clipStartTime, end: vm.clipEndTime)
        }
        .onChange(of: vm.clipStartTime) { _, newStart in
            if !isDragging {
                localStartTime = newStart
                if !isFullMovieScale {
                    adjustSceneWindow(toInclude: newStart, end: localEndTime)
                }
            }
        }
        .onChange(of: vm.clipEndTime) { _, newEnd in
            if !isDragging {
                localEndTime = newEnd
                if !isFullMovieScale {
                    adjustSceneWindow(toInclude: localStartTime, end: newEnd)
                }
            }
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
            Text(formattedDuration(localEndTime - localStartTime))
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
            let win = currentWindow

            // Координаты рамки обрезки рассчитываются по локальным переменным с мгновенным откликом
            let startFrac = max(0.0, min(1.0, (localStartTime - win.start) / win.span))
            let endFrac = max(startFrac, min(1.0, (localEndTime - win.start) / win.span))

            let startX = startFrac * totalW
            let endX = max(startX + 36.0, endFrac * totalW)
            let frameW = max(36.0, endX - startX)

            ZStack(alignment: .leading) {
                // 1. БАЗОВАЯ ПОДЛОЖКА С ОБЛОЖКОЙ ФИЛЬМА (Исключает черную полосу даже без загруженных кадров)
                if let backdrop = vm.backdropUrl, !backdrop.isEmpty {
                    AsyncCachedImage(urlString: backdrop) { uiImage in
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: totalW, height: 56)
                            .clipped()
                            .overlay(Color.black.opacity(0.35))
                    } placeholder: {
                        Color.black.opacity(0.85)
                    }
                } else {
                    Color.black.opacity(0.85)
                }

                // 2. КИНОЛЕНТА 35ММ СО СЛОТАМИ КАДРОВ
                HStack(spacing: 0) {
                    ForEach(0..<thumbnailSlotCount, id: \.self) { slotIdx in
                        let slotW = totalW / CGFloat(thumbnailSlotCount)
                        let slotCenterSec = win.start + (Double(slotIdx) + 0.5) * (win.span / Double(thumbnailSlotCount))
                        let frameImg = vm.liveFrame(near: slotCenterSec)

                        ZStack {
                            // Реальный живой кадр из видео (если захвачен)
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
                                            .fill(Color.white.opacity(0.18))
                                            .frame(width: 5, height: 3)
                                    }
                                }
                                Spacer()
                                HStack(spacing: 3) {
                                    ForEach(0..<2, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.white.opacity(0.18))
                                            .frame(width: 5, height: 3)
                                    }
                                }
                            }
                            .padding(.vertical, 3)

                            // Вертикальный разделитель кадров
                            HStack {
                                Spacer()
                                Rectangle()
                                    .fill(Color.white.opacity(0.12))
                                    .frame(width: 1, height: 56)
                            }
                        }
                        .frame(width: slotW, height: 56)
                    }
                }

                // 3. БЕЗУПРЕЧНОЕ ЗАТЕМНЕНИЕ (Слева и справа от рамки, без глитчей и обрывов)
                HStack(spacing: 0) {
                    if startX > 0 {
                        Rectangle()
                            .fill(Color.black.opacity(0.70))
                            .frame(width: startX)
                    }

                    Spacer(minLength: 0)
                        .frame(width: frameW)

                    if totalW > endX {
                        Rectangle()
                            .fill(Color.black.opacity(0.70))
                            .frame(width: max(0, totalW - endX))
                    }
                }

                // 4. ФИРМЕННАЯ РАМКА ОБРЕЗКИ SLOOSH
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

                        HStack(spacing: 2) {
                            Capsule().fill(Color.black.opacity(0.85)).frame(width: 2, height: 16)
                            Capsule().fill(Color.black.opacity(0.85)).frame(width: 2, height: 16)
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

                        HStack(spacing: 2) {
                            Capsule().fill(Color.black.opacity(0.85)).frame(width: 2, height: 16)
                            Capsule().fill(Color.black.opacity(0.85)).frame(width: 2, height: 16)
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
            // Единый чистый жест DragGesture с мгновенным откликом (120 FPS)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let touchX = val.location.x
                        let startTouchX = val.startLocation.x

                        if activeDragTarget == .none {
                            isDragging = true
                            vm.isUserSeeking = true
                            dragInitialTouchX = startTouchX
                            dragInitialStart = localStartTime
                            dragInitialEnd = localEndTime
                            dragInitialWindowStart = sceneWindowStart

                            let leftCenterX = startX + 8
                            let rightCenterX = endX - 8
                            let distLeft = abs(startTouchX - leftCenterX)
                            let distRight = abs(startTouchX - rightCenterX)

                            if frameW >= 48 {
                                if distLeft <= 24 {
                                    activeDragTarget = .leftHandle
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } else if distRight <= 24 {
                                    activeDragTarget = .rightHandle
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } else if startTouchX >= startX && startTouchX <= endX {
                                    activeDragTarget = .middleFrame
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } else {
                                    // Тап вне рамки: мягко смещаем окно клипа к точке касания
                                    activeDragTarget = .middleFrame
                                    let clipLen = dragInitialEnd - dragInitialStart
                                    let touchSec = win.start + (Double(startTouchX / totalW) * win.span)
                                    var newStart = max(0.0, touchSec - clipLen / 2.0)
                                    var newEnd = newStart + clipLen
                                    if newEnd > totalMovieDuration {
                                        newEnd = totalMovieDuration
                                        newStart = max(0.0, newEnd - clipLen)
                                    }
                                    localStartTime = newStart
                                    localEndTime = newEnd
                                    dragInitialStart = newStart
                                    dragInitialEnd = newEnd
                                    throttledSeek(to: newStart)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            } else {
                                if distLeft < distRight {
                                    activeDragTarget = .leftHandle
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } else {
                                    activeDragTarget = .rightHandle
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                        }

                        let deltaX = touchX - dragInitialTouchX
                        let deltaSec = Double(deltaX / totalW) * win.span
                        let maxLimit = totalMovieDuration

                        switch activeDragTarget {
                        case .leftHandle:
                            let minStart = 0.0
                            let maxStart = dragInitialEnd - 3.0 // минимум 3 секунды клип
                            let newStart = max(minStart, min(maxStart, dragInitialStart + deltaSec))
                            localStartTime = newStart
                            throttledSeek(to: newStart)

                        case .rightHandle:
                            let minEnd = dragInitialStart + 3.0 // минимум 3 секунды клип
                            let maxEnd = min(maxLimit, dragInitialStart + 90.0) // максимум 90 секунд
                            let newEnd = min(maxEnd, max(minEnd, dragInitialEnd + deltaSec))
                            localEndTime = newEnd
                            throttledSeek(to: max(dragInitialStart, newEnd - 1.0))

                        case .middleFrame:
                            let clipLength = dragInitialEnd - dragInitialStart
                            var newStart = max(0.0, dragInitialStart + deltaSec)
                            var newEnd = newStart + clipLength
                            if newEnd > maxLimit {
                                newEnd = maxLimit
                                newStart = max(0.0, newEnd - clipLength)
                            }
                            localStartTime = newStart
                            localEndTime = newEnd
                            throttledSeek(to: newStart)

                        case .none:
                            break
                        }
                    }
                    .onEnded { _ in
                        activeDragTarget = .none
                        isDragging = false
                        vm.isUserSeeking = false

                        // Фиксируем выбранный отрезок в PlayerViewModel
                        vm.clipStartTime = localStartTime
                        vm.clipEndTime = localEndTime
                        vm.seekClip(to: localStartTime)

                        UISelectionFeedbackGenerator().selectionChanged()

                        // Мягко центрируем окно сцены при завершении перетягивания
                        if !isFullMovieScale {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                adjustSceneWindow(toInclude: localStartTime, end: localEndTime)
                            }
                        }
                    }
            )
        }
    }

    // MARK: - Handle Timecodes Row (Бейджи времени плавно следуют за ручками при драге)

    private var handleTimecodesRow: some View {
        GeometryReader { proxy in
            let totalW = max(100.0, proxy.size.width)
            let win = currentWindow

            let startFrac = max(0.0, min(1.0, (localStartTime - win.start) / win.span))
            let endFrac = max(startFrac, min(1.0, (localEndTime - win.start) / win.span))

            let startX = startFrac * totalW
            let endX = max(startX + 36.0, endFrac * totalW)

            ZStack(alignment: .leading) {
                // Бейдж начала клипа (под левой ручкой)
                Text(formatTimecode(localStartTime))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(trimmerAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .offset(x: max(0, min(totalW - 65, startX - 16)))

                // Бейдж конца клипа (под правой ручкой)
                Text(formatTimecode(localEndTime))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(trimmerAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .offset(x: max(0, min(totalW - 65, endX - 26)))
            }
        }
        .frame(height: 20)
    }

    // MARK: - Timeline Footer Row (Границы окна + Кнопка «Сцена / Весь фильм»)

    private var timelineFooterRow: some View {
        HStack {
            let win = currentWindow

            // Время начала видимого окна
            Text(formatTimecode(win.start))
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
            Text(formatTimecode(win.end))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Scale & Scene Window

    private func adjustSceneWindow(toInclude start: Double, end: Double) {
        let span = min(sceneSpan, totalMovieDuration)
        let clipCenter = (start + end) / 2.0
        let idealStart = clipCenter - span / 2.0
        let maxStart = max(0.0, totalMovieDuration - span)
        sceneWindowStart = max(0.0, min(maxStart, idealStart))
    }

    private func toggleScaleMode() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isFullMovieScale.toggle()
            if !isFullMovieScale {
                adjustSceneWindow(toInclude: localStartTime, end: localEndTime)
            }
        }
    }

    private func throttledSeek(to seconds: Double) {
        let now = CACurrentMediaTime()
        guard now - lastSeekTime >= 0.08 else { return }
        lastSeekTime = now
        vm.seekClipFast(to: seconds)
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
