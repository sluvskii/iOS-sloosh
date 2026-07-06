import SwiftUI

// MARK: - Центральные кнопки: -10с / Play-Pause / +10с

struct CenterControlsView: View {
    @ObservedObject var vm: PlayerViewModel
    @Namespace private var glassNS
    @State private var seekBackwardFlash = false
    @State private var seekForwardFlash = false

    var body: some View {
        HStack(spacing: 28) {
            // −10 с
            Button {
                vm.seek(by: -10)
                flashBackward()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 54, height: 54)
                .scaleEffect(seekBackwardFlash ? 0.85 : 1.0)
            }
            .modifier(GlassCircleButton(diameter: 54))

            // Play / Pause (крупнее)
            Button {
                vm.togglePlayPause()
            } label: {
                Group {
                    if vm.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white)
                            // offset play icon visually (right-biased glyph)
                            .offset(x: vm.isPlaying ? 0 : 2)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 68, height: 68)
            }
            .modifier(GlassCircleButton(diameter: 68))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: vm.isPlaying)

            // +10 с
            Button {
                vm.seek(by: 10)
                flashForward()
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .scaleEffect(seekForwardFlash ? 0.85 : 1.0)
            }
            .modifier(GlassCircleButton(diameter: 54))
        }
    }

    private func flashBackward() {
        withAnimation(.easeOut(duration: 0.12)) { seekBackwardFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.3)) { seekBackwardFlash = false }
        }
    }

    private func flashForward() {
        withAnimation(.easeOut(duration: 0.12)) { seekForwardFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.3)) { seekForwardFlash = false }
        }
    }
}

// MARK: - Glass circle button style

struct GlassCircleButton: ViewModifier {
    let diameter: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: diameter, height: diameter)
            .modifier(GlassCircleEffect(diameter: diameter))
    }
}

private struct GlassCircleEffect: ViewModifier {
    let diameter: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.5))
                )
        }
    }
}
