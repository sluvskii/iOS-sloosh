import SwiftUI
import UIKit

// MARK: - Authentic Telegram 1-in-1 Context Menu Overlay (UIKit + Liquid Glass)

struct TelegramMessageContextView: View {
    let message: ChatMessage
    let isFromMe: Bool
    let bubbleFrame: CGRect              // фрейм бабла в точных window-координатах
    let screenSize: CGSize
    let safeAreaInsets: EdgeInsets
    let onDismiss: () -> Void
    let onReact: (String) -> Void
    let onReply: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var appeared = false

    private let emojis = ["❤️", "👍", "🔥", "😂", "😢", "👏"]

    private var myCurrentReaction: String? {
        guard let myId = AuthRepository.shared.currentUser?.id else { return nil }
        return message.reactions?[myId]
    }

    // MARK: - Geometry & Placement Math

    private var reactionPillWidth: CGFloat { CGFloat(emojis.count) * 48 + 12 }
    private var reactionPillHeight: CGFloat { 52 }

    private var menuWidth: CGFloat { 240 }
    private var menuHeight: CGFloat {
        let canEdit = isFromMe && message.type == .text
        return canEdit ? 148 : 98
    }

    // X реакций — по центру бабла с clamp
    private var reactionBarX: CGFloat {
        let half = reactionPillWidth / 2
        return bubbleFrame.midX.clamped(to: half + 16 ... screenSize.width - half - 16)
    }

    // Y реакций — строго над баблом
    private var reactionBarY: CGFloat {
        let desired = bubbleFrame.minY - 10 - (reactionPillHeight / 2)
        let minY = safeAreaInsets.top + (reactionPillHeight / 2) + 8
        return max(minY, desired)
    }

    // X меню — по правому краю для моих, по левому для чужих
    private var menuX: CGFloat {
        let half = menuWidth / 2
        if isFromMe {
            let ideal = bubbleFrame.maxX - half
            return ideal.clamped(to: half + 16 ... screenSize.width - half - 16)
        } else {
            let ideal = bubbleFrame.minX + half
            return ideal.clamped(to: half + 16 ... screenSize.width - half - 16)
        }
    }

    // Y меню — под баблом (или над, если мало места снизу)
    private var menuY: CGFloat {
        let spaceBelow = screenSize.height - safeAreaInsets.bottom - bubbleFrame.maxY
        if spaceBelow >= menuHeight + 16 {
            return bubbleFrame.maxY + 10 + (menuHeight / 2)
        } else {
            return bubbleFrame.minY - 10 - (menuHeight / 2)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. Затемнение экрана Telegram с размытием (закрывается при тапе)
            Color.black
                .opacity(appeared ? 0.45 : 0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .animation(.easeOut(duration: 0.2), value: appeared)

            // 2. Горизонтальная плашка реакций над баблом (Liquid Glass)
            reactionPill
                .position(x: reactionBarX, y: reactionBarY)
                .scaleEffect(appeared ? 1 : 0.4, anchor: .bottom)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.30, dampingFraction: 0.72).delay(0.02), value: appeared)

            // 3. Меню действий под баблом (Liquid Glass)
            actionsMenu
                .position(x: menuX, y: menuY)
                .scaleEffect(
                    appeared ? 1 : 0.4,
                    anchor: isFromMe ? .topTrailing : .topLeading
                )
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.28, dampingFraction: 0.72).delay(0.04), value: appeared)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .ignoresSafeArea()
        .onAppear {
            withAnimation { appeared = true }
        }
    }

    // MARK: - Reaction Pill (Liquid Glass)

    private var reactionPill: some View {
        HStack(spacing: 2) {
            ForEach(Array(emojis.enumerated()), id: \.offset) { _, emoji in
                reactionButton(emoji: emoji)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular.interactive(), in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
    }

    private func reactionButton(emoji: String) -> some View {
        let isSelected = myCurrentReaction == emoji
        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onReact(emoji)
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.slooshAccent.opacity(0.32))
                        .frame(width: 40, height: 40)
                }
                Text(emoji)
                    .font(.system(size: 24))
                    .scaleEffect(isSelected ? 1.15 : 1.0)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(EmojiPressStyle())
    }

    // MARK: - Actions Menu (Liquid Glass)

    private var actionsMenu: some View {
        VStack(spacing: 0) {
            menuRow(
                title: "Ответить",
                icon: "arrowshape.turn.up.left.fill",
                color: .primary,
                action: onReply
            )

            if isFromMe && message.type == .text {
                Divider().padding(.horizontal, 12)
                menuRow(
                    title: "Редактировать",
                    icon: "pencil",
                    color: .primary,
                    action: onEdit
                )
            }

            Divider().padding(.horizontal, 12)

            menuRow(
                title: "Удалить у всех",
                icon: "trash.fill",
                color: .red,
                action: onDelete
            )
        }
        .frame(width: menuWidth)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 7)
    }

    private func menuRow(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowPressStyle())
    }
}

// MARK: - Button Styles

private struct EmojiPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct MenuRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.white.opacity(0.12) : Color.clear)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - ContextMenuCoordinator (UIKit presenter)

@MainActor
final class ContextMenuCoordinator: ObservableObject {
    private var overlayWindow: UIWindow?

    func present(
        message: ChatMessage,
        isFromMe: Bool,
        bubbleFrame: CGRect,
        onDismiss: @escaping () -> Void,
        onReact: @escaping (String) -> Void,
        onReply: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        dismiss(animated: false)

        let screen = windowScene.screen.bounds
        let safeInsets = windowScene.windows.first?.safeAreaInsets ?? .zero
        let swiftUISafe = EdgeInsets(
            top: safeInsets.top,
            leading: safeInsets.left,
            bottom: safeInsets.bottom,
            trailing: safeInsets.right
        )

        let dismissAction: () -> Void = { [weak self] in
            Task { @MainActor in
                onDismiss()
                self?.dismiss(animated: true)
            }
        }

        let rootView = TelegramMessageContextView(
            message: message,
            isFromMe: isFromMe,
            bubbleFrame: bubbleFrame,
            screenSize: screen.size,
            safeAreaInsets: swiftUISafe,
            onDismiss: dismissAction,
            onReact: { emoji in onReact(emoji); dismissAction() },
            onReply:  { onReply();  dismissAction() },
            onEdit:   { onEdit();   dismissAction() },
            onDelete: { onDelete(); dismissAction() }
        )

        let vc = UIHostingController(rootView: rootView)
        vc.view.backgroundColor = .clear
        vc.additionalSafeAreaInsets = UIEdgeInsets(
            top: -safeInsets.top,
            left: -safeInsets.left,
            bottom: -safeInsets.bottom,
            right: -safeInsets.right
        )

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = vc
        window.frame = screen
        window.isHidden = false

        self.overlayWindow = window
    }

    func dismiss(animated: Bool) {
        guard let w = overlayWindow else { return }
        overlayWindow = nil
        if animated {
            UIView.animate(withDuration: 0.18, animations: { w.alpha = 0 }) { _ in
                w.isHidden = true
            }
        } else {
            w.isHidden = true
        }
    }
}
