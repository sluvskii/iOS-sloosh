import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drag payload

/// Перетаскиваемый айтем доски. JSON-представление достаточно для того,
/// чтобы дроп-зона поняла, какой фильм и откуда переносится.
struct TierDragPayload: Codable, Transferable {
    var item: TierListItem
    var sourceRowId: String? // nil = пул «Не распределено»

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

// MARK: - Board

/// Доска тир-листа: строки уровней с цветными чипами + сетки постеров + пул
/// «Не распределено». Один компонент на оба режима: в `edit` работает
/// drag&drop и меню айтемов, в `view` постеры просто открывают фильм.
struct TierListBoardView: View {
    enum Mode { case edit, view }

    let mode: Mode
    @Binding var rows: [TierRow]
    @Binding var unranked: [TierListItem]
    var onTapItem: ((TierListItem) -> Void)?
    var onOpenDetails: ((TierListItem) -> Void)?
    var onRemoveItem: ((TierListItem, String?) -> Void)?

    @State private var highlightedRowId: String?
    @State private var movingItem: TierListItem?

    private let posterWidth: CGFloat = 86
    private let posterHeight: CGFloat = 129

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($rows) { $row in
                tierRow(row: $row)
            }
            if mode == .edit || !unranked.isEmpty {
                unrankedRow
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Строка уровня

    @ViewBuilder
    private func tierRow(row: Binding<TierRow>) -> some View {
        HStack(alignment: .top, spacing: 0) {
            chip(for: row.wrappedValue)
                .frame(width: 92)

            itemsArea(rowId: row.wrappedValue.id, items: Binding(
                get: { row.wrappedValue.items },
                set: { row.wrappedValue.items = $0 }
            ))
            .frame(minHeight: 96)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    highlightedRowId == row.wrappedValue.id ? Color.slooshAccent : Color.clear,
                    lineWidth: 2
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .dropDestination(for: TierDragPayload.self) { payload, _ in
            guard let payload = payload.first else { return false }
            moveItem(payload: payload, targetRowId: row.wrappedValue.id)
            return true
        } isTargeted: { targeted in
            highlightedRowId = targeted ? row.wrappedValue.id : nil
        }
    }

    private func chip(for row: TierRow) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [row.color, row.color.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(row.label)
                .font(.system(size: 26, weight: .heavy, design: .default))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .minimumScaleFactor(0.4)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
    }

    // MARK: Сетки айтемов

    @ViewBuilder
    private func itemsArea(rowId: String, items: Binding<[TierListItem]>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) {
                if items.wrappedValue.isEmpty && rowId != "__pool__" {
                    Text("Перетащите фильмы сюда")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 12)
                }
                ForEach(items.wrappedValue) { item in
                    itemCell(item: item, sourceRowId: rowId == "__pool__" ? nil : rowId)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .dropDestination(for: TierDragPayload.self) { payload, _ in
            guard let payload = payload.first else { return false }
            moveItem(payload: payload, targetRowId: rowId == "__pool__" ? nil : rowId)
            return true
        } isTargeted: { targeted in
            if rowId != "__pool__" { highlightedRowId = targeted ? rowId : nil }
        }
    }

    private var unrankedRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Не распределено (\(unranked.count))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 18)

            itemsArea(rowId: "__pool__", items: $unranked)
                .frame(minHeight: 96)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            highlightedRowId == "__pool__" ? Color.slooshAccent : Color.clear,
                            lineWidth: 2
                        )
                )
        }
    }

    // MARK: Ячейка постера

    @ViewBuilder
    private func itemCell(item: TierListItem, sourceRowId: String?) -> some View {
        let cell = AsyncCachedImage(
            url: item.posterUrl.flatMap { URL(string: $0) },
            placeholder: {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
            },
            content: { image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            },
            fallback: {
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.08))
                    Text(String(item.title.prefix(1)))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        )
        .frame(width: posterWidth, height: posterHeight)
        .clipShape(RoundedRectangle(cornerRadius: 8))

        Group {
            if mode == .edit {
                cell
                    .draggable(TierDragPayload(item: item, sourceRowId: sourceRowId)) {
                        cell.overlay(alignment: .topTrailing) {
                            Image(systemName: "cursor.rays")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(4)
                                .background(Circle().fill(Color.black.opacity(0.45)))
                                .padding(4)
                                .opacity(0.9)
                        }
                    }
                    .onTapGesture { onTapItem?(item) }
            } else {
                cell
                    .onTapGesture { onOpenDetails?(item) }
            }
        }
    }

    // MARK: Перенос

    private func moveItem(payload: TierDragPayload, targetRowId: String?) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            // Удаляем из источника
            if let sourceId = payload.sourceRowId,
               let index = rows.firstIndex(where: { $0.id == sourceId }) {
                rows[index].items.removeAll { $0.mediaId == payload.item.mediaId }
            } else {
                unranked.removeAll { $0.mediaId == payload.item.mediaId }
            }
            // Вставляем в цель
            if let targetId = targetRowId,
               let index = rows.firstIndex(where: { $0.id == targetId }) {
                rows[index].items.append(payload.item)
            } else {
                unranked.append(payload.item)
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - Палитра уровней (как у tiermaker)

enum TierRowPalette {
    static let colors: [(name: String, hex: String)] = [
        ("Красный", "FF7F7F"), ("Оранжевый", "FFBF7F"), ("Жёлтый", "FFDF7F"),
        ("Жёлто-зелёный", "FFFF7F"), ("Салатовый", "BFFF7F"), ("Зелёный", "7FFF7F"),
        ("Бирюзовый", "7FFFFF"), ("Голубой", "7FBFFF"), ("Синий", "7F7FFF"),
        ("Фиолетовый", "BF7FFF"), ("Розовый", "FF7FFF"), ("Серый", "BFBFBF")
    ]
}

// MARK: - Общая тема экранов тир-листов

enum TierListTheme {
    static let background = Color(red: 0.04, green: 0.055, blue: 0.048, opacity: 1)
}
