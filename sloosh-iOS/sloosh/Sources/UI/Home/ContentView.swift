import SwiftUI
import UIKit

private enum AppTab: Hashable {
    case home
    case search
    case downloads
    case continueWatching
    case profile
}

struct ContentView: View {
    @AppStorage("tabBarShowsLabels") private var tabBarShowsLabels = false
    @State private var selectedTab: AppTab = .home

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
                    Tab(value: .downloads) {
                        DownloadsView()
                    } label: {
                        tabLabel("Загрузки", systemImage: "arrow.down.circle.fill")
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
                    Image("LogoText")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.black)
                        .frame(height: 12)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(
                                    EllipticalGradient(
                                        stops: [
                                            .init(color: .white, location: 0.0),
                                            .init(color: Color(red: 182/255, green: 255/255, blue: 12/255), location: 0.7)
                                        ],
                                        center: .center
                                    )
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, proxy.safeAreaInsets.top > 50 ? 11 : 5)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
            .withToasts()
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlooshIntentPlayMovie"))) { notification in
                selectedTab = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SlooshIntentContinueWatching"))) { notification in
                selectedTab = .continueWatching
            }
        }
    }
}
