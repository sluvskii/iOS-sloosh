import SwiftUI
import UIKit
import AVFoundation

// MARK: - Apple Gallery Style Video Trimmer (Галерейная обрезка момента)
// Вдохновлено нативным видеоредактором Apple Photos / Галереи iOS:
// 1. Иконическая желтая рамка обрезки с тактильными ручками захвата.
// 2. Единый, плавный координатор жестов без конфликтов и скачков.
// 3. Свободная перемотка и навигация по всему фильму (мини-бар + детальная дорожка).
// 4. Ноль визуального шума — никаких лишних кнопок, чипов и громоздких блоков.
// 5. Зацикленное воспроизведение выбранного фрагмента на уже запущенном AVPlayer.

struct PlayerClipTrimmerView: View {
    @ObservedObject var vm: PlayerViewModel

    // Режим активного перетаскивания
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

    // Окно сцены детальной дорожки (по умолчанию 3 минуты вокруг клипа)
    @State private var sceneCenterTime: Double = 0.0
    private let sceneWindowSpan: Double = 180.0 // 3 минуты обзора

    // Иконический желтый цвет обрезки Apple Photos
    private let appleYellow = Color(red: 1.0, green: 0.83, blue: 0.04)
    private let sampleTags = ["#эпик", "#цитата", "#момент", "#шедевр", "#смешно", "#мурашки"]

    var body: some View {
        ZStack {
            // 1. Мягкие кинематографичные виньетки сверху и снизу
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.85), Color.black.opacity(0.4), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .ignoresSafeArea()

                Spacer()

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.4), Color.black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)

            // 2. Центральная область экрана: тап ставит на паузу / запускает видео
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
                            .frame(width: 72, height: 72)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .shadow(color: .black.opacity(0.4), radius: 10)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

            // 3. Основной интерфейс: Верхняя шапка + Нижняя галерейная обрезка
            VStack(spacing: 0) {
                // Шапка (Отмена • Длительность • Опубликовать)
                topBar
                    .padding(.top, 12)
                    .padding(.horizontal, 20)

                Spacer()

                // Галерейный пульт обрезки
                galleryTrimmerSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }

            // 4. Окно публикации (при нажатии «Опубликовать»)
            if vm.showClipPublishOverlay {
                publishOverlay
                    .zIndex(10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onAppear {
            syncSceneCenter()
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.isPlaying)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.showClipPublishOverlay)
    }

    // MARK: - Top Bar (Как в галерее iOS)

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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()

            // Бейдж длительности клипа по центру (например: 0:30)
            HStack(spacing: 6) {
                Text(formattedDurationOnly(vm.clipEndTime - vm.clipStartTime))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                Text("•")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))

                Text(vm.fallbackTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: .capsule)

            Spacer()

            // Кнопка «Опубликовать» (яркая, нативная)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    vm.showClipPublishOverlay = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Опубликовать")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color.white)
                .clipShape(Capsule())
                .shadow(color: Color.white.opacity(0.2), radius: 8)
            }
            .buttonStyle(.glassPress)
        }
    }

    // MARK: - Gallery Trimmer Section

    private var galleryTrimmerSection: some View {
        VStack(spacing: 8) {
            // 1. Мини-полоса всего фильма (для мгновенного перехода в любую сцену)
            if vm.currentDuration > sceneWindowSpan {
                fullMovieMiniNavigator
                    .frame(height: 14)
            }

            // 2. Основная галерейная дорожка с желтой рамкой Apple Photos
            galleryFilmstripTrack
                .frame(height: 54)

            // 3. Подписи таймкодов начала и конца клипа
            HStack {
                Text(formatTimecode(vm.clipStartTime))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                Text(formatTimecode(vm.clipEndTime))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 6)
        }
    }

    // MARK: - Full Movie Mini Navigator (Обзор всего 2-часового фильма)

    private var fullMovieMiniNavigator: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let dur = max(1.0, vm.currentDuration)
            let (wStart, wEnd) = currentSceneWindow()
            let span = max(1.0, wEnd - wStart)

            let winX = max(0.0, min(w, (wStart / dur) * w))
            let winW = max(24.0, min(w - winX, (span / dur) * w))

            let playheadX = max(0.0, min(w - 2.0, (vm.currentTime / dur) * w))

            ZStack(alignment: .leading) {
                // Фон полосы
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: 4)

                // Окошко текущего участка фильма
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.35))
                    .frame(width: winW, height: 8)
                    .offset(x: winX)

                // Точка текущей секунды
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .offset(x: max(0, min(w - 8, playheadX - 4)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let progress = max(0.0, min(1.0, val.location.x / w))
                        let targetSec = progress * dur
                        jumpToTime(targetSec)
                    }
            )
        }
    }

    // MARK: - Gallery Filmstrip Track (Иконическая желтая рамка Apple Photos)

    private var galleryFilmstripTrack: some View {
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

            // Координата бегунка воспроизведения
            let playNorm = max(0.0, min(1.0, (vm.currentTime - wStart) / span))
            let playX = max(0.0, min(totalW - 2.0, playNorm * totalW))

            ZStack(alignment: .leading) {
                // 1. Фоновая подложка дорожки с легкими насечками кадров
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.65))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Засечки кадров киноленты
                HStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { _ in
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.09))
                            .frame(width: 1, height: 18)
                    }
                    Spacer()
                }

                // 2. Затемнение слева от рамки
                if startX > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.55))
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
                        .fill(Color.black.opacity(0.55))
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

                // 4. ЖЕЛТАЯ РАМКА ОБРЕЗКИ APPLE PHOTOS
                ZStack {
                    // Верхняя и нижняя соединительные перекладины
                    VStack {
                        Rectangle()
                            .fill(appleYellow)
                            .frame(height: 3)
                        Spacer()
                        Rectangle()
                            .fill(appleYellow)
                            .frame(height: 3)
                    }

                    // Левая ручка (Начало клипа)
                    HStack {
                        ZStack {
                            UnevenRoundedRectangle(
                                topLeadingRadius: 8,
                                bottomLeadingRadius: 8,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 0
                            )
                            .fill(appleYellow)
                            .frame(width: 16)

                            // Ребра захвата (как в iOS)
                            VStack(spacing: 3) {
                                Capsule().fill(Color.black.opacity(0.75)).frame(width: 2.2, height: 14)
                            }
                        }

                        Spacer()

                        // Правая ручка (Конец клипа)
                        ZStack {
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 8,
                                topTrailingRadius: 8
                            )
                            .fill(appleYellow)
                            .frame(width: 16)

                            // Ребра захвата (как в iOS)
                            VStack(spacing: 3) {
                                Capsule().fill(Color.black.opacity(0.75)).frame(width: 2.2, height: 14)
                            }
                        }
                    }
                }
                .frame(width: frameW)
                .offset(x: startX)

                // 5. Белый бегунок воспроизведения (Playhead)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2.5, height: 54)
                    .shadow(color: .black.opacity(0.7), radius: 3)
                    .offset(x: playX)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            // ЕДИНЫЙ, НАДЕЖНЫЙ КООРДИНАТОР ЖЕСТОВ БЕЗ КОНФЛИКТОВ
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
                    }
            )
        }
    }

    // MARK: - Scene Window Helpers

    private func currentSceneWindow() -> (Double, Double) {
        let center = sceneCenterTime > 0 ? sceneCenterTime : ((vm.clipStartTime + vm.clipEndTime) / 2.0)
        let maxLimit = vm.currentDuration > 0 ? vm.currentDuration : (center + sceneWindowSpan)
        let half = sceneWindowSpan / 2.0
        var wStart = max(0.0, center - half)
        var wEnd = min(maxLimit, wStart + sceneWindowSpan)

        // Всегда держим рамку клипа внутри окна обзора
        if wStart > vm.clipStartTime {
            wStart = max(0.0, vm.clipStartTime - 10.0)
            wEnd = min(maxLimit, wStart + sceneWindowSpan)
        }
        if wEnd < vm.clipEndTime {
            wEnd = min(maxLimit, vm.clipEndTime + 10.0)
            wStart = max(0.0, wEnd - sceneWindowSpan)
        }

        return (wStart, max(wStart + 10.0, wEnd))
    }

    private func syncSceneCenter() {
        sceneCenterTime = (vm.clipStartTime + vm.clipEndTime) / 2.0
    }

    private func jumpToTime(_ seconds: Double) {
        sceneCenterTime = seconds
        let currentLen = vm.clipEndTime - vm.clipStartTime
        let maxLimit = vm.currentDuration > 0 ? vm.currentDuration : (seconds + 300)
        let newStart = max(0.0, min(maxLimit - currentLen, seconds - currentLen / 2.0))
        let newEnd = min(maxLimit, newStart + currentLen)

        vm.clipStartTime = newStart
        vm.clipEndTime = newEnd
        vm.seekClip(to: newStart)
    }

    // MARK: - Publish Overlay

    private var publishOverlay: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        vm.showClipPublishOverlay = false
                    }
                }

            VStack(spacing: 14) {
                // Заголовок
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Опубликовать момент")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)

                        Text("\(vm.fallbackTitle) • \(formattedDurationOnly(vm.clipEndTime - vm.clipStartTime))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        withAnimation {
                            vm.showClipPublishOverlay = false
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }

                // Поле ввода подписи
                TextField("Добавьте цитату или подпись к моменту...", text: $vm.clipCaption, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .lineLimit(2...3)
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Быстрые теги
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sampleTags, id: \.self) { tag in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                if !vm.clipCaption.contains(tag) {
                                    vm.clipCaption = vm.clipCaption.isEmpty ? tag : "\(vm.clipCaption) \(tag)"
                                }
                            } label: {
                                Text(tag)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let error = vm.clipPublishErrorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Кнопки действий
                HStack(spacing: 12) {
                    Button {
                        withAnimation {
                            vm.showClipPublishOverlay = false
                        }
                    } label: {
                        Text("Назад к обрезке")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.glassPress)

                    Button {
                        publishClipAction()
                    } label: {
                        HStack(spacing: 6) {
                            if vm.isClipPublishing {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: "sparkles.tv.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Опубликовать ✨")
                                    .font(.system(size: 14, weight: .bold))
                            }
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .shadow(color: Color.white.opacity(0.25), radius: 8)
                    }
                    .buttonStyle(.glassPress)
                    .disabled(vm.isClipPublishing)
                }
                .padding(.top, 4)
            }
            .padding(18)
            .frame(maxWidth: 480)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.75))
            )
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 30)
            .padding(.horizontal, 24)
        }
    }

    private func publishClipAction() {
        guard !vm.isClipPublishing else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                try await vm.publishClip()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastManager.shared.show(title: "Момент опубликован в ленту! ✨", icon: "sparkles.tv.fill", iconColor: Color.slooshAccent)
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                withAnimation {
                    vm.clipPublishErrorMessage = "Не удалось опубликовать момент. Проверьте интернет."
                }
            }
        }
    }

    // MARK: - Formatters

    private func formattedDurationOnly(_ dur: Double) -> String {
        let total = Int(round(max(1.0, dur)))
        let m = total / 60
        let s = total % 60
        if m > 0 {
            return s > 0 ? "\(m) мин \(s) сек" : "\(m) мин"
        }
        return "\(s) сек"
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
