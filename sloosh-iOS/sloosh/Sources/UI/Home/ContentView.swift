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
        .tint(Color(UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.70, green: 1.0, blue: 0.0, alpha: 1.0) // #B3FF00 for Dark
            } else {
                return UIColor(red: 0.45, green: 0.80, blue: 0.0, alpha: 1.0) // Darker green for Light
            }
        }))
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
