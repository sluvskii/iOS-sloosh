import SwiftUI

// MARK: - Центральные кнопки: -10с / Play-Pause / +10с
// GlassEffectContainer объединяет все три кнопки в одну жидкую стеклянную поверхность

struct CenterControlsView: View {
    @ObservedObject var vm: PlayerViewModel
    @Namespace private var glassNS
    @State private var seekBackwardFlash = false
    @State private var seekForwardFlash = false

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 20) {
                // −10 с
                Button {
                    vm.seek(by: -10)
                    flash($seekBackwardFlash)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .scaleEffect(seekBackwardFlash ? 0.82 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: seekBackwardFlash)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("backward", in: glassNS)

                // Play / Pause
                Button {
                    vm.togglePlayPause()
                } label: {
                    Group {
                        if vm.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: vm.isPlaying ? 0 : 2)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .frame(width: 64, height: 64)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("playPause", in: glassNS)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: vm.isPlaying)

                // +10 с
                Button {
                    vm.seek(by: 10)
                    flash($seekForwardFlash)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .scaleEffect(seekForwardFlash ? 0.82 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: seekForwardFlash)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .glassEffectID("forward", in: glassNS)
            }
        }
    }

    private func flash(_ flag: Binding<Bool>) {
        flag.wrappedValue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { flag.wrappedValue = false }
    }
}
