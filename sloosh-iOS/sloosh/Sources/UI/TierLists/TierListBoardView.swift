import SwiftUI
import UniformTypeIdentifiers

/// Перетаскиваемый айтем доски.
struct TierDragPayload: Codable, Transferable {
    var item: TierListItem
    var sourceRowId: String? // nil = пул «Не распределено»

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// Доска тир-листа: компактные цветные чипы уровней + обтекаемая сетка постеров,
/// идеально оптимизированная под экраны телефонов (375–430 pt).
/// Поддерживает как Drag & Drop, так и мгновенное перемещение тапом.
struct TierListBoardView: View {
    enum Mode { case edit, view }

    let mode: Mode
    @Binding var rows: [TierRow]
    @Binding var unranked: [TierListItem]
    var onTapItem: ((TierListItem) -> Void)?
    var onTapRow: ((TierRow) -> Void)?
    var onAddMovies: (() -> Void)?
    var onOpenDetails: ((TierListItem) -> Void)?

    @State private var highlightedRowId: String?

    // Оптимизированные мобильные габариты (помещается 4 постера в ряд на любом iPhone)
    private let posterWidth: CGFloat = 66
    private let posterHeight: CGFloat = 98
    private let chipWidth: CGFloat = 48

    var body: some View {
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
        HStack(alignment: .top, spacing: 8) {
            chip(row: row.wrappedValue)

            itemsGrid(rowId: row.wrappedValue.id, items: Binding(
                get: { row.wrappedValue.items },
                set: { row.wrappedValue.items = $0 }
            ))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(UIColor.secondarySystemFill).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    highlightedRowId == row.wrappedValue.id ? Color.primary.opacity(0.45) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .dropDestination(for: TierDragPayload.self) { payload, _ in
            guard let payload = payload.first else { return false }
            moveItem(payload: payload, targetRowId: row.wrappedValue.id)
            return true
        } isTargeted: { targeted in
            highlightedRowId = targeted ? row.wrappedValue.id : nil
        }
    }

    private func chip(row: TierRow) -> some View {
        Button {
            if mode == .edit {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onTapRow?(row)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(UIColor(hex: row.colorHex) ?? .systemGray),
                                Color(UIColor(hex: row.colorHex) ?? .systemGray).opacity(0.8)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(row.label)
                    .font(.system(size: 19, weight: .heavy, design: .default))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                    .minimumScaleFactor(0.35)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 3)
            }
            .frame(width: chipWidth, height: posterHeight)
        }
        .buttonStyle(.plain)
        .disabled(mode != .edit)
    }

    // MARK: - Сетки айтемов

    @ViewBuilder
    private func itemsGrid(rowId: String, items: Binding<[TierListItem]>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: posterWidth), spacing: 6)], spacing: 6) {
            if items.wrappedValue.isEmpty {
                Text(rowId == "__pool__" ? "Добавленные фильмы появятся здесь" : "Перетащите фильмы сюда")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: posterHeight)
            }
            ForEach(items.wrappedValue) { item in
                itemCell(item: item, sourceRowId: rowId == "__pool__" ? nil : rowId)
            }
        }
        .frame(maxWidth: .infinity, minHeight: posterHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .dropDestination(for: TierDragPayload.self) { payload, _ in
            guard let payload = payload.first else { return false }
            moveItem(payload: payload, targetRowId: rowId == "__pool__" ? nil : rowId)
            return true
        } isTargeted: { targeted in
            if rowId != "__pool__" { highlightedRowId = targeted ? rowId : nil }
        }
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
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Добавить")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(UIColor.secondarySystemFill))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            if unranked.isEmpty && mode == .edit {
                Button {
                    onAddMovies?()
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                        Text("Добавить фильмы в тир-лист")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Поиск по каталогу, подборкам и избранному")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(UIColor.separator), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
                }
                .buttonStyle(.plain)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(UIColor.tertiarySystemFill))
                        Text("?")
                            .font(.system(size: 19, weight: .heavy))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: chipWidth, height: posterHeight)

                    itemsGrid(rowId: "__pool__", items: $unranked)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(UIColor.secondarySystemFill).opacity(0.35))
                )
            }
        }
    }

    // MARK: - Ячейка постера

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
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
        )
        .frame(width: posterWidth, height: posterHeight)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())

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

    // MARK: - Перенос айтема

    private func moveItem(payload: TierDragPayload, targetRowId: String?) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            if let sourceId = payload.sourceRowId,
               let index = rows.firstIndex(where: { $0.id == sourceId }) {
                rows[index].items.removeAll { $0.mediaId == payload.item.mediaId }
            } else {
                unranked.removeAll { $0.mediaId == payload.item.mediaId }
            }
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
