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

/// Виртуальный слот в сетке строки тир-листа
enum GridSlot: Identifiable, Equatable {
    case item(TierListItem)
    case placeholder

    var id: String {
        switch self {
        case .item(let item): return item.mediaId
        case .placeholder: return "__drag_placeholder__"
        }
    }
}

/// Флагманская доска тир-листа в стиле Apple TV+ / Liquid Glass.
/// Полностью свободный скролл экрана при касании в любой области постеров,
/// перетаскивание без застреваний, автоскролл экрана при подтягивании к краям,
/// строго вертикальная карточка (0° наклон).
struct TierListBoardView: View {
    enum Mode { case edit, view }

    let mode: Mode
    @Binding var rows: [TierRow]
    @Binding var unranked: [TierListItem]
    var onTapItem: ((TierListItem) -> Void)?
    var onTapRow: ((TierRow) -> Void)?
    var onAddMovies: (() -> Void)?
    var onOpenDetails: ((TierListItem) -> Void)?
    var onScrollRequest: ((String) -> Void)?

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
                    highlightedRowId == row.wrappedValue.id ? Color.primary.opacity(0.4) : Color.white.opacity(0.06),
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

    // MARK: - Глянцевый бейдж уровня

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
                    .fill(
                        LinearGradient(
                            colors: [tierColor, tierColor.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)

                Text(row.label)
                    .font(.system(size: 20, weight: .heavy, design: .default))
                    .foregroundStyle(.white)
                    .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1.5)
                    .minimumScaleFactor(0.35)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            }
            .frame(width: chipWidth, height: posterHeight)
        }
        .buttonStyle(.plain)
        .disabled(mode != .edit)
    }

    // MARK: - Сетка постеров

    @ViewBuilder
    private func itemsGrid(rowId: String, items: [TierListItem]) -> some View {
        let rowSlots = computeSlots(for: rowId, items: items)

        LazyVGrid(columns: [GridItem(.adaptive(minimum: posterWidth), spacing: 6)], spacing: 6) {
            if rowSlots.isEmpty {
                emptyRowPlaceholder(isPool: rowId == "__pool__")
            } else {
                ForEach(Array(rowSlots.enumerated()), id: \.element.id) { index, slot in
                    switch slot {
                    case .item(let item):
                        itemCell(item: item, sourceRowId: rowId, index: index)
                    case .placeholder:
                        placeholderSlot
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: posterHeight, alignment: .topLeading)
    }

    // MARK: - Вычисление слотов без разрушения исходной модели

    private func computeSlots(for rowId: String, items: [TierListItem]) -> [GridSlot] {
        var result: [GridSlot] = items
            .filter { $0.mediaId != activeDraggedItem?.mediaId }
            .map { .item($0) }

        if isDragging, targetRowId == rowId {
            let safeIndex = max(0, min(targetIndex, result.count))
            result.insert(.placeholder, at: safeIndex)
        }

        return result
    }

    // MARK: - Ячейка постера

    @ViewBuilder
    private func itemCell(item: TierListItem, sourceRowId: String, index: Int) -> some View {
        let card = itemCard(item: item, isLifted: false)
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
                .strokeBorder(isLifted ? Color.white.opacity(0.4) : Color.white.opacity(0.1), lineWidth: isLifted ? 1.0 : 0.5)
        )
        .shadow(color: Color.black.opacity(isLifted ? 0.45 : 0.2), radius: isLifted ? 16 : 3, y: isLifted ? 10 : 1.5)
    }

    // MARK: - Плейсхолдер слота в сетке при перетаскивании

    private var placeholderSlot: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: posterWidth, height: posterHeight)
    }

    // MARK: - Заглушка пустой строки

    @ViewBuilder
    private func emptyRowPlaceholder(isPool: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isPool ? "tray" : "plus.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(isPool ? "Здесь будут новые фильмы" : (mode == .edit ? "Перетащите фильм сюда" : "Нет фильмов"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: posterHeight)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
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
                            .fill(Color(UIColor.tertiarySystemFill))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                        Text("?")
                            .font(.system(size: 21, weight: .heavy))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: chipWidth, height: posterHeight)

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
                            highlightedRowId == "__pool__" ? Color.primary.opacity(0.4) : Color.white.opacity(0.06),
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

    // MARK: - Поднятая карточка под пальцем (Overlay) — строго вертикальная (без наклонов!)

    @ViewBuilder
    private var draggedCardOverlay: some View {
        if isDragging, let item = activeDraggedItem {
            itemCard(item: item, isLifted: true)
                .scaleEffect(1.05)
                .shadow(color: Color.black.opacity(0.5), radius: 18, x: 0, y: 10)
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
            highlightedRowId = sourceRowId
        }
    }

    private func handleDragMoved(windowPoint: CGPoint) {
        let localPoint = CGPoint(
            x: windowPoint.x - boardGlobalFrame.minX,
            y: windowPoint.y - boardGlobalFrame.minY
        )
        dragLocation = localPoint
        guard let dragged = activeDraggedItem else { return }

        // 1. Находим целевую строку
        guard let newTargetRowId = findTargetRow(at: windowPoint) else { return }

        // 2. Автоскролл экрана при подтягивании к краям
        checkAutoScroll(windowPoint: windowPoint)

        // 3. Находим целевой индекс внутри целевой строки
        let newTargetIndex = findTargetIndex(in: newTargetRowId, at: windowPoint)

        // 4. Плавно перемещаем виртуальный слот плейсхолдера
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

        // Тянем вверх к верхнему краю экрана
        if windowPoint.y < 160 {
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

    // MARK: - Фиксация перемещения на отпускание пальца

    private func commitMove() {
        guard let dragged = activeDraggedItem,
              let sourceRow = draggedFromRowId,
              let targetRow = targetRowId else {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                activeDraggedItem = nil
                isDragging = false
                highlightedRowId = nil
            }
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            // Удаляем из исходного места
            if sourceRow == "__pool__" {
                unranked.removeAll { $0.mediaId == dragged.mediaId }
            } else if let rIdx = rows.firstIndex(where: { $0.id == sourceRow }) {
                rows[rIdx].items.removeAll { $0.mediaId == dragged.mediaId }
            }

            // Вставляем в целевое место по индексу targetIndex
            if targetRow == "__pool__" {
                let safeIndex = max(0, min(targetIndex, unranked.count))
                unranked.insert(dragged, at: safeIndex)
            } else if let rIdx = rows.firstIndex(where: { $0.id == targetRow }) {
                let safeIndex = max(0, min(targetIndex, rows[rIdx].items.count))
                rows[rIdx].items.insert(dragged, at: safeIndex)
            }

            activeDraggedItem = nil
            isDragging = false
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

// MARK: - UIKit Gesture Recognizer для безупречного скролла без блокировки родительского ScrollView

private struct InteractiveDragCardModifier: ViewModifier {
    let isEnabled: Bool
    let onLift: (CGPoint) -> Void
    let onMove: (CGPoint) -> Void
    let onDrop: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.overlay(
                InteractiveDragGestureRecognizer(onLift: onLift, onMove: onMove, onDrop: onDrop)
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

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onLift = onLift
        context.coordinator.onMove = onMove
        context.coordinator.onDrop = onDrop
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLift: onLift, onMove: onMove, onDrop: onDrop)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onLift: (CGPoint) -> Void
        var onMove: (CGPoint) -> Void
        var onDrop: () -> Void

        init(onLift: @escaping (CGPoint) -> Void, onMove: @escaping (CGPoint) -> Void, onDrop: @escaping () -> Void) {
            self.onLift = onLift
            self.onMove = onMove
            self.onDrop = onDrop
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let window = gesture.view?.window else { return }
            let windowPoint = gesture.location(in: window)

            switch gesture.state {
            case .began:
                onLift(windowPoint)
            case .changed:
                onMove(windowPoint)
            case .ended, .cancelled:
                onDrop()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Разрешаем UIScrollView параллельно получать касания: при движении пальца >12pt
            // лонгпресс мгновенно отменяется, и экран листается свободно.
            return true
        }
    }
}

private final class TouchForwardingView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        return super.hitTest(point, with: event)
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
