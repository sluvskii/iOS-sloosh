import SwiftUI
import UIKit

/// Премиальный экран запуска (Splash Screen) в стиле iOS 26+ Liquid Glass:
/// - Полная адаптация под Темную и Светлую темы без мерцаний
/// - Гарантированная видимость с первого кадра (opacity: 1.0)
/// - Атмосферный неоновый ореол фирменного цвета slooshAccent
/// - Векторный логотип `LogoText` с адаптивной глубиной и мягкой тенью
/// - Световой блик (shimmer), плавно скользящий по буквам логотипа
/// - Аккуратная версия приложения внизу экрана (как в настройках)
/// - Тактильный отклик (haptic feedback)
/// - Мягкое растворение при переходе к контенту приложения
struct LaunchSplashView: View {
    @Binding var isPresented: Bool
    
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @Environment(\.colorScheme) private var systemColorScheme
    
    @State private var logoScale: CGFloat = 0.92
    @State private var glowScale: CGFloat = 0.85
    @State private var glowOpacity: Double = 0.65
    @State private var shimmerOffset: CGFloat = -260
    @State private var contentOpacity: Double = 1.0
    @State private var versionOpacity: Double = 0.0
    
    private var isDark: Bool {
        switch appTheme {
        case .light:
            return false
        case .dark:
            return true
        case .system:
            return systemColorScheme == .dark
        }
    }
    
    private var backgroundColor: Color {
        isDark ? Color.black : Color(uiColor: .systemBackground)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Версия \(version) (\(build))"
    }

    var body: some View {
        ZStack {
            // Адаптивный фон под текущую тему (без мерцаний и скачков)
            backgroundColor
                .ignoresSafeArea()
            
            // Атмосферное неоновое свечение фирменного акцентного цвета
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.slooshAccent.opacity(isDark ? 0.40 : 0.28),
                            Color.slooshAccent.opacity(isDark ? 0.15 : 0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: isDark ? 180 : 160
                    )
                )
                .frame(width: 320, height: 320)
                .scaleEffect(glowScale)
                .opacity(glowOpacity)
                .blur(radius: isDark ? 40 : 32)
            
            // Центральный векторный логотип со скользящим световым лучом
            ZStack {
                // Базовый логотип в фирменном акцентном цвете
                Image("LogoText")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color.slooshAccent)
                    .frame(maxWidth: 240, maxHeight: 64)
                    .shadow(
                        color: Color.slooshAccent.opacity(isDark ? 0.50 : 0.28),
                        radius: isDark ? 18 : 10,
                        x: 0,
                        y: isDark ? 0 : 3
                    )
                
                // Бегущий луч света (Shimmer beam) по контуру букв
                Image("LogoText")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.white)
                    .frame(maxWidth: 240, maxHeight: 64)
                    .mask {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .white.opacity(isDark ? 0.95 : 0.85), location: 0.5),
                                        .init(color: .clear, location: 1.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 100, height: 80)
                            .offset(x: shimmerOffset)
                    }
            }
            .scaleEffect(logoScale)
            
            // Аккуратная версия приложения снизу экрана (как в настройках)
            VStack {
                Spacer()
                Text(appVersion)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(isDark ? Color.white.opacity(0.38) : Color.black.opacity(0.35))
                    .padding(.bottom, 28)
            }
            .opacity(versionOpacity)
        }
        .opacity(contentOpacity)
        .ignoresSafeArea()
        .onAppear {
            runAnimationSequence()
        }
    }
    
    private func runAnimationSequence() {
        // Фаза 1: Нежное пружинное раскрытие логотипа, сияния и версии
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            logoScale = 1.0
            glowScale = 1.15
            glowOpacity = isDark ? 0.85 : 0.75
            versionOpacity = 1.0
        }
        
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            generator.impactOccurred()
        }
        
        // Фаза 2: Скольжение светового луча по логотипу
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeInOut(duration: 0.85)) {
                shimmerOffset = 260
            }
        }
        
        // Фаза 3: Плавное растворение экрана заставки и переход в приложение
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            withAnimation(.easeInOut(duration: 0.4)) {
                logoScale = 1.08
                glowOpacity = 0.0
                contentOpacity = 0.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                isPresented = false
            }
        }
    }
}
