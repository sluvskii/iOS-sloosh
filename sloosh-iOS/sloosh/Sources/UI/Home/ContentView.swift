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

    @ViewBuilder
    private func tabLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        if tabBarShowsLabels {
            Label(title, systemImage: systemImage)
        } else {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
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
                        tabLabel("Профиль", systemImage: "person.fill")
                    }
                }
                .id(tabBarShowsLabels)
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlooshIntentPlayMovie"))) { notification in
                selectedTab = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlooshIntentContinueWatching"))) { notification in
                selectedTab = .continueWatching
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlooshOpenGenreSearch"))) { _ in
                selectedTab = .search
            }
            .onChange(of: deepLinkManager.targetMovieId) { _, newValue in
                if newValue != nil {
                    selectedTab = .home
                }
            }
        }
    }
}
