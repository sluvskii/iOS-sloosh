import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
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
    }
}
