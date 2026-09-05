import SwiftUI
import UIKit

private enum AppTab: Hashable {
    case home
    case search
    case messenger
    case continueWatching
    case profile
}

struct ContentView: View {
    @AppStorage("tabBarShowsLabels") private var tabBarShowsLabels = false
    @State private var selectedTab: AppTab = .home
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    @ObservedObject private var authRepo = AuthRepository.shared
    @State private var loadedAvatarImage: UIImage? = {
        if let source = AuthRepository.shared.currentUser?.photoURL, !source.isEmpty {
            return AvatarImageProcessor.decodeImage(from: source)
        }
        return nil
    }()

    @ViewBuilder
    private func tabLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        if tabBarShowsLabels {
            Label(title, systemImage: systemImage)
        } else {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
    }

    @ViewBuilder
    private func profileTabLabel() -> some View {
        if authRepo.isAuthenticated, let user = authRepo.currentUser {
            let avatar = renderCircularAvatar(
                from: loadedAvatarImage,
                initials: user.avatarInitials,
                isSelected: selectedTab == .profile
            )
            if tabBarShowsLabels {
                Label {
                    Text("Профиль")
                } icon: {
                    Image(uiImage: avatar)
                        .renderingMode(.original)
                }
            } else {
                Label {
                    Text("Профиль")
                } icon: {
                    Image(uiImage: avatar)
                        .renderingMode(.original)
                }
                .labelStyle(.iconOnly)
            }
        } else {
            tabLabel("Профиль", systemImage: "person.fill")
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                TabView(selection: $selectedTab) {
                    Tab(value: .home) {
                        HomeView()
                    } label: {
                        tabLabel("Главная", systemImage: "house.fill")
                    }
                    Tab(value: .search, role: .search) {
                        SearchView()
                    } label: {
                        tabLabel("Поиск", systemImage: "magnifyingglass")
                    }
                    Tab(value: .messenger) {
                        MessengerView()
                    } label: {
                        tabLabel("Чаты", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    Tab(value: .continueWatching) {
                        ContinueView()
                    } label: {
                        tabLabel("Продолжить", systemImage: "clock.arrow.circlepath")
                    }
                    Tab(value: .profile) {
                        ProfileView()
                    } label: {
                        profileTabLabel()
                    }
                }
                .id("\(tabBarShowsLabels)_\(authRepo.isAuthenticated)")
                .tabViewStyle(.tabBarOnly)
                .tabBarMinimizeBehavior(.onScrollDown)
                .tint(Color.slooshAccent)
                
                if UIDevice.current.userInterfaceIdiom == .phone && proxy.safeAreaInsets.top > 20 {
                    // Telegram DeviceMetrics thresholds:
                    // Dynamic Island (iPhone 14 Pro/Max, 15, 16): statusBarHeight >= 54pt
                    // Standard Notch (iPhone X, XS, 11, 12, 13, 14): statusBarHeight >= 44pt
                    let isDynamicIsland = proxy.safeAreaInsets.top >= 54
                    let topPadding: CGFloat = isDynamicIsland ? 11.5 : (proxy.safeAreaInsets.top >= 44 ? 5.5 : 2.0)
                    let logoHeight: CGFloat = isDynamicIsland ? 11.0 : 12.0
                    let hPadding: CGFloat = isDynamicIsland ? 14.0 : 16.0

                    Image("LogoText")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.black)
                        .frame(height: logoHeight)
                        .padding(.horizontal, hPadding)
                        .padding(.vertical, 5)
                        .background {
                            Capsule()
                                .fill(
                                    EllipticalGradient(
                                        stops: [
                                            .init(color: .white, location: 0.0),
                                            .init(color: Color.slooshAccent, location: 0.75)
                                        ],
                                        center: .center
                                    )
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, topPadding)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
            .withToasts()
            .task {
                CloudSyncService.shared.syncAllData()
            }
            .task(id: authRepo.currentUser?.photoURL) {
                await loadAvatarImage()
            }
            .onChange(of: authRepo.isAuthenticated) { _, isAuth in
                if !isAuth {
                    loadedAvatarImage = nil
                } else {
                    Task {
                        await loadAvatarImage()
                    }
                }
            }
            .onChange(of: authRepo.currentUser?.id) { _, _ in
                Task {
                    await loadAvatarImage()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlooshIntentPlayMovie"))) { notification in
                selectedTab = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlooshIntentContinueWatching"))) { notification in
                selectedTab = .continueWatching
            }
            .onChange(of: deepLinkManager.targetMovieId) { _, newValue in
                if newValue != nil {
                    selectedTab = .home
                }
            }
        }
    }

    // MARK: - Avatar Helpers

    private func renderCircularAvatar(
        from image: UIImage?,
        initials: String,
        isSelected: Bool,
        size: CGFloat = 28
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)

        return renderer.image { ctx in
            let cgContext = ctx.cgContext
            let bounds = CGRect(x: 0, y: 0, width: size, height: size)
            let traits = UITraitCollection.current
            let accent = UIColor.slooshAccent.resolvedColor(with: traits)

            // Inner avatar circle frame
            let avatarInset: CGFloat = 2.25
            let avatarRect = bounds.insetBy(dx: avatarInset, dy: avatarInset)

            if let img = image {
                cgContext.saveGState()
                let clipPath = UIBezierPath(ovalIn: avatarRect)
                clipPath.addClip()

                let imgSize = img.size
                if imgSize.width > 0 && imgSize.height > 0 {
                    let scale = max(avatarRect.width / imgSize.width, avatarRect.height / imgSize.height)
                    let drawWidth = imgSize.width * scale
                    let drawHeight = imgSize.height * scale
                    let drawRect = CGRect(
                        x: avatarRect.midX - drawWidth / 2.0,
                        y: avatarRect.midY - drawHeight / 2.0,
                        width: drawWidth,
                        height: drawHeight
                    )
                    img.draw(in: drawRect, blendMode: .normal, alpha: isSelected ? 1.0 : 0.75)
                }
                cgContext.restoreGState()
            } else {
                let fallbackBg = isSelected
                    ? accent
                    : (traits.userInterfaceStyle == .dark ? UIColor(white: 0.25, alpha: 1.0) : UIColor(white: 0.85, alpha: 1.0))
                let textColor = isSelected
                    ? UIColor.black
                    : (traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black)

                fallbackBg.setFill()
                UIBezierPath(ovalIn: avatarRect).fill()

                let cleanInitials = initials.trimmingCharacters(in: .whitespacesAndNewlines)
                let textToDraw = cleanInitials.isEmpty ? "S" : String(cleanInitials.prefix(1)).uppercased()

                let fontSize: CGFloat = max(9, avatarRect.width * 0.46)
                let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .center

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]

                let textSize = (textToDraw as NSString).size(withAttributes: attributes)
                let textRect = CGRect(
                    x: avatarRect.origin.x + (avatarRect.width - textSize.width) / 2.0,
                    y: avatarRect.origin.y + (avatarRect.height - textSize.height) / 2.0,
                    width: textSize.width,
                    height: textSize.height
                )
                (textToDraw as NSString).draw(in: textRect, withAttributes: attributes)
            }

            // Outer Ring / Border
            if isSelected {
                let ringRect = bounds.insetBy(dx: 0.75, dy: 0.75)
                let ringPath = UIBezierPath(ovalIn: ringRect)
                ringPath.lineWidth = 1.5
                accent.setStroke()
                ringPath.stroke()
            } else {
                let borderPath = UIBezierPath(ovalIn: avatarRect)
                borderPath.lineWidth = 0.8
                let borderColor = traits.userInterfaceStyle == .dark
                    ? UIColor(white: 1.0, alpha: 0.3)
                    : UIColor(white: 0.0, alpha: 0.2)
                borderColor.setStroke()
                borderPath.stroke()
            }
        }
    }

    @MainActor
    private func loadAvatarImage() async {
        guard authRepo.isAuthenticated, let user = authRepo.currentUser else {
            loadedAvatarImage = nil
            return
        }

        guard let source = user.photoURL, !source.isEmpty else {
            loadedAvatarImage = nil
            return
        }

        // 1. Base64 or cached image
        if let decoded = AvatarImageProcessor.decodeImage(from: source) {
            loadedAvatarImage = decoded
            return
        }

        // 2. Remote HTTP/HTTPS URL
        if source.starts(with: "http"), let url = URL(string: source) {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
            if let cachedResponse = URLCache.shared.cachedResponse(for: request),
               let cachedImg = UIImage(data: cachedResponse.data) {
                ImageCache.shared.insertImage(cachedImg, forKey: source)
                loadedAvatarImage = cachedImg
                return
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
                   let downloadedImg = UIImage(data: data) {
                    URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
                    ImageCache.shared.insertImage(downloadedImg, forKey: source)
                    loadedAvatarImage = downloadedImg
                }
            } catch {
                // Ignore network failure, fallback will remain visible
            }
        }
    }
}
