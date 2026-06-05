import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                TabView {
                    Tab("Главная", systemImage: "house.fill") {
                        HomeView()
                    }
                    Tab("Поиск", systemImage: "magnifyingglass", role: .search) {
                        SearchView()
                    }
                    Tab("Избранное", systemImage: "heart.fill") {
                        FavoritesView()
                    }
                    Tab("Загрузки", systemImage: "arrow.down.circle.fill") {
                        DownloadsView()
                    }
                    Tab("Настройки", systemImage: "gearshape.fill") {
                        SettingsView()
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                .tabBarMinimizeBehavior(.onScrollDown)
                .tint(Color.slooshAccent)
                
                if UIDevice.current.userInterfaceIdiom == .phone && proxy.safeAreaInsets.top > 20 {
                    Image("LogoText")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 12)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(
                                    RadialGradient(
                                        colors: [.white, Color(red: 182/255, green: 255/255, blue: 12/255)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 40
                                    )
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, proxy.safeAreaInsets.top > 50 ? 11 : 5)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
