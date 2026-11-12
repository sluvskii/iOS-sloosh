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
/// Стиль — нативный: systemBackground, системные плейсхолдеры, adaptive light/dark.
struct TierListBoardView: View {
    enum Mode { case edit, view }

    let mode: Mode
    @Binding var rows: [TierRow]
    @Binding var unranked: [TierListItem]
    var onTapItem: ((TierListItem) -> Void)?
    var onOpenDetails: ((TierListItem) -> Void)?

    @State private var highlightedRowId: String?

    private let posterWidth: CGFloat = 82
    private let posterHeight: CGFloat = 123
    private let rowHeight: CGFloat = 143

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        HStack(alignment: .center, spacing: 0) {
            chip(for: row.wrappedValue)
                .frame(width: 92, height: rowHeight)

            itemsArea(rowId: row.wrappedValue.id, items: Binding(
                get: { row.wrappedValue.items },
                set: { row.wrappedValue.items = $0 }
            ))
        }
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemFill).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    highlightedRowId == row.wrappedValue.id ? Color.slooshAccent : Color.clear,
                    lineWidth: 2
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
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
            LinearGradient(
                colors: [row.color, row.color.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(row.label)
                .font(.system(size: 24, weight: .heavy, design: .default))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .minimumScaleFactor(0.4)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Сетки айтемов

    @ViewBuilder
    private func itemsArea(rowId: String, items: Binding<[TierListItem]>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                if items.wrappedValue.isEmpty {
                    Text(rowId == "__pool__" ? "Добавьте фильмы вниз" : "Перетащите фильмы сюда")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                }
                ForEach(items.wrappedValue) { item in
                    itemCell(item: item, sourceRowId: rowId == "__pool__" ? nil : rowId)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: TierDragPayload.self) { payload, _ in
            guard let payload = payload.first else { return false }
            moveItem(payload: payload, targetRowId: rowId == "__pool__" ? nil : rowId)
            return true
        } isTargeted: { targeted in
            if rowId != "__pool__" { highlightedRowId = targeted ? rowId : nil }
        }
    }

    private var unrankedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Не распределено (\(unranked.count))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)

            itemsArea(rowId: "__pool__", items: $unranked)
                .frame(height: rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(UIColor.secondarySystemFill).opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
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
        let poster = AsyncCachedImage(
            url: item.posterUrl.flatMap { URL(string: $0) },
            placeholder: {
                Rectangle()
                    .fill(Color(UIColor.tertiarySystemFill))
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
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        )
        .frame(width: posterWidth, height: posterHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

        Group {
            if mode == .edit {
                poster
                    .draggable(TierDragPayload(item: item, sourceRowId: sourceRowId))
                    .onTapGesture { onTapItem?(item) }
            } else {
                poster
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
