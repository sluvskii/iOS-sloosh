import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Главная", systemImage: "house.fill")
                }
            SearchView()
                .tabItem {
                    Label("Поиск", systemImage: "magnifyingglass")
                }
            FavoritesView()
                .tabItem {
                    Label("Избранное", systemImage: "heart.fill")
                }
            DownloadsView()
                .tabItem {
                    Label("Загрузки", systemImage: "arrow.down.circle.fill")
                }
            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gearshape.fill")
                }
        }
        // Native iOS 26 TabBar styling applied via SwiftUI modifiers available in newer SDKs
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .tint(.blue)
    }
}
