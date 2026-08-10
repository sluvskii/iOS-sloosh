import SwiftUI
import UIKit


// MARK: - Основной оверлей (SwiftUI поверх UIKit window)

/// Правильный Telegram-style оверлей:
/// - Размытый backdrop на весь экран
/// - Сообщение анимировано переносится на своё место
/// - Реакции — горизонтальная пилюля СТРОГО над сообщением
/// - Меню действий — СТРОГО под сообщением (или над, если нет места)
struct TelegramMessageContextView: View {
    let message: ChatMessage
    let isFromMe: Bool
    let bubbleFrame: CGRect              // фрейм бабла в глобальных (window) координатах
    let screenSize: CGSize
    let safeAreaInsets: EdgeInsets
    let allMessages: [ChatMessage]
    let onDismiss: () -> Void
    let onReact: (String) -> Void
    let onReply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var appeared = false

    private var myCurrentReaction: String? {
        guard let myId = AuthRepository.shared.currentUser?.id else { return nil }
        return message.reactions?[myId]
    }

    private let emojis = ["❤️", "👍", "🔥", "😂", "😢", "👏"]

    // Реакции показываем ВСЕГДА над баблом, но если нет места — снизу
    private var reactionBarY: CGFloat {
        let reactionBarHeight: CGFloat = 52
        let gap: CGFloat = 8
        let topLimit = safeAreaInsets.top + 8
        let idealY = bubbleFrame.minY - gap - reactionBarHeight / 2

        if idealY - reactionBarHeight / 2 < topLimit {
            // Нет места над — показываем под сообщением
            return bubbleFrame.maxY + gap + reactionBarHeight / 2
        }
        return max(topLimit + reactionBarHeight / 2, idealY)
    }

    // Реакции выровнены по краю бабла (как в Telegram)
    private var reactionBarX: CGFloat {
        let barWidth: CGFloat = 52 * CGFloat(emojis.count)
        let margin: CGFloat = 16
        if isFromMe {
            // Исходящие — выровнять по правому краю
            return min(screenSize.width - margin - barWidth / 2, max(barWidth / 2 + margin, bubbleFrame.maxX - barWidth / 2))
        } else {
            // Входящие — выровнять по левому краю
            return max(barWidth / 2 + margin, min(screenSize.width - margin - barWidth / 2, bubbleFrame.minX + barWidth / 2))
        }
    }

    private var menuWidth: CGFloat { min(250, screenSize.width - 32) }
    private var menuItemCount: Int { (isFromMe && message.type == .text) ? 3 : 2 }
    private var menuHeight: CGFloat { CGFloat(menuItemCount) * 50 + CGFloat(menuItemCount - 1) * 0.5 }

    // Меню под баблом, если нет места — над
    private var menuY: CGFloat {
        let gap: CGFloat = 12
        let reactionBarUsed: CGFloat = 52 + 8  // высота плашки реакций + gap
        let spaceBelow = screenSize.height - bubbleFrame.maxY - safeAreaInsets.bottom

        if spaceBelow >= menuHeight + gap + 8 {
            return bubbleFrame.maxY + gap + menuHeight / 2
        } else {
            return bubbleFrame.minY - gap - menuHeight / 2
        }
    }

    private var menuX: CGFloat {
        let margin: CGFloat = 16
        if isFromMe {
            return min(screenSize.width - margin - menuWidth / 2, max(menuWidth / 2 + margin, bubbleFrame.maxX - menuWidth / 2))
        } else {
            return max(menuWidth / 2 + margin, min(screenSize.width - margin - menuWidth / 2, bubbleFrame.minX + menuWidth / 2))
        }
    }

    var body: some View {
        ZStack {
            // 1. Backdrop — тёмный полупрозрачный фон, как в Telegram
            Color.black
                .opacity(appeared ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .animation(.easeOut(duration: 0.2), value: appeared)

            // 2. Плашка реакций — горизонтальная пилюля НАД баблом
            reactionPill
                .position(x: reactionBarX, y: reactionBarY)
                .scaleEffect(appeared ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.32, dampingFraction: 0.72).delay(0.05), value: appeared)

            // 3. Меню действий — вертикальный список ПОД баблом
            actionsMenu
                .position(x: menuX, y: menuY)
                .scaleEffect(appeared ? 1 : 0.5, anchor: isFromMe ? .topTrailing : .topLeading)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.3, dampingFraction: 0.72).delay(0.08), value: appeared)
        }
        .onAppear {
            withAnimation { appeared = true }
        }
    }

    // MARK: - Reaction Pill

    private var reactionPill: some View {
        HStack(spacing: 0) {
            ForEach(Array(emojis.enumerated()), id: \.offset) { idx, emoji in
                let isSelected = (myCurrentReaction == emoji)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onReact(emoji)
                } label: {
                    ZStack {
                        // Подсветка выбранной реакции
                        if isSelected {
                            Circle()
                                .fill(Color.slooshAccent.opacity(0.25))
                                .frame(width: 44, height: 44)
                        }
                        Text(emoji)
                            .font(.system(size: 26))
                            .scaleEffect(isSelected ? 1.1 : 1.0)
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(EmojiPressStyle())
            }
        }
        .padding(.horizontal, 4)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Actions Menu

    private var actionsMenu: some View {
        VStack(spacing: 0) {
            MenuActionRow(
                title: "Ответить",
                systemImage: "arrowshape.turn.up.left",
                color: .primary
            ) { onReply() }

            if isFromMe && message.type == .text {
                Divider()
                    .background(Color.white.opacity(0.1))
                MenuActionRow(
                    title: "Редактировать",
                    systemImage: "pencil",
                    color: .primary
                ) { onEdit() }
            }

            Divider()
                .background(Color.white.opacity(0.1))

            MenuActionRow(
                title: "Удалить",
                systemImage: "trash",
                color: .red
            ) { onDelete() }
        }
        .frame(width: menuWidth)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Supporting Views

private struct MenuActionRow: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(color)
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(color)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowPressStyle())
    }
}

private struct EmojiPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.78 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct MenuRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - ContextOverlayCoordinator (UIKit presenter)

/// Показывает Telegram-style оверлей поверх всего (в window) через UIKit
@MainActor
final class ContextMenuCoordinator: ObservableObject {
    private var overlayWindow: UIWindow?
    private var overlayVC: UIViewController?

    func present(
        message: ChatMessage,
        isFromMe: Bool,
        bubbleFrame: CGRect,
        allMessages: [ChatMessage],
        onReact: @escaping (String) -> Void,
        onReply: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        let screenSize = windowScene.screen.bounds.size
        let safeAreaInsets = windowScene.windows.first?.safeAreaInsets ?? .zero
        let swiftUISafeInsets = EdgeInsets(
            top: safeAreaInsets.top,
            leading: safeAreaInsets.left,
            bottom: safeAreaInsets.bottom,
            trailing: safeAreaInsets.right
        )

        let dismissAction: () -> Void = { [weak self] in
            Task { @MainActor in
                self?.dismiss(animated: true)
            }
        }

        let overlay = TelegramMessageContextView(
            message: message,
            isFromMe: isFromMe,
            bubbleFrame: bubbleFrame,
            screenSize: screenSize,
            safeAreaInsets: swiftUISafeInsets,
            allMessages: allMessages,
            onDismiss: dismissAction,
            onReact: { emoji in
                onReact(emoji)
                dismissAction()
            },
            onReply: {
                onReply()
                dismissAction()
            },
            onEdit: {
                onEdit()
                dismissAction()
            },
            onDelete: {
                onDelete()
                dismissAction()
            }
        )

        let vc = UIHostingController(rootView: overlay)
        vc.view.backgroundColor = .clear

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = vc
        window.isHidden = false

        self.overlayWindow = window
        self.overlayVC = vc
    }

    func dismiss(animated: Bool) {
        let w = overlayWindow
        UIView.animate(withDuration: animated ? 0.18 : 0, animations: {
            w?.alpha = 0
        }, completion: { _ in
            w?.isHidden = true
        })
        self.overlayWindow = nil
        self.overlayVC = nil
    }
}
