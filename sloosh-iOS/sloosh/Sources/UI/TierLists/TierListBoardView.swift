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
/// - Удержание 0.22 сек: тактильный щелчок, подъём карточки, полная заморозка скролла.
/// - Строго 0° наклон (никаких раскачиваний), никаких зависаний в воздухе.
/// - Защита от застревания в навбаре и у краев экрана с мягкой привязкой к верхнему уровню.
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
    @State private var lastAutoScrollTime = Date.distantPast

    // Мобильные пропорции 2:3
    private let posterWidth: CGFloat = 66
    private let posterHeight: CGFloat = 98
    private let chipWidth: CGFloat = 52

    var body: some View {
        boardStack
            .onPreferenceChange(BoardRowGeometryKey.self) { rowGeometries = $0 }
            .onPreferenceChange(BoardItemGeometryKey.self) { itemGeometries = $0 }
            .overlay { draggedCardOverlay }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { boardGlobalFrame = geo.frame(in: .global) }
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            boardGlobalFrame = newFrame
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: posterWidth), spacing: 6)], spacing: 6) {
            if items.isEmpty {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: posterHeight)
                    .contentShape(Rectangle())
            } else {
                ForEach(Array(items.enumerated()), id: \.element.mediaId) { index, item in
                    itemCell(item: item, sourceRowId: rowId, index: index)
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
                        onMove: { windowPoint in
                            handleDragMoved(windowPoint: windowPoint)
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

    private func handleDragMoved(windowPoint: CGPoint) {
        guard isDragging, activeDraggedItem != nil else { return }

        let localPoint = CGPoint(
            x: windowPoint.x - boardGlobalFrame.minX,
            y: windowPoint.y - boardGlobalFrame.minY
        )
        dragLocation = localPoint

        // 1. Проверка границ: если палец ушёл в верхний навбар (высота статус-бара + навбара ~ 96-104pt)
        let topBarThreshold: CGFloat = 100
        if windowPoint.y <= topBarThreshold {
            snapToTopRowAndCommit()
            return
        }

        // Если палец вылетел за боковые или нижние границы доски
        if boardGlobalFrame != .zero {
            let horizontalMargin: CGFloat = 60
            let bottomMargin: CGFloat = 80
            if windowPoint.x < (boardGlobalFrame.minX - horizontalMargin) ||
               windowPoint.x > (boardGlobalFrame.maxX + horizontalMargin) ||
               windowPoint.y > (boardGlobalFrame.maxY + bottomMargin) {
                cancelDrag()
                return
            }
        }

        // 2. Находим целевую строку
        guard let newTargetRowId = findTargetRow(at: windowPoint) else { return }

        // 3. Автоскролл экрана при подтягивании к краям (между навбаром и верхними строками)
        checkAutoScroll(windowPoint: windowPoint)

        // 4. Находим целевой индекс
        let newTargetIndex = findTargetIndex(in: newTargetRowId, at: windowPoint)

        if newTargetRowId != targetRowId || newTargetIndex != targetIndex {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                targetRowId = newTargetRowId
                targetIndex = newTargetIndex
                highlightedRowId = newTargetRowId
            }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    // MARK: - Автоскролл экрана

    private func checkAutoScroll(windowPoint: CGPoint) {
        guard Date().timeIntervalSince(lastAutoScrollTime) > 0.35 else { return }

        let allRowIds = rows.map(\.id) + ["__pool__"]
        guard let currentTargetRowId = targetRowId,
              let currentIndex = allRowIds.firstIndex(of: currentTargetRowId) else { return }

        let screenHeight = UIScreen.main.bounds.height

        // Тянем вверх к верхнему краю экрана (но ниже навбара)
        if windowPoint.y < 160 && windowPoint.y > 100 {
            lastAutoScrollTime = Date()
            if currentIndex > 0 {
                let previousRowId = allRowIds[currentIndex - 1]
                onScrollRequest?(previousRowId)
            } else {
                onScrollRequest?("__top__")
            }
            return
        }

        // Тянем вниз к нижнему краю экрана
        if windowPoint.y > (screenHeight - 180) {
            lastAutoScrollTime = Date()
            if currentIndex < allRowIds.count - 1 {
                let nextRowId = allRowIds[currentIndex + 1]
                onScrollRequest?(nextRowId)
            }
            return
        }
    }

    // MARK: - Привязка к верхнему уровню при выходе в навбар

    private func snapToTopRowAndCommit() {
        guard isDragging, activeDraggedItem != nil else { return }
        let destinationRowId = rows.first?.id ?? draggedFromRowId ?? "__pool__"
        targetRowId = destinationRowId
        targetIndex = 0
        commitMove()
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

    // MARK: - Геометрические вычисления в глобальных координатах

    private func findTargetRow(at windowPoint: CGPoint) -> String? {
        if rowGeometries.isEmpty { return nil }

        if let exact = rowGeometries.first(where: {
            windowPoint.y >= ($0.frame.minY - 8) && windowPoint.y <= ($0.frame.maxY + 8)
        }) {
            return exact.rowId
        }

        if let first = rowGeometries.min(by: { $0.frame.minY < $1.frame.minY }), windowPoint.y < first.frame.minY {
            return first.rowId
        }

        if let last = rowGeometries.max(by: { $0.frame.maxY < $1.frame.maxY }), windowPoint.y > last.frame.maxY {
            return last.rowId
        }

        return rowGeometries.min(by: { abs($0.frame.midY - windowPoint.y) < abs($1.frame.midY - windowPoint.y) })?.rowId
    }

    private func findTargetIndex(in rowId: String, at windowPoint: CGPoint) -> Int {
        let items = itemGeometries
            .filter { $0.rowId == rowId && $0.mediaId != activeDraggedItem?.mediaId }
            .sorted {
                if abs($0.frame.midY - $1.frame.midY) > 20 {
                    return $0.frame.midY < $1.frame.midY
                }
                return $0.frame.midX < $1.frame.midX
            }

        if items.isEmpty { return 0 }

        for (idx, itemGeo) in items.enumerated() {
            if windowPoint.y < (itemGeo.frame.minY - 4) {
                return idx
            }
            if windowPoint.y <= (itemGeo.frame.maxY + 10) {
                if windowPoint.x < itemGeo.frame.midX {
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

// MARK: - UIKit Gesture Recognizer для безупречного скролла и безопасного переноса

private struct InteractiveDragCardModifier: ViewModifier {
    let isEnabled: Bool
    let onLift: (CGPoint) -> Void
    let onMove: (CGPoint) -> Void
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
    var onMove: (CGPoint) -> Void
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
        view.onDetached = { [weak coordinator = context.coordinator] in
            coordinator?.handleViewDetached()
        }

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
        var onMove: (CGPoint) -> Void
        var onDrop: () -> Void
        var onCancel: () -> Void

        weak var recognizer: UILongPressGestureRecognizer?
        private weak var parentScrollView: UIScrollView?
        private weak var cachedWindow: UIWindow?
        private(set) var isDraggingActive = false

        init(
            onLift: @escaping (CGPoint) -> Void,
            onMove: @escaping (CGPoint) -> Void,
            onDrop: @escaping () -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onLift = onLift
            self.onMove = onMove
            self.onDrop = onDrop
            self.onCancel = onCancel
        }

        func handleViewDetached() {
            guard isDraggingActive else { return }
            finishDrag(cancelled: true)
        }

        deinit {
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
                cachedWindow = gesture.view?.window
                let scrollView = gesture.view?.findParentScrollView()
                parentScrollView = scrollView
                scrollView?.panGestureRecognizer.isEnabled = false

                let windowPoint = activeWindow.map { gesture.location(in: $0) } ?? gesture.location(in: gesture.view)
                onLift(windowPoint)

            case .changed:
                guard isDraggingActive else { return }
                guard let window = activeWindow else { return }
                let windowPoint = gesture.location(in: window)

                // Если палец вошёл в зону навбара — безопасно завершаем перенос
                let navBarBottom = (window.safeAreaInsets.top > 0 ? window.safeAreaInsets.top : 44) + 44
                if windowPoint.y <= navBarBottom {
                    gesture.isEnabled = false
                    gesture.isEnabled = true
                    finishDrag(cancelled: false)
                    return
                }

                onMove(windowPoint)

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
    var onDetached: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            onDetached?()
        }
    }

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
