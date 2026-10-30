import SwiftUI
import UIKit

// MARK: - Telegram Glass Platter Item Model

public struct TelegramGlassPlatterItem: Identifiable {
    public let id: String
    public let systemName: String?
    public let title: String?
    public let badgeCount: Int?
    public let tintColor: Color?
    public let action: () -> Void
    public let onLongPress: (() -> Void)?

    public init(
        id: String,
        systemName: String? = nil,
        title: String? = nil,
        badgeCount: Int? = nil,
        tintColor: Color? = nil,
        action: @escaping () -> Void,
        onLongPress: (() -> Void)? = nil
    ) {
        self.id = id
        self.systemName = systemName
        self.title = title
        self.badgeCount = badgeCount
        self.tintColor = tintColor
        self.action = action
        self.onLongPress = onLongPress
    }
}

// MARK: - Telegram Glass Platter (iOS 27 / Telegram Style)

/// Стеклянная капсула (Platter) в стиле Telegram / iOS 27:
/// объединяет одну или несколько кнопок в единую монолитную Liquid Glass форму.
/// Если кнопка одна — получается идеальный круг 44x44 pt.
/// Если кнопок несколько — они бесшовно «слипаются» в единую капсулу с мягким разделителем,
/// независимым откликом на нажатие и плавной пружинной интерполяцией ширины при изменении состава кнопок.
public struct TelegramGlassPlatter: View {
    private let items: [TelegramGlassPlatterItem]
    private let showsDividers: Bool

    public init(items: [TelegramGlassPlatterItem], showsDividers: Bool = true) {
        self.items = items
        self.showsDividers = showsDividers
    }

    public init(
        id: String = "single",
        systemName: String? = nil,
        title: String? = nil,
        badgeCount: Int? = nil,
        tintColor: Color? = nil,
        action: @escaping () -> Void,
        onLongPress: (() -> Void)? = nil
    ) {
        self.items = [
            TelegramGlassPlatterItem(
                id: id,
                systemName: systemName,
                title: title,
                badgeCount: badgeCount,
                tintColor: tintColor,
                action: action,
                onLongPress: onLongPress
            )
        ]
        self.showsDividers = false
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 && showsDividers {
                    // Тонкий мягкий разделитель между кнопками внутри капсулы
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1, height: 20)
                        .transition(.opacity)
                }

                PlatterItemButton(
                    item: item,
                    isSingleIcon: items.count == 1 && item.title == nil
                )
            }
        }
        .frame(height: 44)
        .background {
            Capsule()
                .fill(Color.clear)
        }
        .clipShape(Capsule())
        .glassEffect(.regular.interactive(), in: Capsule())
        // Фирменная пружина Telegram из NavigationBarPlatterTransitionView (Spring response 0.416, damping 0.75)
        .animation(.spring(response: 0.416, dampingFraction: 0.75), value: items.map { $0.id })
    }
}

// MARK: - Platter Item Button

private struct PlatterItemButton: View {
    let item: TelegramGlassPlatterItem
    var isSingleIcon: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            item.action()
        } label: {
            ZStack(alignment: .topTrailing) {
                if let systemName = item.systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(effectiveTintColor)
                        .glassForeground(isEnabled: GlassForegroundAppearance.shouldBlend(tint: item.tintColor))
                        .frame(width: isSingleIcon ? 44 : 42, height: 44)
                } else if let title = item.title {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(effectiveTintColor)
                        .glassForeground(isEnabled: GlassForegroundAppearance.shouldBlend(tint: item.tintColor))
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                }

                // Бейдж счетчика (если есть)
                if let count = item.badgeCount, count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(height: 16)
                        .frame(minWidth: 16)
                        .background(Capsule().fill(Color.red))
                        .offset(x: -2, y: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlatterPressButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                if let onLongPress = item.onLongPress {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLongPress()
                }
            }
        )
        .accessibilityLabel(item.title ?? item.systemName ?? "Кнопка")
    }

    private var effectiveTintColor: Color {
        if let tint = item.tintColor {
            return tint
        }
        return colorScheme == .dark ? .white : .primary
    }
}

// MARK: - Platter Press Button Style (Telegram Instant Touch Tracking)

/// Точный стиль нажатия Telegram:
/// Мгновенный отклик при касании (scale 0.92, alpha 0.55),
/// плавная пружинная анимация возврата при отпускании пальца.
public struct PlatterPressButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.55 : 1.0)
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.08)
                    : .spring(response: 0.35, dampingFraction: 0.65),
                value: configuration.isPressed
            )
    }
}

// MARK: - Generic View-based Platter Container

/// Контейнер для произвольных view (например, аватара и иконки),
/// упаковывающий их в единую монолитную капсулу Liquid Glass.
public struct TelegramGlassCustomPlatter<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 0) {
            content
        }
        .frame(height: 44)
        .clipShape(Capsule())
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}

// MARK: - Matched Geometry Optional Helper

extension View {
    @ViewBuilder
    public func matchedGeometryIfPresent(id: AnyHashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
