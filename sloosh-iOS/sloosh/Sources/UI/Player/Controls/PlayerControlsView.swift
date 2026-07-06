import SwiftUI

// MARK: - Полный слой контролов плеера

struct PlayerControlsView: View {
    @ObservedObject var vm: PlayerViewModel
    let onDismiss: () -> Void

    @State private var showVoiceoverSheet = false
    @State private var showQualitySheet = false
    @State private var showSpeedSheet = false
    @State private var showSubtitleSheet = false

    var body: some View {
        ZStack {
            // Лёгкое затемнение фона, когда контролы видны
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                // ── Верхняя панель ──────────────────────────────
                TopBarView(vm: vm, onDismiss: onDismiss)

                Spacer()

                // ── Центральные кнопки ──────────────────────────
                CenterControlsView(vm: vm)

                Spacer()

                // ── Нижний блок: правые кнопки + seek bar ───────
                VStack(alignment: .trailing, spacing: 8) {
                    HStack {
                        Spacer()
                        BottomRowView(
                            vm: vm,
                            showVoiceoverSheet: $showVoiceoverSheet,
                            showQualitySheet: $showQualitySheet,
                            showSpeedSheet: $showSpeedSheet,
                            showSubtitleSheet: $showSubtitleSheet
                        )
                        .padding(.trailing, 16)
                    }

                    SeekBarView(vm: vm)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
            }
        }
        // Sheets
        .sheet(isPresented: $showVoiceoverSheet) {
            VoiceoverPickerSheet(vm: vm)
        }
        .sheet(isPresented: $showQualitySheet) {
            QualityPickerSheet(vm: vm)
        }
        .sheet(isPresented: $showSpeedSheet) {
            SpeedPickerSheet(vm: vm)
        }
        .sheet(isPresented: $showSubtitleSheet) {
            SubtitlePickerSheet(vm: vm)
        }
    }
}
