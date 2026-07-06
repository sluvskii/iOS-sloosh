import SwiftUI
import AVFoundation
import AVKit

// MARK: - UIView с AVPlayerLayer как backing layer

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

// MARK: - SwiftUI обёртка

struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer?
    @Binding var pipController: AVPictureInPictureController?
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = videoGravity
        view.playerLayer.player = player

        // PiP
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(playerLayer: view.playerLayer)
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
            DispatchQueue.main.async {
                pipController = pip
            }
        }

        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.player !== player {
            uiView.player = player
        }
        if uiView.playerLayer.videoGravity != videoGravity {
            uiView.playerLayer.videoGravity = videoGravity
        }
    }
}
