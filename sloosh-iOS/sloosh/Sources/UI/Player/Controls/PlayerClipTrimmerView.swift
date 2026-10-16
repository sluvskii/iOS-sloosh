import SwiftUI
import UIKit
import AVFoundation

// MARK: - In-Player Cinema Clip Trimmer (Создание момента прямо в плеере)
// 1. Полностью горизонтальный (landscape) кинематографичный интерфейс без переворотов экрана.
// 2. Использует текущее уже загруженное видео из AVPlayer (0 мс ожидания, 0 сетевых перезагрузок).
// 3. Зацикливание выбранного фрагмента [clipStartTime ... clipEndTime].
// 4. Пошаговые тактильные кнопки [-1с] / [+1с] для начала и конца.
// 5. Быстрые пресеты длительности (15с, 30с, 60с, 2 мин).
// 6. Встроенная компактная карточка публикации с тегами и подписью.

struct PlayerClipTrimmerView: View {
    @ObservedObject var vm: PlayerViewModel

    @State private var dragInitialStart: Double? = nil
    @State private var dragInitialEnd: Double? = nil
    @State private var isDragging: Bool = false

    private let sampleTags = ["#эпик", "#цитата", "#момент", "#шедевр", "#смешно", "#мурашки"]

    var body: some View {
        ZStack {
            // 1. Градиентные тени сверху и снизу для читаемости поверх любого кадра
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.85), Color.black.opacity(0.4), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 90)
                .ignoresSafeArea()

                Spacer()

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.5), Color.black.opacity(0.92)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)

            // 2. Центральная область тапа: Play/Pause видео
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    vm.togglePlayPause()
                }
                .overlay {
                    if !vm.isPlaying {
                        Image(systemName: "play.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 80, height: 80)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .shadow(color: .black.opacity(0.4), radius: 12)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

            // 3. Верхняя панель (Header)
            VStack {
                topBar
                    .padding(.top, 10)
                    .padding(.horizontal, 16)

                Spacer()

                // 4. Нижний плавающий пульт обрезки (Cinema Island)
                bottomTrimmerIsland
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            // 5. Карточка публикации (поверх при нажатии «Опубликовать»)
            if vm.showClipPublishOverlay {
                publishOverlay
                    .zIndex(10)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.isPlaying)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.showClipPublishOverlay)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 14) {
            // Кнопка «Отмена»
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    vm.exitClipMode()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                    Text("Отмена")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 38)
            }
            .buttonStyle(.glassPress)
            .glassEffect(.regular.interactive(), in: .capsule)

            Spacer()

            // Центральный бейдж: Название + Создание момента
            HStack(spacing: 8) {
                if let logo = vm.logoUrl, !logo.isEmpty, let url = resolveImageUrl(logo) {
                    AsyncCachedImage(url: url) {
                        Text(vm.fallbackTitle)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 20)
                    } fallback: {
                        Text(vm.fallbackTitle)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    Text(vm.fallbackTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text("•")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))

                HStack(spacing: 5) {
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.slooshAccent)

                    Text("Создание момента")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.slooshAccent)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .glassEffect(.regular, in: .capsule)

            Spacer()

            // Кнопка «Опубликовать»
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    vm.showClipPublishOverlay = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Опубликовать")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(Color.white)
                .clipShape(Capsule())
                .shadow(color: Color.white.opacity(0.2), radius: 8)
            }
            .buttonStyle(.glassPress)
        }
    }

    // MARK: - Bottom Trimmer Island (Островок обрезки)

    private var bottomTrimmerIsland: some View {
        VStack(spacing: 10) {
            // Ряд 1: Время начала, длительность, время конца + кнопки [-1с]/[+1с]
            HStack(alignment: .center) {
                // Блок «Начало»
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("НАЧАЛО")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                        Text(formatSeconds(vm.clipStartTime))
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }

                    HStack(spacing: 4) {
                        nudgeButton(title: "-1с") {
                            vm.nudgeClipStart(by: -1.0)
                        }
                        nudgeButton(title: "+1с") {
                            vm.nudgeClipStart(by: 1.0)
                        }
                    }
                }

                Spacer()

                // Центральная капсула длительности
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.slooshAccent)
                    Text("Длительность: \(formattedClipDuration)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.slooshAccent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.slooshAccent.opacity(0.14))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.slooshAccent.opacity(0.35), lineWidth: 1))

                Spacer()

                // Блок «Конец»
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        nudgeButton(title: "-1с") {
                            vm.nudgeClipEnd(by: -1.0)
                        }
                        nudgeButton(title: "+1с") {
                            vm.nudgeClipEnd(by: 1.0)
                        }
                    }

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("КОНЕЦ")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.55))
                        Text(formatSeconds(vm.clipEndTime))
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.horizontal, 4)

            // Ряд 2: Интерактивный кинематографичный таймлайн
            timelineTrackView
                .frame(height: 48)

            // Ряд 3: Пресеты длительности в 1 касание
            HStack(spacing: 10) {
                Text("Пресет:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))

                presetChip(seconds: 15, label: "15 сек")
                presetChip(seconds: 30, label: "30 сек")
                presetChip(seconds: 60, label: "60 сек")
                presetChip(seconds: 120, label: "2 мин")

                Spacer()

                // Кнопка зацикленного воспроизведения с начала
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    vm.seekClip(to: vm.clipStartTime)
                    if !vm.isPlaying {
                        vm.player?.play()
                        vm.isPlaying = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "repeat")
                            .font(.system(size: 11, weight: .bold))
                        Text("С начала клипа")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Timeline Track View

    private var timelineTrackView: some View {
        GeometryReader { proxy in
            let totalW = max(100.0, proxy.size.width)
            let clipDur = max(1.0, vm.clipEndTime - vm.clipStartTime)

            // Контекстное окно сцены вокруг клипа:
            let margin = max(20.0, clipDur * 0.4)
            let wStart = max(0.0, vm.clipStartTime - margin)
            let maxTotal = vm.currentDuration > 0 ? vm.currentDuration : (vm.clipEndTime + 60.0)
            let wEnd = min(maxTotal, vm.clipEndTime + margin)
            let span = max(15.0, wEnd - wStart)

            let startNorm = max(0.0, min(1.0, (vm.clipStartTime - wStart) / span))
            let endNorm = max(startNorm + 0.05, min(1.0, (vm.clipEndTime - wStart) / span))

            let leftX = startNorm * totalW
            let rightX = endNorm * totalW
            let selW = max(36.0, rightX - leftX)

            let playheadNorm = max(0.0, min(1.0, (vm.currentTime - wStart) / span))
            let playheadX = playheadNorm * totalW

            ZStack(alignment: .leading) {
                // Фон трека
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Деления времени по дорожке
                HStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { _ in
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 1, height: 14)
                    }
                    Spacer()
                }

                // Затемнение вне выбранного фрагмента (левая шторка)
                if leftX > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: leftX)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 10,
                                bottomLeadingRadius: 10,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 0
                            )
                        )
                }

                // Затемнение вне выбранного фрагмента (правая шторка)
                if rightX < totalW {
                    Rectangle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: totalW - rightX)
                        .offset(x: rightX)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 10,
                                topTrailingRadius: 10
                            )
                        )
                }

                // ВЫДЕЛЕННЫЙ ФРАГМЕНТ (Кинематографичная акцентная рамка)
                ZStack {
                    // Полупрозрачный фон клипа (перетаскивание всей сцены целиком)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.slooshAccent.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.slooshAccent, lineWidth: 2.5)
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { val in
                                    if dragInitialStart == nil {
                                        dragInitialStart = vm.clipStartTime
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                    guard let initStart = dragInitialStart else { return }
                                    let deltaSec = Double(val.translation.width / totalW) * span
                                    let currentLength = vm.clipEndTime - vm.clipStartTime
                                    let maxLimit = vm.currentDuration > 0 ? vm.currentDuration : (initStart + 600)
                                    var newS = max(0.0, initStart + deltaSec)
                                    var newE = newS + currentLength
                                    if newE > maxLimit {
                                        newE = maxLimit
                                        newS = max(0.0, newE - currentLength)
                                    }
                                    vm.clipStartTime = newS
                                    vm.clipEndTime = newE
                                    vm.seekClip(to: newS)
                                }
                                .onEnded { _ in
                                    dragInitialStart = nil
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                        )

                    // Левый хэндл (Начало)
                    HStack {
                        ZStack {
                            UnevenRoundedRectangle(
                                topLeadingRadius: 8,
                                bottomLeadingRadius: 8,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 0
                            )
                            .fill(Color.slooshAccent)
                            .frame(width: 22)

                            // Засечки захвата ||
                            VStack(spacing: 3) {
                                Capsule().fill(Color.black.opacity(0.8)).frame(width: 2.5, height: 14)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { val in
                                    if dragInitialStart == nil {
                                        dragInitialStart = vm.clipStartTime
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                    guard let initStart = dragInitialStart else { return }
                                    let deltaSec = Double(val.translation.width / totalW) * span
                                    let newStart = max(0.0, min(vm.clipEndTime - 3.0, initStart + deltaSec))
                                    vm.clipStartTime = newStart
                                    vm.seekClip(to: newStart)
                                }
                                .onEnded { _ in
                                    dragInitialStart = nil
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                        )

                        Spacer()

                        // Правый хэндл (Конец)
                        ZStack {
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 8,
                                topTrailingRadius: 8
                            )
                            .fill(Color.slooshAccent)
                            .frame(width: 22)

                            // Засечки захвата ||
                            VStack(spacing: 3) {
                                Capsule().fill(Color.black.opacity(0.8)).frame(width: 2.5, height: 14)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { val in
                                    if dragInitialEnd == nil {
                                        dragInitialEnd = vm.clipEndTime
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    }
                                    guard let initEnd = dragInitialEnd else { return }
                                    let deltaSec = Double(val.translation.width / totalW) * span
                                    let maxLimit = vm.currentDuration > 0 ? vm.currentDuration : (vm.clipStartTime + 600)
                                    let newEnd = min(maxLimit, max(vm.clipStartTime + 3.0, initEnd + deltaSec))
                                    vm.clipEndTime = newEnd
                                    vm.seekClip(to: max(vm.clipStartTime, newEnd - 1.5))
                                }
                                .onEnded { _ in
                                    dragInitialEnd = nil
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                        )
                    }
                }
                .frame(width: selW)
                .offset(x: leftX)

                // Игла текущей позиции воспроизведения (Playhead needle)
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2.5, height: 48)
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .offset(x: max(0, min(totalW - 2.5, playheadX)))
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Helper UI Components

    private func nudgeButton(title: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 34, height: 26)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func presetChip(seconds: Double, label: String) -> some View {
        let isSelected = abs((vm.clipEndTime - vm.clipStartTime) - seconds) < 1.0

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                vm.setClipDurationPreset(seconds)
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .black : .white.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.slooshAccent : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - In-Player Publish Overlay Modal (Карточка публикации)

    private var publishOverlay: some View {
        ZStack {
            // Размытый полупрозрачный фон
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        vm.showClipPublishOverlay = false
                    }
                }

            // Компактная карточка
            VStack(spacing: 14) {
                // Заголовок карточки
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Опубликовать момент")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)

                        Text("\(vm.fallbackTitle) • \(formattedClipDuration)")
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

                // Поле ввода подписи / цитаты
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

                // Баннер ошибки если есть
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

    // MARK: - Utilities

    private var formattedClipDuration: String {
        let dur = max(1.0, vm.clipEndTime - vm.clipStartTime)
        let total = Int(round(dur))
        let m = total / 60
        let s = total % 60
        if m > 0 {
            return s > 0 ? "\(m) мин \(s) сек" : "\(m) мин"
        }
        return "\(s) сек"
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func resolveImageUrl(_ path: String) -> URL? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        if let normalized = normalizeImageUrl(path: path) {
            return URL(string: normalized)
        }
        return nil
    }
}
