import AVKit
import UIKit

final class CollapsNativePlayerViewController: AVPlayerViewController, UIGestureRecognizerDelegate, UIAdaptivePresentationControllerDelegate {
    var onWillDisappearCallback: (() -> Void)?
    var onCloseTapped: (() -> Void)?
    var onPlayPauseTapped: (() -> Void)?
    var onSeekRelative: ((Double) -> Void)?
    var onSliderSeek: ((Double) -> Void)?
    var onAudioTapped: ((UIView) -> Void)?
    var onQualityTapped: ((UIView) -> Void)?
    var onPreviousEpisodeTapped: (() -> Void)?
    var onNextEpisodeTapped: (() -> Void)?

    private let dimTop = CAGradientLayer()
    private let dimBottom = CAGradientLayer()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let rewindButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let currentTimeLabel = UILabel()
    private let durationLabel = UILabel()
    private let progressSlider = UISlider()
    private let audioChip = UIButton(type: .system)
    private let qualityChip = UIButton(type: .system)
    private let previousEpisodeChip = UIButton(type: .system)
    private let nextEpisodeChip = UIButton(type: .system)
    private var chromeViews: [UIView] = []
    private var chromeVisible = true
    private var hideWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildOverlay()
        scheduleChromeHide()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dimTop.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 150)
        dimBottom.frame = CGRect(x: 0, y: view.bounds.height - 220, width: view.bounds.width, height: 220)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        presentationController?.delegate = self
        forceToLandscape()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onCloseTapped?()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        onWillDisappearCallback?()
        restoreToPortrait()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }

    override var shouldAutorotate: Bool {
        return true
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }

    private func forceToLandscape() {
        if #available(iOS 16.0, *) {
            guard let windowScene = view.window?.windowScene else { return }
            let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: [.landscapeRight, .landscapeLeft])
            windowScene.requestGeometryUpdate(prefs) { _ in }
            setNeedsUpdateOfSupportedInterfaceOrientations()
            return
        }
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }

    private func restoreToPortrait() {
        if #available(iOS 16.0, *) {
            guard let windowScene = view.window?.windowScene else { return }
            let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: [.portrait])
            windowScene.requestGeometryUpdate(prefs) { _ in }
            return
        }
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }

    @MainActor
    func updateOverlay(
        title: String,
        subtitle: String,
        isPlaying: Bool,
        currentTime: Double,
        duration: Double,
        audioLabel: String,
        qualityLabel: String,
        canGoPreviousEpisode: Bool,
        canGoNextEpisode: Bool
    ) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        playPauseButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"), for: .normal)
        currentTimeLabel.text = formatTime(currentTime)
        durationLabel.text = formatTime(duration)
        progressSlider.minimumValue = 0
        progressSlider.maximumValue = Float(max(duration, 0.1))
        progressSlider.value = Float(currentTime)
        audioChip.setTitle("  \(audioLabel)  ", for: .normal)
        qualityChip.setTitle("  \(qualityLabel)  ", for: .normal)
        previousEpisodeChip.isHidden = !canGoPreviousEpisode
        nextEpisodeChip.isHidden = !canGoNextEpisode
        if isPlaying {
            scheduleChromeHide()
        }
    }

    private func buildOverlay() {
        guard let overlay = contentOverlayView else { return }
        overlay.layer.addSublayer(dimTop)
        overlay.layer.addSublayer(dimBottom)
        dimTop.colors = [UIColor.black.withAlphaComponent(0.72).cgColor, UIColor.clear.cgColor]
        dimBottom.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.75).cgColor]

        overlay.isUserInteractionEnabled = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)

        closeButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        closeButton.layer.cornerRadius = 24
        closeButton.addAction(UIAction { [weak self] _ in
            self?.registerInteraction()
            self?.onCloseTapped?()
        }, for: .touchUpInside)

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textAlignment = .center
        subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.75)
        subtitleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        subtitleLabel.textAlignment = .center

        configureCircleButton(rewindButton, symbol: "gobackward.10", size: 52)
        rewindButton.addAction(UIAction { [weak self] _ in
            self?.registerInteraction()
            self?.onSeekRelative?(-10)
        }, for: .touchUpInside)
        configureCircleButton(playPauseButton, symbol: "pause.fill", size: 84)
        playPauseButton.addAction(UIAction { [weak self] _ in
            self?.registerInteraction()
            self?.onPlayPauseTapped?()
        }, for: .touchUpInside)
        configureCircleButton(forwardButton, symbol: "goforward.10", size: 52)
        forwardButton.addAction(UIAction { [weak self] _ in
            self?.registerInteraction()
            self?.onSeekRelative?(10)
        }, for: .touchUpInside)

        currentTimeLabel.textColor = .white
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        durationLabel.textColor = .white
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .medium)
        durationLabel.textAlignment = .right

        progressSlider.minimumTrackTintColor = .white
        progressSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.22)
        progressSlider.addAction(UIAction { [weak self] _ in
            self?.registerInteraction()
            self?.onSliderSeek?(Double(self?.progressSlider.value ?? 0))
        }, for: .valueChanged)

        configureChip(audioChip, icon: "speaker.wave.2.fill")
        audioChip.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.registerInteraction()
            self.onAudioTapped?(self.audioChip)
        }, for: .touchUpInside)

        configureChip(qualityChip, icon: "slider.horizontal.3")
        qualityChip.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.registerInteraction()
            self.onQualityTapped?(self.qualityChip)
        }, for: .touchUpInside)

        configureChip(previousEpisodeChip, icon: "backward.end.fill")
        previousEpisodeChip.addAction(UIAction { [weak self] _ in
            self?.registerInteraction()
            self?.onPreviousEpisodeTapped?()
        }, for: .touchUpInside)

        configureChip(nextEpisodeChip, icon: "forward.end.fill")
        nextEpisodeChip.addAction(UIAction { [weak self] _ in
            self?.registerInteraction()
            self?.onNextEpisodeTapped?()
        }, for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        header.axis = .vertical
        header.spacing = 2

        let center = UIStackView(arrangedSubviews: [previousEpisodeChip, rewindButton, playPauseButton, forwardButton, nextEpisodeChip])
        center.axis = .horizontal
        center.alignment = .center
        center.spacing = 16

        let times = UIStackView(arrangedSubviews: [currentTimeLabel, progressSlider, durationLabel])
        times.axis = .horizontal
        times.alignment = .center
        times.spacing = 14

        let chips = UIStackView(arrangedSubviews: [audioChip, qualityChip])
        chips.axis = .horizontal
        chips.spacing = 10
        chips.alignment = .center
        chips.distribution = .fillProportionally

        [closeButton, header, center, times, chips].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview($0)
        }
        chromeViews = [closeButton, header, center, times, chips]

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 28),
            closeButton.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 28),
            closeButton.widthAnchor.constraint(equalToConstant: 48),
            closeButton.heightAnchor.constraint(equalToConstant: 48),

            header.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            header.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 28),

            center.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            center.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: 10),

            times.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 24),
            times.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -24),
            times.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -74),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 90),
            durationLabel.widthAnchor.constraint(equalToConstant: 90),

            chips.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            chips.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -26)
        ])
    }

    private func configureCircleButton(_ button: UIButton, symbol: String, size: CGFloat) {
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.layer.cornerRadius = size / 2
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size)
        ])
    }

    private func configureChip(_ button: UIButton, icon: String) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: icon)
        config.imagePadding = 8
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        button.configuration = config
        button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        button.layer.cornerRadius = 24
    }

    private func formatTime(_ sec: Double) -> String {
        guard sec.isFinite else { return "0:00" }
        let total = Int(max(0, sec))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func registerInteraction() {
        showChrome()
        scheduleChromeHide()
    }

    private func showChrome() {
        guard !chromeVisible else { return }
        chromeVisible = true
        UIView.animate(withDuration: 0.2) {
            self.chromeViews.forEach { $0.alpha = 1 }
            self.dimTop.opacity = 1
            self.dimBottom.opacity = 1
        }
    }

    private func hideChrome() {
        guard chromeVisible else { return }
        chromeVisible = false
        UIView.animate(withDuration: 0.2) {
            self.chromeViews.forEach { $0.alpha = 0 }
            self.dimTop.opacity = 0
            self.dimBottom.opacity = 0
        }
    }

    private func scheduleChromeHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hideChrome()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    @objc
    private func toggleChrome() {
        if chromeVisible {
            hideWorkItem?.cancel()
            hideChrome()
        } else {
            showChrome()
            scheduleChromeHide()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIControl)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
