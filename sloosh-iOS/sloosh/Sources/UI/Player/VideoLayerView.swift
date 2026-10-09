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

extension PlayerLayerView: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        if UIApplication.shared.applicationState == .background {
            stashedPlayer = playerLayer.player
            playerLayer.player = nil
        }
    }
}

// MARK: - SwiftUI обёртка

struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer?
    @Binding var pipController: AVPictureInPictureController?
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = videoGravity
        view.playerLayer.player = player

        // PiP
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let pip = AVPictureInPictureController(playerLayer: view.playerLayer)
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
            pip?.delegate = view
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

// MARK: - Ambient Live Blurred Video Layer

final class AmbientPlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("AmbientPlayerLayerView: expected AVPlayerLayer")
        }
        return layer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    private let blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .dark)
        let v = UIVisualEffectView(effect: blur)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return v
    }()

    private let dimOverlay: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return v
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspectFill
        addSubview(blurView)
        addSubview(dimOverlay)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspectFill
        addSubview(blurView)
        addSubview(dimOverlay)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        blurView.frame = bounds
        dimOverlay.frame = bounds
    }
}

struct AmbientVideoLayerView: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> AmbientPlayerLayerView {
        let view = AmbientPlayerLayerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: AmbientPlayerLayerView, context: Context) {
        if uiView.player !== player {
            uiView.player = player
        }
    }
}
