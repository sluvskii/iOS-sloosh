import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        if #available(iOS 18.0, *) {
            TabView {
                Tab("Главная", systemImage: "house.fill") {
                    HomeView()
                }
                Tab("Поиск", systemImage: "magnifyingglass") {
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
            .tint(Color.slooshAccent)
        } else {
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
            .tint(Color.slooshAccent)
        }
    }
}
