import SwiftUI
import AVKit

struct CustomVideoPlayer: UIViewRepresentable {
    @ObservedObject var viewModel: PlayerViewModel
    
    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = viewModel.player
        
        // Setup Picture in Picture
        if AVPictureInPictureController.isPictureInPictureSupported() {
            let pipController = AVPictureInPictureController(playerLayer: view.playerLayer)
            pipController?.delegate = context.coordinator
            viewModel.pipController = pipController
        }
        
        return view
    }
    
    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        if uiView.playerLayer.player !== viewModel.player {
            uiView.playerLayer.player = viewModel.player
        }
        
        // Re-setup PiP if player layer changed its player and pip was lost
        if viewModel.pipController == nil && AVPictureInPictureController.isPictureInPictureSupported() {
            let pipController = AVPictureInPictureController(playerLayer: uiView.playerLayer)
            pipController?.delegate = context.coordinator
            viewModel.pipController = pipController
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    @MainActor
    class Coordinator: NSObject, AVPictureInPictureControllerDelegate {
        var viewModel: PlayerViewModel
        
        init(viewModel: PlayerViewModel) {
            self.viewModel = viewModel
        }
        
        nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            Task { @MainActor in
                viewModel.isPiPActive = true
            }
        }
        
        nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
            Task { @MainActor in
                viewModel.isPiPActive = false
            }
        }
        
        nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            completionHandler(true)
        }
    }
}

class PlayerUIView: UIView {
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
    
    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }
}
