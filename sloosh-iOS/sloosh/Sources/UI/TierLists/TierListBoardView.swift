import SwiftUI

/// Геометрия строк и ячеек для интерактивного пространственного перемещения.
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
/// Поддерживает плавное физическое перетаскивание карточек с динамической подстройкой
/// соседних постеров (пружинный сдвиг), тактильной отдачей и быстрым тапом для меню.
struct TierListBoardView: View {
    enum Mode { case edit, view }

    let mode: Mode
    @Binding var rows: [TierRow]
    @Binding var unranked: [TierListItem]
    var onTapItem: ((TierListItem) -> Void)?
    var onTapRow: ((TierRow) -> Void)?
    var onAddMovies: (() -> Void)?
    var onOpenDetails: ((TierListItem) -> Void)?

    // MARK: - Состояние интерактивного перетаскивания

    @State private var rowGeometries: [BoardRowGeometry] = []
    @State private var itemGeometries: [BoardItemGeometry] = []
    @State private var draggedItem: TierListItem?
    @State private var dragLocation: CGPoint = .zero
    @State private var isDragging = false
    @State private var highlightedRowId: String?

    private let coordinateSpaceName = "TierBoardCoordinateSpace"

    // Мобильные пропорции 2:3 (Apple TV постера)
    private let posterWidth: CGFloat = 66
    private let posterHeight: CGFloat = 98
    private let chipWidth: CGFloat = 52

    var body: some View {
        boardStack
            .coordinateSpace(name: coordinateSpaceName)
            .onPreferenceChange(BoardRowGeometryKey.self) { rowGeometries = $0 }
            .onPreferenceChange(BoardItemGeometryKey.self) { itemGeometries = $0 }
            .overlay { draggedCardOverlay }
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
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: BoardRowGeometryKey.self,
                    value: [BoardRowGeometry(rowId: row.wrappedValue.id, frame: geo.frame(in: .named(coordinateSpaceName)))]
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
                // Градиентная основа
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tierColor, tierColor.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Глянцевый блик сверху
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                // Внутренняя кайма
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)

                // Название уровня
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
        LazyVGrid(columns: [GridItem(.adaptive(minimum: posterWidth), spacing: 6)], spacing: 6) {
            if items.isEmpty {
                emptyRowPlaceholder(isPool: rowId == "__pool__")
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
        let isCurrentDragged = isDragging && draggedItem?.mediaId == item.mediaId

        let content = ZStack {
            if isCurrentDragged {
                placeholderSlot
            } else {
                itemCard(item: item, isLifted: false)
            }
        }
        .frame(width: posterWidth, height: posterHeight)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: BoardItemGeometryKey.self,
                    value: [BoardItemGeometry(
                        mediaId: item.mediaId,
                        rowId: sourceRowId,
                        index: index,
                        frame: geo.frame(in: .named(coordinateSpaceName))
                    )]
                )
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if mode == .edit {
                onTapItem?(item)
            } else {
                onOpenDetails?(item)
            }
        }

        Group {
            if mode == .edit {
                content
                    .gesture(dragGesture(for: item, sourceRowId: sourceRowId))
            } else {
                content
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
                .strokeBorder(isLifted ? Color.white.opacity(0.35) : Color.white.opacity(0.1), lineWidth: isLifted ? 1.0 : 0.5)
        )
        .shadow(color: Color.black.opacity(isLifted ? 0.45 : 0.2), radius: isLifted ? 12 : 3, y: isLifted ? 8 : 1.5)
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
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 14, weight: .semibold))
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
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: BoardRowGeometryKey.self,
                            value: [BoardRowGeometry(rowId: "__pool__", frame: geo.frame(in: .named(coordinateSpaceName)))]
                        )
                    }
                )
            }
        }
    }

    // MARK: - Поднятая карточка под пальцем (Overlay)

    @ViewBuilder
    private var draggedCardOverlay: some View {
        if isDragging, let item = draggedItem {
            itemCard(item: item, isLifted: true)
                .scaleEffect(1.08)
                .rotationEffect(.degrees(2.0))
                .shadow(color: Color.black.opacity(0.55), radius: 20, x: 0, y: 12)
                .position(x: dragLocation.x, y: dragLocation.y - 10)
                .transition(.identity)
                .zIndex(999)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Жест перетаскивания

    private func dragGesture(for item: TierListItem, sourceRowId: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.16)
            .sequenced(before: DragGesture(coordinateSpace: .named(coordinateSpaceName)))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if let drag = drag {
                        if !isDragging {
                            startDragging(item: item, sourceRowId: sourceRowId, location: drag.startLocation)
                        }
                        handleDragMoved(location: drag.location)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                if isDragging {
                    handleDragEnded()
                }
            }
    }

    private func startDragging(item: TierListItem, sourceRowId: String, location: CGPoint) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
            draggedItem = item
            dragLocation = location
            isDragging = true
            highlightedRowId = sourceRowId
        }
    }

    private func handleDragMoved(location: CGPoint) {
        dragLocation = location
        guard let dragged = draggedItem else { return }

        // 1. Находим целевую строку по положению пальца
        guard let targetRow = findTargetRow(at: location) else { return }

        // 2. Находим целевой индекс внутри этой строки
        let targetIndex = findTargetIndex(in: targetRow.rowId, at: location)

        // 3. Сверяем с текущим положением
        let currRowId = currentRowId(for: dragged.mediaId)
        let currIndex = currRowId != nil ? currentIndex(for: dragged.mediaId, in: currRowId!) : nil

        if targetRow.rowId != currRowId || (currIndex != nil && targetIndex != currIndex!) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                performLiveMove(item: dragged, toRowId: targetRow.rowId, toIndex: targetIndex)
                highlightedRowId = targetRow.rowId
            }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func handleDragEnded() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            isDragging = false
            draggedItem = nil
            highlightedRowId = nil
        }
    }

    // MARK: - Геометрические вычисления

    private func findTargetRow(at location: CGPoint) -> BoardRowGeometry? {
        if rowGeometries.isEmpty { return nil }
        // Точное попадание по вертикали
        if let exact = rowGeometries.first(where: {
            location.y >= ($0.frame.minY - 8) && location.y <= ($0.frame.maxY + 8)
        }) {
            return exact
        }
        // Ближайшая строка по расстоянию
        return rowGeometries.min(by: { abs($0.frame.midY - location.y) < abs($1.frame.midY - location.y) })
    }

    private func findTargetIndex(in rowId: String, at location: CGPoint) -> Int {
        let items = itemGeometries
            .filter { $0.rowId == rowId }
            .sorted {
                if abs($0.frame.midY - $1.frame.midY) > 20 {
                    return $0.frame.midY < $1.frame.midY
                }
                return $0.frame.midX < $1.frame.midX
            }

        if items.isEmpty { return 0 }

        for (idx, itemGeo) in items.enumerated() {
            if location.y < (itemGeo.frame.minY - 4) {
                return idx
            }
            if location.y <= (itemGeo.frame.maxY + 10) {
                if location.x < itemGeo.frame.midX {
                    return idx
                }
            }
        }
        return items.count
    }

    private func currentRowId(for mediaId: String) -> String? {
        if unranked.contains(where: { $0.mediaId == mediaId }) {
            return "__pool__"
        }
        for row in rows {
            if row.items.contains(where: { $0.mediaId == mediaId }) {
                return row.id
            }
        }
        return nil
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

    private func performLiveMove(item: TierListItem, toRowId: String, toIndex: Int) {
        // Удаляем из текущей позиции
        for rIndex in rows.indices {
            rows[rIndex].items.removeAll { $0.mediaId == item.mediaId }
        }
        unranked.removeAll { $0.mediaId == item.mediaId }

        // Вставляем в целевую позицию
        if toRowId == "__pool__" {
            let safeIndex = max(0, min(toIndex, unranked.count))
            unranked.insert(item, at: safeIndex)
        } else if let rIndex = rows.firstIndex(where: { $0.id == toRowId }) {
            let safeIndex = max(0, min(toIndex, rows[rIndex].items.count))
            rows[rIndex].items.insert(item, at: safeIndex)
        }
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
