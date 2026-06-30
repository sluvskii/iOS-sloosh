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
            let isLandscape = proxy.size.width > proxy.size.height
            
            HStack(spacing: 0) {
                if isLandscape {
                    sidebarNavigation
                }
                
                ZStack(alignment: .top) {
                    if isLandscape {
                        Group {
                            switch selectedTab {
                            case .home:
                                HomeView()
                            case .search:
                                SearchView()
                            case .downloads:
                                DownloadsView()
                            case .continueWatching:
                                ContinueView()
                            case .profile:
                                ProfileView()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
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
                    }
                    
                    if !isLandscape && UIDevice.current.userInterfaceIdiom == .phone && proxy.safeAreaInsets.top > 20 {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var sidebarNavigation: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack.fill")
                .font(.system(size: 24))
                .foregroundColor(Color.slooshAccent)
                .padding(.top, 24)
            
            Spacer()
            
            VStack(spacing: 8) {
                sidebarTabButton(tab: .home, icon: "house.fill", title: "Главная")
                sidebarTabButton(tab: .search, icon: "magnifyingglass", title: "Поиск")
                sidebarTabButton(tab: .downloads, icon: "arrow.down.circle.fill", title: "Загрузки")
                sidebarTabButton(tab: .continueWatching, icon: "clock.arrow.circlepath", title: "Продолжить")
                sidebarTabButton(tab: .profile, icon: "person.fill", title: "Профиль")
            }
            
            Spacer()
        }
        .frame(width: 76)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .ignoresSafeArea(edges: .vertical)
    }
    
    private func sidebarTabButton(tab: AppTab, icon: String, title: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? Color.slooshAccent : .secondary)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.slooshAccent.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                if tabBarShowsLabels {
                    Text(title)
                        .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? Color.slooshAccent : .secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
