import SwiftUI
import UIKit

/// Премиальный экран запуска (Splash Screen) в стиле iOS 26+ Liquid Glass:
/// - Гарантированная видимость с первого кадра (opacity: 1.0)
/// - Темный фон с глубоким неоновым ореолом slooshAccent
/// - Векторный логотип `LogoText`
/// - Световой блик (shimmer), плавно скользящий по буквам логотипа
/// - Тактильный отклик (haptic feedback)
/// - Мягкое растворение при переходе к контенту приложения
struct LaunchSplashView: View {
    @Binding var isPresented: Bool
    
    @State private var logoScale: CGFloat = 0.92
    @State private var glowScale: CGFloat = 0.85
    @State private var glowOpacity: Double = 0.65
    @State private var shimmerOffset: CGFloat = -260
    @State private var contentOpacity: Double = 1.0
    
    var body: some View {
        ZStack {
            // Глубокий темный фон на весь экран
            Color.black
                .ignoresSafeArea()
            
            // Атмосферное неоновое свечение фирменного акцентного цвета
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.slooshAccent.opacity(0.40),
                            Color.slooshAccent.opacity(0.15),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 180
                    )
                )
                .frame(width: 320, height: 320)
                .scaleEffect(glowScale)
                .opacity(glowOpacity)
                .blur(radius: 40)
            
            // Центральный векторный логотип со скользящим световым лучом
            ZStack {
                // Базовый логотип в фирменном акцентном цвете
                Image("LogoText")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color.slooshAccent)
                    .frame(maxWidth: 240, maxHeight: 64)
                
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
                                        .init(color: .white.opacity(0.95), location: 0.5),
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
        }
        .opacity(contentOpacity)
        .ignoresSafeArea()
        .onAppear {
            runAnimationSequence()
        }
    }
    
    private func runAnimationSequence() {
        // Фаза 1: Нежное пружинное раскрытие логотипа и сияния
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            logoScale = 1.0
            glowScale = 1.15
            glowOpacity = 0.85
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
