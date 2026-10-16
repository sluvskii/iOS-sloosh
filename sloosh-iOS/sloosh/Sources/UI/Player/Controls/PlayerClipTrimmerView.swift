import SwiftUI
import UIKit
import AVFoundation

// MARK: - Native iOS Video Trimmer (Нативная обрезка момента)
// 1. Строго нативный стиль iOS / Apple Photos.
// 2. Никакого визуального шума: нет названий фильмов, нет лишних кнопок и выдуманных тегов.
// 3. Иконическая желтая рамка обрезки с тактильными ручками захвата.
// 4. Плавная навигация и перемотка по дорожке без конфликтов жестов.
// 5. Нативный системный лист публикации (Form + NavigationStack).

struct PlayerClipTrimmerView: View {
    @ObservedObject var vm: PlayerViewModel

    @State private var isShowingPublishSheet: Bool = false

    // Жесты на дорожке
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

    // Окно сцены: 120 секунд вокруг момента (достаточно для точной подгонки)
    private let sceneSpan: Double = 120.0

    var body: some View {
        ZStack {
            // Градиенты сверху и снизу для читаемости
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.8), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 70)
                .ignoresSafeArea()

                Spacer()

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)

            // Центральная область: тап для Play / Pause
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
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(width: 64, height: 64)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

            // Основной интерфейс: Верхняя панель + Нижний нативный триммер
            VStack {
                // Нативная верхняя панель (Отмена / Длительность / Готово)
                nativeTopBar
                    .padding(.top, 14)
                    .padding(.horizontal, 20)

                Spacer()

                // Нативная нижняя дорожка обрезки
                nativeTrimmerBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $isShowingPublishSheet) {
            PublishMomentSheet(vm: vm)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.isPlaying)
    }

    // MARK: - Native Top Bar

    private var nativeTopBar: some View {
        HStack {
            // Отмена
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    vm.exitClipMode()
                }
            } label: {
                Text("Отмена")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)

            Spacer()

            // Длительность по центру (например: 0:30)
            Text(formattedDuration(vm.clipEndTime - vm.clipStartTime))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)

            Spacer()

            // Готово
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isShowingPublishSheet = true
            } label: {
                Text("Готово")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.glassPress)
        }
    }

    // MARK: - Native Trimmer Bar (Apple Photos Yellow Frame)

    private var nativeTrimmerBar: some View {
        GeometryReader { proxy in
            let totalW = max(100.0, proxy.size.width)
            let (wStart, wEnd) = activeWindow()
            let span = max(1.0, wEnd - wStart)

            // Нормализованные координаты
            let startNorm = max(0.0, min(1.0, (vm.clipStartTime - wStart) / span))
            let endNorm = max(startNorm + 0.03, min(1.0, (vm.clipEndTime - wStart) / span))

            let startX = startNorm * totalW
            let endX = endNorm * totalW
            let frameW = max(34.0, endX - startX)

            let playNorm = max(0.0, min(1.0, (vm.currentTime - wStart) / span))
            let playX = max(0.0, min(totalW - 2.5, playNorm * totalW))

            ZStack(alignment: .leading) {
                // 1. Фоновая дорожка
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                // Насечки ленты
                HStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { _ in
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 1, height: 16)
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

                // 4. Жёлтая рамка Apple Photos
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

                    // Левая и правая ручки
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

                // 5. Белый бегунок воспроизведения
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2.5, height: 50)
                    .shadow(color: .black.opacity(0.7), radius: 3)
                    .offset(x: playX)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            // Единый координатор жестов
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
                    }
            )
        }
        .frame(height: 50)
    }

    private func activeWindow() -> (Double, Double) {
        let center = (vm.clipStartTime + vm.clipEndTime) / 2.0
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

    private func formattedDuration(_ dur: Double) -> String {
        let total = Int(round(max(1.0, dur)))
        let m = total / 60
        let s = total % 60
        if m > 0 {
            return String(format: "%d:%02d", m, s)
        }
        return String(format: "0:%02d", s)
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
