import SwiftUI
import AVKit

struct PlayerView: View {
    let movieId: String
    let videoUrl: String
    
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .onAppear {
            setupPlayer()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func setupPlayer() {
        // Here we would normally fetch the actual video URL from Alloha/Collaps API
        // For now using a sample HLS stream
        let sampleUrl = URL(string: "http://devimages.apple.com/iphone/samples/bipbop/bipbopall.m3u8")!
        player = AVPlayer(url: sampleUrl)
    }
}
