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
            Tab("Загрузки", systemImage: "arrow.down.circle.fill") {
                DownloadsView()
            }
            Tab("Продолжить", systemImage: "clock.arrow.circlepath") {
                ContinueView()
            }
            Tab("Профиль", systemImage: "person.fill") {
                ProfileView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Color.slooshAccent)
    }
}
