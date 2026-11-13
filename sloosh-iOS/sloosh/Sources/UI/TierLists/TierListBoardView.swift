import SwiftUI
import UIKit

/// Геометрия строк и ячеек в абсолютных оконных координатах.
struct BoardRowGeometry: Equatable {
    let rowId: String
    let frame: CGRect
}

struct BoardItemGeometry: Equatable {
    let mediaId: String
    let rowId: String
    let index: Int
    let frame: CGRect
}

struct BoardRowGeometryKey: PreferenceKey {
    static var defaultValue: [BoardRowGeometry] = []
    static func reduce(value: inout [BoardRowGeometry], nextValue: () -> [BoardRowGeometry]) {
        value.append(contentsOf: nextValue())
    }
}

struct BoardItemGeometryKey: PreferenceKey {
    static var defaultValue: [BoardItemGeometry] = []
    static func reduce(value: inout [BoardItemGeometry], nextValue: () -> [BoardItemGeometry]) {
        value.append(contentsOf: nextValue())
    }
}

/// Флагманская доска тир-листа в стиле Apple TV+ / Liquid Glass.
/// Полное разделение скролла и переноса:
/// - Обычный свайп: мгновенный свободный скролл страницы по постерам.
/// - Удержание 0.22 сек: тактильный щелчок, подъём карточки, полная заморозка ручного скролла.
/// - Строго 0° наклон (никаких раскачиваний), непрерывный перенос без преждевременных сбросов.
/// - Плавный аппаратный автоскролл экрана при подтягивании карточки к верхнему или нижнему краю (CADisplayLink).
struct TierListBoardView: View {
    enum Mode { case edit, view }

    let mode: Mode
    @Binding var rows: [TierRow]
    @Binding var unranked: [TierListItem]
    @Binding var isDraggingActive: Bool
    var onTapItem: ((TierListItem) -> Void)?
    var onTapRow: ((TierRow) -> Void)?
    var onAddMovies: (() -> Void)?
    var onOpenDetails: ((TierListItem) -> Void)?
    var onScrollRequest: ((String) -> Void)?

    init(
        mode: Mode,
        rows: Binding<[TierRow]>,
        unranked: Binding<[TierListItem]>,
        isDraggingActive: Binding<Bool> = .constant(false),
        onTapItem: ((TierListItem) -> Void)? = nil,
        onTapRow: ((TierRow) -> Void)? = nil,
        onAddMovies: (() -> Void)? = nil,
        onOpenDetails: ((TierListItem) -> Void)? = nil,
        onScrollRequest: ((String) -> Void)? = nil
    ) {
        self.mode = mode
        self._rows = rows
        self._unranked = unranked
        self._isDraggingActive = isDraggingActive
        self.onTapItem = onTapItem
        self.onTapRow = onTapRow
        self.onAddMovies = onAddMovies
        self.onOpenDetails = onOpenDetails
        self.onScrollRequest = onScrollRequest
    }

    // MARK: - Состояние перетаскивания

    @State private var rowGeometries: [BoardRowGeometry] = []
    @State private var itemGeometries: [BoardItemGeometry] = []
    @State private var boardGlobalFrame: CGRect = .zero
    @State private var activeDraggedItem: TierListItem?
    @State private var draggedFromRowId: String?
    @State private var targetRowId: String?
    @State private var targetIndex: Int = 0
    @State private var dragLocation: CGPoint = .zero
    @State private var isDragging = false
    @State private var highlightedRowId: String?
    @State private var dragStartBoardFrame: CGRect = .zero
    @State private var dragStartRowGeometries: [BoardRowGeometry] = []
    @State private var dragStartItemGeometries: [BoardItemGeometry] = []

    // Мобильные пропорции 2:3
    private let posterWidth: CGFloat = 66
    private let posterHeight: CGFloat = 98
    private let chipWidth: CGFloat = 52

    var body: some View {
        boardStack
            .onPreferenceChange(BoardRowGeometryKey.self) { newGeos in
                rowGeometries = newGeos
                if !isDragging { dragStartRowGeometries = newGeos }
            }
            .onPreferenceChange(BoardItemGeometryKey.self) { newGeos in
                itemGeometries = newGeos
                if !isDragging { dragStartItemGeometries = newGeos }
            }
            .overlay { draggedCardOverlay }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            boardGlobalFrame = geo.frame(in: .global)
                            if !isDragging { dragStartBoardFrame = boardGlobalFrame }
                        }
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            boardGlobalFrame = newFrame
                            if !isDragging { dragStartBoardFrame = newFrame }
                        }
                }
            )
            .tint(.primary)
    }

    // MARK: - Структура доски

    @ViewBuilder
    private var boardStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($rows) { $row in
                tierRow($row)
            }
            if mode == .edit || !unranked.isEmpty {
                poolRow
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Строка уровня

    @ViewBuilder
    private func tierRow(_ row: Binding<TierRow>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            chip(row: row.wrappedValue)
            itemsGrid(rowId: row.wrappedValue.id, items: row.wrappedValue.items)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    highlightedRowId == row.wrappedValue.id ? Color.white.opacity(0.4) : Color.white.opacity(0.06),
                    lineWidth: highlightedRowId == row.wrappedValue.id ? 1.5 : 0.5
                )
        )
        .id(row.wrappedValue.id)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: BoardRowGeometryKey.self,
                    value: [BoardRowGeometry(rowId: row.wrappedValue.id, frame: geo.frame(in: .global))]
                )
            }
        )
    }

    // MARK: - Бейдж уровня (Apple Design)

    private func chip(row: TierRow) -> some View {
        let tierColor = Color(UIColor(hex: row.colorHex) ?? .systemGray)

        return Button {
            if mode == .edit {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTapRow?(row)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tierColor)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)

                Text(row.label)
                    .font(.system(size: 20, weight: .heavy, design: .default))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.35)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }
            .frame(width: chipWidth, height: posterHeight)
            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(mode != .edit)
    }

    // MARK: - Сетка постеров

    @ViewBuilder
    private func itemsGrid(rowId: String, items: [TierListItem]) -> some View {
        Group {
            if items.isEmpty {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: posterHeight)
                    .contentShape(Rectangle())
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.element.mediaId) { index, item in
                        itemCell(item: item, sourceRowId: rowId, index: index)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: posterHeight, alignment: .topLeading)
    }

    // MARK: - Ячейка постера

    @ViewBuilder
    private func itemCell(item: TierListItem, sourceRowId: String, index: Int) -> some View {
        let isBeingDragged = isDragging && activeDraggedItem?.mediaId == item.mediaId

        let card = itemCard(item: item, isLifted: false)
            .opacity(isBeingDragged ? 0.25 : 1.0)
            .frame(width: posterWidth, height: posterHeight)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: BoardItemGeometryKey.self,
                        value: [BoardItemGeometry(
                            mediaId: item.mediaId,
                            rowId: sourceRowId,
                            index: index,
                            frame: geo.frame(in: .global)
                        )]
                    )
                }
            )
            .contentShape(Rectangle())

        if mode == .edit {
            card
                .onTapGesture {
                    onTapItem?(item)
                }
                .modifier(
                    InteractiveDragCardModifier(
                        isEnabled: true,
                        onLift: { windowPoint in
                            startDragging(item: item, sourceRowId: sourceRowId, windowPoint: windowPoint)
                        },
                        onMove: { windowPoint, scrollDelta in
                            handleDragMoved(windowPoint: windowPoint, scrollDelta: scrollDelta)
                        },
                        onDrop: {
                            commitMove()
                        },
                        onCancel: {
                            cancelDrag()
                        }
                    )
                )
        } else {
            card
                .onTapGesture {
                    onOpenDetails?(item)
                }
        }
    }

    // MARK: - Карточка фильма

    @ViewBuilder
    private func itemCard(item: TierListItem, isLifted: Bool) -> some View {
        AsyncCachedImage(
            url: item.posterUrl.flatMap { URL(string: $0) },
            placeholder: {
                Rectangle().fill(Color(UIColor.tertiarySystemFill))
            },
            content: { image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            },
            fallback: {
                ZStack {
                    Rectangle().fill(Color(UIColor.tertiarySystemFill))
                    Text(String(item.title.prefix(1)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        )
        .frame(width: posterWidth, height: posterHeight)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isLifted ? Color.white.opacity(0.35) : Color.white.opacity(0.08), lineWidth: isLifted ? 1.0 : 0.5)
        )
        .shadow(color: Color.black.opacity(isLifted ? 0.3 : 0.12), radius: isLifted ? 12 : 2, y: isLifted ? 6 : 1)
    }

    // MARK: - Пул «Не распределено»

    private var poolRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Не распределено (\(unranked.count))", systemImage: "tray.full")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if mode == .edit {
                    Button {
                        onAddMovies?()
                    } label: {
                        Label("Добавить", systemImage: "plus")
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 4)

            if unranked.isEmpty && mode == .edit {
                Button {
                    onAddMovies?()
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color(UIColor.tertiarySystemFill))
                                .frame(width: 40, height: 40)
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        Text("Добавить фильмы в тир-лист")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Поиск по каталогу, подборкам и избранному")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 104)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.45))
                            )
                    )
                }
                .buttonStyle(.plain)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(UIColor.secondarySystemFill))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                        Text("?")
                            .font(.system(size: 20, weight: .heavy, design: .default))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: chipWidth, height: posterHeight)
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)

                    itemsGrid(rowId: "__pool__", items: unranked)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            highlightedRowId == "__pool__" ? Color.white.opacity(0.4) : Color.white.opacity(0.06),
                            lineWidth: highlightedRowId == "__pool__" ? 1.5 : 0.5
                        )
                )
                .id("__pool__")
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: BoardRowGeometryKey.self,
                            value: [BoardRowGeometry(rowId: "__pool__", frame: geo.frame(in: .global))]
                        )
                    }
                )
            }
        }
    }

    // MARK: - Поднятая карточка под пальцем (Overlay) — строго 0° наклон (без раскачиваний)

    @ViewBuilder
    private var draggedCardOverlay: some View {
        if isDragging, let item = activeDraggedItem {
            itemCard(item: item, isLifted: true)
                .scaleEffect(1.05)
                .position(x: dragLocation.x, y: dragLocation.y)
                .transition(.identity)
                .zIndex(999)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Логика перетаскивания

    private func startDragging(item: TierListItem, sourceRowId: String, windowPoint: CGPoint) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        dragStartBoardFrame = boardGlobalFrame
        dragStartRowGeometries = rowGeometries
        dragStartItemGeometries = itemGeometries

        let localPoint = CGPoint(
            x: windowPoint.x - boardGlobalFrame.minX,
            y: windowPoint.y - boardGlobalFrame.minY
        )
        withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
            activeDraggedItem = item
            draggedFromRowId = sourceRowId
            targetRowId = sourceRowId
            targetIndex = currentIndex(for: item.mediaId, in: sourceRowId) ?? 0
            dragLocation = localPoint
            isDragging = true
            isDraggingActive = true
            highlightedRowId = sourceRowId
        }
    }

    private func handleDragMoved(windowPoint: CGPoint, scrollDelta: CGFloat) {
        guard isDragging, activeDraggedItem != nil else { return }

        // Позиция под пальцем с поправкой на физический сдвиг доски в скролле
        let effectiveBoardY = dragStartBoardFrame.minY - scrollDelta
        let localPoint = CGPoint(
            x: windowPoint.x - dragStartBoardFrame.minX,
            y: windowPoint.y - effectiveBoardY
        )
        dragLocation = localPoint

        // Находим целевую строку с учётом текущего сдвига скролла
        guard let newTargetRowId = findTargetRow(at: windowPoint, scrollDelta: scrollDelta) else { return }

        // Находим целевой индекс с учётом текущего сдвига скролла
        let newTargetIndex = findTargetIndex(in: newTargetRowId, at: windowPoint, scrollDelta: scrollDelta)

        if newTargetRowId != targetRowId || newTargetIndex != targetIndex {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                targetRowId = newTargetRowId
                targetIndex = newTargetIndex
                highlightedRowId = newTargetRowId
            }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    // MARK: - Фиксация перемещения на отпускание пальца

    private func commitMove() {
        guard let dragged = activeDraggedItem,
              let sourceRow = draggedFromRowId,
              let targetRow = targetRowId else {
            cancelDrag()
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            let currentSourceIndex = currentIndex(for: dragged.mediaId, in: sourceRow)

            // Если переместили в другую строку или сменили индекс в текущей
            if sourceRow != targetRow || targetIndex != currentSourceIndex {
                // 1. Удаляем из исходного места
                if sourceRow == "__pool__" {
                    unranked.removeAll { $0.mediaId == dragged.mediaId }
                } else if let rIdx = rows.firstIndex(where: { $0.id == sourceRow }) {
                    rows[rIdx].items.removeAll { $0.mediaId == dragged.mediaId }
                }

                // 2. Вставляем в целевое место по индексу targetIndex
                if targetRow == "__pool__" {
                    let safeIndex = max(0, min(targetIndex, unranked.count))
                    unranked.insert(dragged, at: safeIndex)
                } else if let rIdx = rows.firstIndex(where: { $0.id == targetRow }) {
                    let safeIndex = max(0, min(targetIndex, rows[rIdx].items.count))
                    rows[rIdx].items.insert(dragged, at: safeIndex)
                }
            }

            activeDraggedItem = nil
            draggedFromRowId = nil
            targetRowId = nil
            isDragging = false
            isDraggingActive = false
            highlightedRowId = nil
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Безопасная отмена перетаскивания

    private func cancelDrag() {
        guard isDragging || activeDraggedItem != nil else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            activeDraggedItem = nil
            draggedFromRowId = nil
            targetRowId = nil
            isDragging = false
            isDraggingActive = false
            highlightedRowId = nil
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Геометрические вычисления в глобальных координатах с учётом скролла

    private func findTargetRow(at windowPoint: CGPoint, scrollDelta: CGFloat) -> String? {
        let baseRows = dragStartRowGeometries.isEmpty ? rowGeometries : dragStartRowGeometries
        if baseRows.isEmpty { return nil }

        let liveRows: [(rowId: String, frame: CGRect)] = baseRows.map {
            (rowId: $0.rowId, frame: $0.frame.offsetBy(dx: 0, dy: -scrollDelta))
        }

        // 1. Точное попадание в строку
        if let exact = liveRows.first(where: {
            windowPoint.y >= ($0.frame.minY - 8) && windowPoint.y <= ($0.frame.maxY + 8)
        }) {
            return exact.rowId
        }

        // 2. Выше самой верхней строки (в навбаре) — привязка к верхней строке (например, S)
        if let first = liveRows.min(by: { $0.frame.minY < $1.frame.minY }), windowPoint.y < first.frame.minY {
            return first.rowId
        }

        // 3. Ниже самой нижней строки — привязка к нижней строке (пул)
        if let last = liveRows.max(by: { $0.frame.maxY < $1.frame.maxY }), windowPoint.y > last.frame.maxY {
            return last.rowId
        }

        // 4. Ближайшая строка по центру
        return liveRows.min(by: { abs($0.frame.midY - windowPoint.y) < abs($1.frame.midY - windowPoint.y) })?.rowId
    }

    private func findTargetIndex(in rowId: String, at windowPoint: CGPoint, scrollDelta: CGFloat) -> Int {
        let baseItems = dragStartItemGeometries.isEmpty ? itemGeometries : dragStartItemGeometries
        let items = baseItems
            .filter { $0.rowId == rowId && $0.mediaId != activeDraggedItem?.mediaId }
            .map { (mediaId: $0.mediaId, frame: $0.frame.offsetBy(dx: 0, dy: -scrollDelta)) }
            .sorted {
                if abs($0.frame.midY - $1.frame.midY) > 20 {
                    return $0.frame.midY < $1.frame.midY
                }
                return $0.frame.midX < $1.frame.midX
            }

        if items.isEmpty { return 0 }

        for (idx, item) in items.enumerated() {
            if windowPoint.y < (item.frame.minY - 4) {
                return idx
            }
            if windowPoint.y <= (item.frame.maxY + 10) {
                if windowPoint.x < item.frame.midX {
                    return idx
                }
            }
        }
        return items.count
    }

    private func currentIndex(for mediaId: String, in rowId: String) -> Int? {
        if rowId == "__pool__" {
            return unranked.firstIndex(where: { $0.mediaId == mediaId })
        }
        if let row = rows.first(where: { $0.id == rowId }) {
            return row.items.firstIndex(where: { $0.mediaId == mediaId })
        }
        return nil
    }
}

// MARK: - Компактная неленивая обёрточная раскладка карточек

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxAvailableWidth = proposal.width ?? 0
        guard maxAvailableWidth > 0, !subviews.isEmpty else {
            return .zero
        }

        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxAvailableWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxAvailableWidth, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard bounds.width > 0, !subviews.isEmpty else { return }

        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Плавный аппаратный автоскролл экрана на базе CADisplayLink

final class TierListAutoScroller {
    private weak var scrollView: UIScrollView?
    private var displayLink: CADisplayLink?
    private var touchPointInWindow: CGPoint = .zero
    private weak var window: UIWindow?
    private var onTick: (() -> Void)?

    func start(scrollView: UIScrollView, onTick: @escaping () -> Void) {
        self.scrollView = scrollView
        self.onTick = onTick
        stop()

        let link = CADisplayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    func updateTouch(pointInWindow: CGPoint, window: UIWindow?) {
        self.touchPointInWindow = pointInWindow
        if self.window == nil {
            self.window = window
        }
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        scrollView = nil
        window = nil
        onTick = nil
        touchPointInWindow = .zero
    }

    @objc private func handleDisplayLink(_ link: CADisplayLink) {
        guard let scrollView = scrollView, touchPointInWindow != .zero else { return }
        guard let window = window ?? scrollView.window else { return }

        let windowBounds = window.bounds
        let safeTop = window.safeAreaInsets.top
        let safeBottom = window.safeAreaInsets.bottom

        // Верхний порог автоскролла: навигационная панель (~ safeTop + 44)
        let topBarThreshold = max(safeTop + 44, 90)
        let topAutoScrollZone = topBarThreshold + 110

        // Нижний порог автоскролла: таб-бар / безопасная зона (~ height - safeBottom - 20)
        let bottomBarThreshold = max(windowBounds.height - safeBottom - 20, 200)
        let bottomAutoScrollZone = bottomBarThreshold - 110

        let touchY = touchPointInWindow.y
        var velocity: CGFloat = 0

        if touchY < topAutoScrollZone {
            // Тянем вверх к шапке — плавное ускорение по мере приближения к верхнему краю
            let distance = topAutoScrollZone - touchY
            let progress = min(1.0, max(0.0, distance / 110))
            velocity = -(120 + 480 * progress)
        } else if touchY > bottomAutoScrollZone {
            // Тянем вниз к низу экрана — плавное ускорение по мере приближения к нижнему краю
            let distance = touchY - bottomAutoScrollZone
            let progress = min(1.0, max(0.0, distance / 110))
            velocity = (120 + 480 * progress)
        }

        guard velocity != 0 else { return }

        let dt = min(max(link.targetTimestamp - link.timestamp, 1.0 / 120.0), 1.0 / 30.0)
        let step = velocity * CGFloat(dt)

        let minOffset = -scrollView.adjustedContentInset.top
        let maxOffset = max(minOffset, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)

        let currentOffset = scrollView.contentOffset.y
        let newOffset = min(max(currentOffset + step, minOffset), maxOffset)

        if abs(newOffset - currentOffset) > 0.1 {
            scrollView.contentOffset.y = newOffset
            onTick?()
        }
    }
}

// MARK: - UIKit Gesture Recognizer для безупречного скролла и безопасного переноса

private struct InteractiveDragCardModifier: ViewModifier {
    let isEnabled: Bool
    let onLift: (CGPoint) -> Void
    let onMove: (CGPoint, CGFloat) -> Void
    let onDrop: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.overlay(
                InteractiveDragGestureRecognizer(
                    onLift: onLift,
                    onMove: onMove,
                    onDrop: onDrop,
                    onCancel: onCancel
                )
            )
        } else {
            content
        }
    }
}

private struct InteractiveDragGestureRecognizer: UIViewRepresentable {
    var onLift: (CGPoint) -> Void
    var onMove: (CGPoint, CGFloat) -> Void
    var onDrop: () -> Void
    var onCancel: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = TouchForwardingView()
        view.backgroundColor = .clear

        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        recognizer.minimumPressDuration = 0.22
        recognizer.allowableMovement = 12
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = context.coordinator
        view.addGestureRecognizer(recognizer)

        context.coordinator.recognizer = recognizer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onLift = onLift
        context.coordinator.onMove = onMove
        context.coordinator.onDrop = onDrop
        context.coordinator.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLift: onLift, onMove: onMove, onDrop: onDrop, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onLift: (CGPoint) -> Void
        var onMove: (CGPoint, CGFloat) -> Void
        var onDrop: () -> Void
        var onCancel: () -> Void

        weak var recognizer: UILongPressGestureRecognizer?
        private weak var parentScrollView: UIScrollView?
        private weak var cachedWindow: UIWindow?
        private(set) var isDraggingActive = false
        private var initialScrollOffset: CGFloat = 0
        private let autoScroller = TierListAutoScroller()
        private var lastWindowPoint: CGPoint = .zero

        init(
            onLift: @escaping (CGPoint) -> Void,
            onMove: @escaping (CGPoint, CGFloat) -> Void,
            onDrop: @escaping () -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onLift = onLift
            self.onMove = onMove
            self.onDrop = onDrop
            self.onCancel = onCancel
        }

        deinit {
            autoScroller.stop()
            if isDraggingActive {
                let scroll = parentScrollView
                let cancelBlock = onCancel
                DispatchQueue.main.async {
                    scroll?.panGestureRecognizer.isEnabled = true
                    cancelBlock()
                }
            }
        }

        private func finishDrag(cancelled: Bool) {
            guard isDraggingActive else { return }
            isDraggingActive = false
            autoScroller.stop()
            parentScrollView?.panGestureRecognizer.isEnabled = true
            if cancelled {
                onCancel()
            } else {
                onDrop()
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            let activeWindow = gesture.view?.window ?? cachedWindow ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })

            switch gesture.state {
            case .began:
                isDraggingActive = true
                cachedWindow = gesture.view?.window ?? activeWindow
                let scrollView = gesture.view?.findParentScrollView()
                parentScrollView = scrollView
                scrollView?.panGestureRecognizer.isEnabled = false

                let currentOffset = scrollView?.contentOffset.y ?? 0
                initialScrollOffset = currentOffset

                let windowPoint = activeWindow.map { gesture.location(in: $0) } ?? gesture.location(in: gesture.view)
                lastWindowPoint = windowPoint

                if let scrollView = scrollView {
                    autoScroller.start(scrollView: scrollView) { [weak self] in
                        self?.handleAutoScrollTick()
                    }
                    autoScroller.updateTouch(pointInWindow: windowPoint, window: activeWindow)
                }

                onLift(windowPoint)

            case .changed:
                guard isDraggingActive else { return }
                guard let window = activeWindow else { return }
                let windowPoint = gesture.location(in: window)
                lastWindowPoint = windowPoint

                autoScroller.updateTouch(pointInWindow: windowPoint, window: window)

                let currentOffset = parentScrollView?.contentOffset.y ?? initialScrollOffset
                let scrollDelta = currentOffset - initialScrollOffset
                onMove(windowPoint, scrollDelta)

            case .ended:
                guard isDraggingActive else { return }
                finishDrag(cancelled: false)

            case .cancelled, .failed:
                guard isDraggingActive else { return }
                finishDrag(cancelled: true)

            default:
                break
            }
        }

        private func handleAutoScrollTick() {
            guard isDraggingActive else { return }
            let currentOffset = parentScrollView?.contentOffset.y ?? initialScrollOffset
            let scrollDelta = currentOffset - initialScrollOffset
            onMove(lastWindowPoint, scrollDelta)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Разрешаем параллельный скролл только пока палец не зажат неподвижно (состояние .possible)
            // Как только лонгпресс активировался (.began / .changed) — скролл страницы намертво запрещён!
            if gestureRecognizer.state == .began || gestureRecognizer.state == .changed {
                return false
            }
            return true
        }
    }
}

private final class TouchForwardingView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return super.hitTest(point, with: event)
    }
}

private extension UIView {
    func findParentScrollView() -> UIScrollView? {
        var current = self.superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}

// MARK: - Системная палитра уровней (Apple Dark Palette)

enum TierRowPalette {
    static let colors: [(name: String, hex: String)] = [
        ("Красный", "FF453A"), ("Оранжевый", "FF9F0A"), ("Жёлтый", "FFD60A"),
        ("Зелёный", "30D158"), ("Мятный", "66D4CF"), ("Бирюзовый", "64D2FF"),
        ("Голубой", "0A84FF"), ("Синий", "5E5CE6"), ("Фиолетовый", "BF5AF2"),
        ("Розовый", "FF375F"), ("Коричневый", "AC8E68"), ("Серый", "8E8E93")
    ]
}
