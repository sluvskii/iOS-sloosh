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
    private let tintColor: Color
    private let tintOpacity: Double
    private let titleMaxWidth: CGFloat
    private let topPadding: CGFloat
    private let bottomPadding: CGFloat
    private let blurThreshold: CGFloat
    private let blurOverflow: CGFloat
    private let showsBottom: Bool
    private let showsGrabber: Bool
    private let trailingContent: () -> Trailing
    private let bottomContent: () -> Bottom

    init(
        title: String,
        scrollOffset: Binding<CGFloat>,
        leadingIcon: String? = "chevron.left",
        leadingAction: (() -> Void)? = nil,
        tintColor: Color = Color(UIColor.systemBackground),
        tintOpacity: Double = 1.0,
        titleMaxWidth: CGFloat = 220,
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0,
        blurThreshold: CGFloat = 30,
        blurOverflow: CGFloat = -60,
        showsBottom: Bool = true,
        showsGrabber: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder bottom: @escaping () -> Bottom
    ) {
        self.title = title
        self._scrollOffset = scrollOffset
        self.leadingIcon = leadingIcon
        self.leadingAction = leadingAction
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.titleMaxWidth = titleMaxWidth
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.blurThreshold = blurThreshold
        self.blurOverflow = blurOverflow
        self.showsBottom = showsBottom
        self.showsGrabber = showsGrabber
        self.trailingContent = trailing
        self.bottomContent = bottom
    }

    private var blurOpacity: Double {
        let progress = max(0, scrollOffset) / max(blurThreshold, 1)
        return min(1.0, Double(progress))
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsGrabber {
                // Собственный grabber вместо системного: геометрия шапки
                // больше не зависит от типа presentationDetents.
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.22))
                    .frame(width: SheetMetrics.grabberWidth, height: SheetMetrics.grabberHeight)
                    .padding(.top, SheetMetrics.grabberTopPadding)
                    .padding(.bottom, SheetMetrics.grabberSpacing)
                    .accessibilityHidden(true)
            }

            ZStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: titleMaxWidth)

                HStack {
                    if let leadingIcon, let leadingAction {
                        TelegramGlassIconButton(systemName: leadingIcon, action: leadingAction)
                    }

                    Spacer()

                    trailingContent()
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 16)
            .padding(.top, showsGrabber ? 0 : topPadding)

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

// MARK: - Canonical Sheet Header Factory

/// Единые канонические метрики для всех модальных шторок приложения.
/// Ритм строго симметричный: 8pt до «ручки», 8pt до заголовка, 8pt снизу.
/// Заголовок всегда начинается на одной и той же высоте от кромки шторки,
/// независимо от типа `presentationDetents`.
enum SheetMetrics {
    static let grabberWidth: CGFloat = 36
    static let grabberHeight: CGFloat = 5
    static let grabberTopPadding: CGFloat = 8
    static let grabberSpacing: CGFloat = 8
    static let bottomPadding: CGFloat = 8
    static let blurOverflow: CGFloat = -30
    static let blurThreshold: CGFloat = 20

    /// Расстояние от кромки шторки до ряда кнопок (8 + 5 + 8).
    static var rowTopInset: CGFloat {
        grabberTopPadding + grabberHeight + grabberSpacing
    }
}

/// «Ручка» шторки в каноническом ритме — для кастомных шапок,
/// которым нужна собственная раскладка кнопок.
struct SlooshSheetGrabber: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.primary.opacity(0.22))
            .frame(width: SheetMetrics.grabberWidth, height: SheetMetrics.grabberHeight)
            .padding(.top, SheetMetrics.grabberTopPadding)
            .padding(.bottom, SheetMetrics.grabberSpacing)
            .accessibilityHidden(true)
    }
}

/// Контейнер кастомной шапки шторки: «ручка» + тот же ритм 8/8/8,
/// что и у `SlooshTopBar.sheet(...)`.
struct SlooshSheetHeader<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            SlooshSheetGrabber()
            content()
        }
        .padding(.bottom, SheetMetrics.bottomPadding)
    }
}

extension SlooshTopBar where Trailing == EmptyView, Bottom == EmptyView {
    /// Каноническая шапка шторки без правых кнопок и без подвала.
    static func sheet(
        title: String,
        scrollOffset: Binding<CGFloat>,
        leadingIcon: String? = "xmark",
        leadingAction: (() -> Void)? = nil,
        titleMaxWidth: CGFloat = 220
    ) -> SlooshTopBar<EmptyView, EmptyView> {
        SlooshTopBar(
            title: title,
            scrollOffset: scrollOffset,
            leadingIcon: leadingIcon,
            leadingAction: leadingAction,
            tintColor: .clear,
            tintOpacity: 0,
            titleMaxWidth: titleMaxWidth,
            topPadding: 0,
            bottomPadding: SheetMetrics.bottomPadding,
            blurThreshold: SheetMetrics.blurThreshold,
            blurOverflow: SheetMetrics.blurOverflow,
            showsGrabber: true
        )
    }
}

extension SlooshTopBar where Bottom == EmptyView {
    /// Каноническая шапка шторки с trailing-элементами (иконки, действия).
    static func sheet(
        title: String,
        scrollOffset: Binding<CGFloat>,
        leadingIcon: String? = "xmark",
        leadingAction: (() -> Void)? = nil,
        titleMaxWidth: CGFloat = 220,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> SlooshTopBar<Trailing, EmptyView> {
        SlooshTopBar(
            title: title,
            scrollOffset: scrollOffset,
            leadingIcon: leadingIcon,
            leadingAction: leadingAction,
            tintColor: .clear,
            tintOpacity: 0,
            titleMaxWidth: titleMaxWidth,
            topPadding: 0,
            bottomPadding: SheetMetrics.bottomPadding,
            blurThreshold: SheetMetrics.blurThreshold,
            blurOverflow: SheetMetrics.blurOverflow,
            showsGrabber: true,
            trailing: trailing
        )
    }
}

extension SlooshTopBar where Trailing == EmptyView {
    /// Каноническая шапка шторки со строкой поиска или табами внизу.
    static func sheet(
        title: String,
        scrollOffset: Binding<CGFloat>,
        leadingIcon: String? = "xmark",
        leadingAction: (() -> Void)? = nil,
        titleMaxWidth: CGFloat = 220,
        @ViewBuilder bottom: @escaping () -> Bottom
    ) -> SlooshTopBar<EmptyView, Bottom> {
        SlooshTopBar(
            title: title,
            scrollOffset: scrollOffset,
            leadingIcon: leadingIcon,
            leadingAction: leadingAction,
            tintColor: .clear,
            tintOpacity: 0,
            titleMaxWidth: titleMaxWidth,
            topPadding: 0,
            bottomPadding: SheetMetrics.bottomPadding,
            blurThreshold: SheetMetrics.blurThreshold,
            blurOverflow: SheetMetrics.blurOverflow,
            showsGrabber: true,
            bottom: bottom
        )
    }
}

extension SlooshTopBar {
    /// Каноническая шапка шторки с trailing-элементами и нижней строкой.
    static func sheet(
        title: String,
        scrollOffset: Binding<CGFloat>,
        leadingIcon: String? = "xmark",
        leadingAction: (() -> Void)? = nil,
        titleMaxWidth: CGFloat = 220,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder bottom: @escaping () -> Bottom
    ) -> SlooshTopBar<Trailing, Bottom> {
        SlooshTopBar(
            title: title,
            scrollOffset: scrollOffset,
            leadingIcon: leadingIcon,
            leadingAction: leadingAction,
            tintColor: .clear,
            tintOpacity: 0,
            titleMaxWidth: titleMaxWidth,
            topPadding: 0,
            bottomPadding: SheetMetrics.bottomPadding,
            blurThreshold: SheetMetrics.blurThreshold,
            blurOverflow: SheetMetrics.blurOverflow,
            showsGrabber: true,
            trailing: trailing,
            bottom: bottom
        )
    }
}

extension SlooshTopBar where Trailing == EmptyView, Bottom == EmptyView {
    init(
        title: String,
        scrollOffset: Binding<CGFloat>,
        leadingIcon: String? = "chevron.left",
        leadingAction: (() -> Void)? = nil,
        tintColor: Color = Color(UIColor.systemBackground),
        tintOpacity: Double = 1.0,
        titleMaxWidth: CGFloat = 220,
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0,
        blurThreshold: CGFloat = 30,
        blurOverflow: CGFloat = -60,
        showsGrabber: Bool = false
    ) {
        self.init(
            title: title,
            scrollOffset: scrollOffset,
            leadingIcon: leadingIcon,
            leadingAction: leadingAction,
            tintColor: tintColor,
            tintOpacity: tintOpacity,
            titleMaxWidth: titleMaxWidth,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            blurThreshold: blurThreshold,
            blurOverflow: blurOverflow,
            showsBottom: false,
            showsGrabber: showsGrabber,
            trailing: { EmptyView() },
            bottom: { EmptyView() }
        )
    }
}

extension SlooshTopBar where Bottom == EmptyView {
    init(
        title: String,
        scrollOffset: Binding<CGFloat>,
        leadingIcon: String? = "chevron.left",
        leadingAction: (() -> Void)? = nil,
        tintColor: Color = Color(UIColor.systemBackground),
        tintOpacity: Double = 1.0,
        titleMaxWidth: CGFloat = 220,
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0,
        blurThreshold: CGFloat = 30,
        blurOverflow: CGFloat = -60,
        showsGrabber: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            title: title,
            scrollOffset: scrollOffset,
            leadingIcon: leadingIcon,
            leadingAction: leadingAction,
            tintColor: tintColor,
            tintOpacity: tintOpacity,
            titleMaxWidth: titleMaxWidth,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            blurThreshold: blurThreshold,
            blurOverflow: blurOverflow,
            showsBottom: false,
            showsGrabber: showsGrabber,
            trailing: trailing,
            bottom: { EmptyView() }
        )
    }
}

extension SlooshTopBar where Trailing == EmptyView {
    init(
        title: String,
        scrollOffset: Binding<CGFloat>,
        leadingIcon: String? = "chevron.left",
        leadingAction: (() -> Void)? = nil,
        tintColor: Color = Color(UIColor.systemBackground),
        tintOpacity: Double = 1.0,
        titleMaxWidth: CGFloat = 220,
        topPadding: CGFloat = 0,
        bottomPadding: CGFloat = 0,
        blurThreshold: CGFloat = 30,
        blurOverflow: CGFloat = -60,
        showsGrabber: Bool = false,
        @ViewBuilder bottom: @escaping () -> Bottom
    ) {
        self.init(
            title: title,
            scrollOffset: scrollOffset,
            leadingIcon: leadingIcon,
            leadingAction: leadingAction,
            tintColor: tintColor,
            tintOpacity: tintOpacity,
            titleMaxWidth: titleMaxWidth,
            topPadding: topPadding,
            bottomPadding: bottomPadding,
            blurThreshold: blurThreshold,
            blurOverflow: blurOverflow,
            showsBottom: true,
            showsGrabber: showsGrabber,
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
