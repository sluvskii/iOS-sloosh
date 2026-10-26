import SwiftUI
import UIKit

/// Единая кастомная шапка экрана: центрированный заголовок, стеклянная кнопка
/// «назад/закрыть», опциональные trailing-элементы и нижняя строка (табы, поиск).
/// Фон — VariableBlurView, плавно проявляющийся при скролле.
struct SlooshTopBar<Trailing: View, Bottom: View>: View {
    private let title: String
    @Binding private var scrollOffset: CGFloat
    private let leadingIcon: String?
    private let leadingAction: (() -> Void)?
    private let leadingView: AnyView?
    private let titleView: AnyView?
    private let tintColor: Color
    private let tintOpacity: Double
    private let titleMaxWidth: CGFloat
    private let topPadding: CGFloat
    private let bottomPadding: CGFloat
    private let blurThreshold: CGFloat
    private let blurOverflow: CGFloat
    private let showsBottom: Bool
    private let trailingContent: () -> Trailing
    private let bottomContent: () -> Bottom

    init(
        title: String = "",
        scrollOffset: Binding<CGFloat>,
        leadingIcon: String? = "chevron.left",
        leadingAction: (() -> Void)? = nil,
        leadingView: AnyView? = nil,
        titleView: AnyView? = nil,
        tintColor: Color = Color(UIColor.systemBackground),
        tintOpacity: Double = 1.0,
        titleMaxWidth: CGFloat = 220,
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0,
        blurThreshold: CGFloat = 30,
        blurOverflow: CGFloat = -60,
        showsBottom: Bool = true,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder bottom: @escaping () -> Bottom
    ) {
        self.title = title
        self._scrollOffset = scrollOffset
        self.leadingIcon = leadingIcon
        self.leadingAction = leadingAction
        self.leadingView = leadingView
        self.titleView = titleView
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.titleMaxWidth = titleMaxWidth
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.blurThreshold = blurThreshold
        self.blurOverflow = blurOverflow
        self.showsBottom = showsBottom
        self.trailingContent = trailing
        self.bottomContent = bottom
    }

    private var blurOpacity: Double {
        let progress = max(0, scrollOffset) / max(blurThreshold, 1)
        return min(1.0, Double(progress))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let titleView {
                    titleView
                        .frame(maxWidth: titleMaxWidth)
                } else if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: titleMaxWidth)
                }

                HStack {
                    if let leadingView {
                        leadingView
                    } else if let leadingIcon, let leadingAction {
                        TelegramGlassIconButton(systemName: leadingIcon, action: leadingAction)
                    }

                    Spacer()

                    trailingContent()
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 16)
            .padding(.top, topPadding)

            if showsBottom {
                bottomContent()
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, bottomPadding)
        .background(
            VariableBlurView(tintColor: tintColor, tintOpacity: tintOpacity)
                .padding(.bottom, blurOverflow)
                .ignoresSafeArea(edges: .top)
                .opacity(blurOpacity)
                .animation(.easeInOut(duration: 0.2), value: blurOpacity)
        )
    }
}

extension SlooshTopBar where Trailing == EmptyView, Bottom == EmptyView {
    init(
        title: String = "",
        scrollOffset: Binding<CGFloat>,
        leadingIcon: String? = "chevron.left",
        leadingAction: (() -> Void)? = nil,
        leadingView: AnyView? = nil,
        titleView: AnyView? = nil,
        tintColor: Color = Color(UIColor.systemBackground),
        tintOpacity: Double = 1.0,
        titleMaxWidth: CGFloat = 220,
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0,
        blurThreshold: CGFloat = 30,
        blurOverflow: CGFloat = -60
    ) {
        self.init(
            title: title,
            scrollOffset: scrollOffset,
            leadingIcon: leadingIcon,
            leadingAction: leadingAction,
            leadingView: leadingView,
            titleView: titleView,
            tintColor: tintColor,
            tintOpacity: tintOpacity,
            titleMaxWidth: titleMaxWidth,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            blurThreshold: blurThreshold,
            blurOverflow: blurOverflow,
            showsBottom: false,
            trailing: { EmptyView() },
            bottom: { EmptyView() }
        )
    }
}

extension SlooshTopBar where Bottom == EmptyView {
    init(
        title: String = "",
        scrollOffset: Binding<CGFloat>,
        leadingIcon: String? = "chevron.left",
        leadingAction: (() -> Void)? = nil,
        leadingView: AnyView? = nil,
        titleView: AnyView? = nil,
        tintColor: Color = Color(UIColor.systemBackground),
        tintOpacity: Double = 1.0,
        titleMaxWidth: CGFloat = 220,
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0,
        blurThreshold: CGFloat = 30,
        blurOverflow: CGFloat = -60,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            title: title,
            scrollOffset: scrollOffset,
            leadingIcon: leadingIcon,
            leadingAction: leadingAction,
            leadingView: leadingView,
            titleView: titleView,
            tintColor: tintColor,
            tintOpacity: tintOpacity,
            titleMaxWidth: titleMaxWidth,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            blurThreshold: blurThreshold,
            blurOverflow: blurOverflow,
            showsBottom: false,
            trailing: trailing,
            bottom: { EmptyView() }
        )
    }
}

extension SlooshTopBar where Trailing == EmptyView {
    init(
        title: String = "",
        scrollOffset: Binding<CGFloat>,
        leadingIcon: String? = "chevron.left",
        leadingAction: (() -> Void)? = nil,
        leadingView: AnyView? = nil,
        titleView: AnyView? = nil,
        tintColor: Color = Color(UIColor.systemBackground),
        tintOpacity: Double = 1.0,
        titleMaxWidth: CGFloat = 220,
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0,
        blurThreshold: CGFloat = 30,
        blurOverflow: CGFloat = -60,
        @ViewBuilder bottom: @escaping () -> Bottom
    ) {
        self.init(
            title: title,
            scrollOffset: scrollOffset,
            leadingIcon: leadingIcon,
            leadingAction: leadingAction,
            leadingView: leadingView,
            titleView: titleView,
            tintColor: tintColor,
            tintOpacity: tintOpacity,
            titleMaxWidth: titleMaxWidth,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            blurThreshold: blurThreshold,
            blurOverflow: blurOverflow,
            showsBottom: true,
            trailing: { EmptyView() },
            bottom: bottom
        )
    }
}

/// Стеклянная поисковая капсула в едином стиле приложения.
struct SlooshSearchField: View {
    @Binding var text: String
    var prompt: String = "Поиск"
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField(prompt, text: $text)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit {
                    onSubmit?()
                    isFocused = false
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}

/// Стеклянная текстовая кнопка для действий в шапке (Сохранить, Готово и т. п.).
struct SlooshGlassTextButton: View {
    let title: String
    var tintColor: Color = .primary
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isEnabled ? tintColor : tintColor.opacity(0.35))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.glassPress)
        .disabled(!isEnabled)
    }
}
