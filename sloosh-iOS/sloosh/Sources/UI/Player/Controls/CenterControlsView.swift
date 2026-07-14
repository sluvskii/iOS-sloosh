import SwiftUI

// MARK: - Центральные кнопки: -10с / Play-Pause / +10с
// GlassEffectContainer объединяет все три кнопки в одну жидкую стеклянную поверхность

struct CenterControlsView: View {
    @ObservedObject var vm: PlayerViewModel
    @Namespace private var glassNS
    @State private var seekBackwardFlash = false
    @State private var seekForwardFlash = false

    var body: some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 24) {
                
                if !vm.isMovie {
                    // Previous Episode
                    Button {
                        vm.playPreviousEpisode()
                        flash($seekBackwardFlash)
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .blendMode(.plusLighter)
                            .frame(width: 56, height: 56)
                            .scaleEffect(seekBackwardFlash ? 0.82 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: seekBackwardFlash)
                            .opacity(vm.hasPreviousEpisode ? 1.0 : 0.4)
                    }
                    .disabled(!vm.hasPreviousEpisode)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("backward", in: glassNS)
                }

                // Play / Pause
                Button {
                    vm.togglePlayPause()
                } label: {
                    Group {
                        if vm.isLoading || vm.isBuffering {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white.opacity(0.85))
                                .blendMode(.plusLighter)
                                .scaleEffect(1.6)
                        } else {
                            Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .blendMode(.plusLighter)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: 72, height: 72)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("playPause", in: glassNS)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: vm.isPlaying)

                if !vm.isMovie {
                    // Next Episode
                    Button {
                        vm.playNextEpisode()
                        flash($seekForwardFlash)
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .blendMode(.plusLighter)
                            .frame(width: 56, height: 56)
                            .scaleEffect(seekForwardFlash ? 0.82 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: seekForwardFlash)
                            .opacity(vm.hasNextEpisode ? 1.0 : 0.4)
                    }
                    .disabled(!vm.hasNextEpisode)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("forward", in: glassNS)
                }
                
            }
        }
    }

    private func flash(_ flag: Binding<Bool>) {
        flag.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { flag.wrappedValue = false }
    }
}
