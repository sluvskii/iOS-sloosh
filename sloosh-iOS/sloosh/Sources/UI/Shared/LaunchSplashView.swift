import SwiftUI
import UIKit

/// Премиальный экран запуска (Splash Screen) в стиле iOS 26+ Liquid Glass:
/// - Темный фон с глубоким неоновым свечением slooshAccent
/// - Векторный логотип `LogoText` с пружинной анимацией появления
/// - Световой блик (shimmer), скользящий по буквам логотипа
/// - Тактильный отклик (haptic feedback)
/// - Мягкое растворение при переходе к контенту приложения
struct LaunchSplashView: View {
    @Binding var isPresented: Bool
    
    @State private var logoOpacity: Double = 0.0
    @State private var logoScale: CGFloat = 0.82
    @State private var glowOpacity: Double = 0.0
    @State private var glowScale: CGFloat = 0.6
    @State private var shimmerOffset: CGFloat = -240
    @State private var backgroundOpacity: Double = 1.0
    
    @State private var dismissTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            // Глубокий темный фон
            Color.black
                .ignoresSafeArea()
            
            // Атмосферное радиальное свечение фирменного акцентного цвета
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.slooshAccent.opacity(0.35),
                            Color.slooshAccent.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 170
                    )
                )
                .frame(width: 320, height: 320)
                .scaleEffect(glowScale)
                .opacity(glowOpacity)
                .blur(radius: 45)
            
            // Центральный векторный логотип с эффектом скользящего блика
            ZStack {
                // Базовый акцентный логотип
                if UIImage(named: "LogoText") != nil {
                    Image("LogoText")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color.slooshAccent)
                        .frame(maxWidth: 240, maxHeight: 62)
                } else {
                    Text("sloosh")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(Color.slooshAccent)
                }
                
                // Бегущий луч света (Shimmer beam) по контуру букв
                if UIImage(named: "LogoText") != nil {
                    Image("LogoText")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(.white)
                        .frame(maxWidth: 240, maxHeight: 62)
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
                                .frame(width: 90, height: 80)
                                .offset(x: shimmerOffset)
                        }
                }
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
        }
        .opacity(backgroundOpacity)
        .contentShape(Rectangle())
        .onTapGesture {
            finishEarly()
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Фаза 1: Пружинный вход логотипа и раскрытие ореола
        withAnimation(.spring(response: 0.55, dampingFraction: 0.72, blendDuration: 0.2)) {
            logoScale = 1.0
            logoOpacity = 1.0
            glowScale = 1.1
            glowOpacity = 0.85
        }
        
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            generator.impactOccurred()
        }
        
        // Фаза 2: Скольжение светового блика
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeInOut(duration: 0.65)) {
                shimmerOffset = 240
            }
        }
        
        // Фаза 3: Плавное растворение и раскрытие приложения
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 850_000_000) // 0.85 сек удержания
            if Task.isCancelled { return }
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) {
                    logoScale = 1.08
                    glowOpacity = 0.0
                    backgroundOpacity = 0.0
                }
            }
            
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            
            await MainActor.run {
                isPresented = false
            }
        }
    }
    
    private func finishEarly() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            backgroundOpacity = 0.0
            logoScale = 1.06
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}
