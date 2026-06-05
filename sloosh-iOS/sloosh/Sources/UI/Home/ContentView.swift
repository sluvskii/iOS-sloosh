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
                    ZStack {
                        Image("LogoBg")
                            .resizable()
                            .frame(width: 108, height: 30)
                        Image("LogoText")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 62, height: 15)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: proxy.safeAreaInsets.top, alignment: .center)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                }
            }
        }
    }
}
