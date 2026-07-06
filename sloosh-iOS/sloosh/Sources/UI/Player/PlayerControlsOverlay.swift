import SwiftUI

struct PlayerControlsOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel
    let title: String
    let onClose: () -> Void
    let onSettings: () -> Void
    
    // For double tap to seek visualization
    @State private var showSeekForward = false
    @State private var showSeekBackward = false
    
    var body: some View {
        ZStack {
            // Interactive background to show/hide controls
            Color.black.opacity(0.001)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if viewModel.showControls {
                            viewModel.showControls = false
                        } else {
                            viewModel.resetControlsTimer()
                        }
                    }
                }
            
            // Double Tap Zones
            HStack(spacing: 0) {
                // Seek Backward Zone
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        viewModel.seekBy(-10)
                        withAnimation(.easeOut(duration: 0.5)) {
                            showSeekBackward = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showSeekBackward = false
                        }
                    }
                
                // Seek Forward Zone
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        viewModel.seekBy(10)
                        withAnimation(.easeOut(duration: 0.5)) {
                            showSeekForward = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showSeekForward = false
                        }
                    }
            }
            
            // Double Tap Visual Indicators
            HStack {
                if showSeekBackward {
                    SeekIndicator(isForward: false)
                        .padding(.leading, 50)
                }
                Spacer()
                if showSeekForward {
                    SeekIndicator(isForward: true)
                        .padding(.trailing, 50)
                }
            }
            
            if viewModel.showControls {
                VStack {
                    // Top Bar
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.leading, 8)
                        
                        Spacer()
                        
                        if viewModel.pipController != nil {
                            Button(action: {
                                if viewModel.isPiPActive {
                                    viewModel.pipController?.stopPictureInPicture()
                                } else {
                                    viewModel.pipController?.startPictureInPicture()
                                }
                            }) {
                                Image(systemName: viewModel.isPiPActive ? "pip.exit" : "pip.enter")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                        }
                        
                        AirPlayButton()
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                            .padding(.trailing, 8)
                        
                        Button(action: onSettings) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    Spacer()
                    
                    // Center Play/Pause
                    if viewModel.isBuffering || viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                    } else {
                        Button(action: {
                            viewModel.togglePlayPause()
                        }) {
                            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                                .padding(24)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                    
                    Spacer()
                    
                    // Bottom Bar
                    HStack {
                        Text(formatTime(viewModel.currentTime))
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                        
                        Slider(
                            value: Binding(
                                get: { viewModel.currentTime },
                                set: { newValue in
                                    viewModel.seek(to: newValue)
                                }
                            ),
                            in: 0...(viewModel.duration > 0 ? viewModel.duration : 1)
                        )
                        .tint(.white)
                        
                        Text(formatTime(viewModel.duration))
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40)
                }
                .background(Color.black.opacity(0.3).ignoresSafeArea())
                .transition(.opacity)
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.isNaN ? 0 : seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}

struct SeekIndicator: View {
    let isForward: Bool
    
    var body: some View {
        VStack {
            Image(systemName: isForward ? "goforward.10" : "gobackward.10")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(20)
        .background(Color.black.opacity(0.5))
        .clipShape(Circle())
        .transition(.scale.combined(with: .opacity))
    }
}
