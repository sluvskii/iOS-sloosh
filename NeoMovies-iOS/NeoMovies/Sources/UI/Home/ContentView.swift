import SwiftUI
import UIKit

struct ContentView: View {
    init() {
        // Modern iOS 26 transparent TabBar styling with Liquid Glass
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        
        // Emulate iOS 26 "Clear" theme and refraction
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundEffect = blurEffect
        
        // Add a subtle border to match the glassmorphism look
        appearance.shadowColor = UIColor.separator.withAlphaComponent(0.3)
        
        // Update item appearances for the "Clear" theme
        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = UIColor.secondaryLabel
        itemAppearance.selected.iconColor = UIColor.systemBlue
        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    
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
        .tint(.blue)
    }
}
