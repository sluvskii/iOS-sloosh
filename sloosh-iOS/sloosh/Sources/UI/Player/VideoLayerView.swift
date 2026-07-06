import SwiftUI
import AVFoundation
import AVKit

// MARK: - UIView с AVPlayerLayer как backing layer

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("PlayerLayerView: expected AVPlayerLayer as backing layer")
        }
        return layer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    private var stashedPlayer: AVPlayer?
    var pipController: AVPictureInPictureController?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupObservers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupObservers()
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func didEnterBackground() {
        if let pip = pipController, pip.isPictureInPictureActive { return }
        stashedPlayer = playerLayer.player
        playerLayer.player = nil
    }

    @objc private func willEnterForeground() {
        guard let stashed = stashedPlayer else { return }
        playerLayer.player = stashed
        stashedPlayer = nil
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
            view.pipController = pip
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
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.35)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            uiView.playerLayer.videoGravity = videoGravity
            CATransaction.commit()
        }
    }
}
