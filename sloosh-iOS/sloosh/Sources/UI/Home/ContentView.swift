import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                TabView {
                    Tab {
                        HomeView()
                    } label: {
                        Label("Главная", systemImage: "house.fill")
                            .labelStyle(.iconOnly)
                    }
                    Tab(role: .search) {
                        SearchView()
                    } label: {
                        Label("Поиск", systemImage: "magnifyingglass")
                            .labelStyle(.iconOnly)
                    }
                    Tab {
                        DownloadsView()
                    } label: {
                        Label("Загрузки", systemImage: "arrow.down.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    Tab {
                        ContinueView()
                    } label: {
                        Label("Продолжить", systemImage: "clock.arrow.circlepath")
                            .labelStyle(.iconOnly)
                    }
                    Tab {
                        ProfileView()
                    } label: {
                        Label("Профиль", systemImage: "person.fill")
                            .labelStyle(.iconOnly)
                    }
                }
                .tabViewStyle(.tabBarOnly)
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
        }
    }
}
