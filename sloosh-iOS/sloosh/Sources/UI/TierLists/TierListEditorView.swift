import SwiftUI

/// Редактор тир-листа: системный навбар («Готово»), доска уровней с drag&drop
/// и быстрым тапом для распределения, карточки в стиле Apple Design.
struct TierListEditorView: View {
    let draft: TierList
    var onPublished: (TierList) -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var subtitle: String
    @State private var rows: [TierRow]
    @State private var unranked: [TierListItem]
    @State private var showAddSheet = false
    @State private var showPublishField = false
    @State private var editingRow: TierRow?
    @State private var tappedItem: TierListItem?
    @State private var isPublishing = false
    @State private var isDraggingCard = false
    @State private var publishError: String?
    @State private var autosaveTask: Task<Void, Never>?

    init(draft: TierList, onPublished: @escaping (TierList) -> Void, onDismiss: @escaping () -> Void) {
        self.draft = draft
        self.onPublished = onPublished
        self.onDismiss = onDismiss
        _title = State(initialValue: draft.title)
        _subtitle = State(initialValue: draft.subtitle ?? "")
        _rows = State(initialValue: draft.rows.isEmpty ? TierRow.defaultRows() : draft.rows)
        _unranked = State(initialValue: draft.unranked)
    }

    private var draftSnapshot: TierList {
        var list = draft
        list.title = title.isEmpty ? "Без названия" : title
        list.subtitle = subtitle.isEmpty ? nil : subtitle
        list.rows = rows
        list.unranked = unranked
        return list
    }

    var body: some View {
        editorContent
            .navigationTitle("Редактор")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { showPublishField = true }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .disabled(isPublishing)
                }
            }
            .onDisappear { autosaveDraft() }
            .onChange(of: rows) { _, _ in scheduleAutosave() }
            .onChange(of: unranked) { _, _ in scheduleAutosave() }
            .onChange(of: title) { _, _ in scheduleAutosave() }
            .sheet(isPresented: $showAddSheet) { addSheet }
            .sheet(isPresented: $showPublishField) { publishSheet }
            .sheet(item: Binding(
                get: { editingRow.map { EditableRowBox(row: $0) } },
                set: { editingRow = $0?.row }
            )) { box in
                rowEditSheet(box: box)
            }
            .confirmationDialog(
                tappedItem?.title ?? "Действия с фильмом",
                isPresented: Binding(get: { tappedItem != nil }, set: { if !$0 { tappedItem = nil } }),
                titleVisibility: .visible
            ) {
                itemActionsDialog
            } message: {
                if let item = tappedItem {
                    Text(currentLocationDescription(for: item))
                }
            }
    }

    // MARK: - Контент редактора

    @ViewBuilder
    private var editorContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerInputSection

                    boardSection(scrollProxy: scrollProxy)

                    addRowButton

                    editorFooterHint
                }
            }
            .scrollClipDisabled()
            .scrollDisabled(isDraggingCard)
        }
    }

    @ViewBuilder
    private var headerInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Название тир-листа", text: $title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)

            Divider()
                .opacity(0.35)

            TextField("Описание (необязательно)", text: $subtitle, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1...3)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .id("__top__")
    }

    @ViewBuilder
    private func boardSection(scrollProxy: ScrollViewProxy) -> some View {
        TierListBoardView(
            mode: .edit,
            rows: $rows,
            unranked: $unranked,
            isDraggingActive: $isDraggingCard,
            onTapItem: { item in tappedItem = item },
            onTapRow: { row in editingRow = row },
            onAddMovies: { showAddSheet = true },
            onScrollRequest: { targetId in
                withAnimation(.easeInOut(duration: 0.28)) {
                    scrollProxy.scrollTo(targetId, anchor: .center)
                }
            }
        )
        .padding(.top, 4)
    }

    @ViewBuilder
    private var addRowButton: some View {
        Button {
            addNewRow()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Добавить уровень")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var editorFooterHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.footnote)
            Text("Зажмите карточку для переноса. Тап — быстрое меню действий.")
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Диалог действий с фильмом

    @ViewBuilder
    private var itemActionsDialog: some View {
        if let item = tappedItem {
            itemReorderActions(for: item)
            itemTierMoveActions(for: item)
            itemGeneralActions(for: item)
        }
        Button("Отмена", role: .cancel) {
            tappedItem = nil
        }
    }

    @ViewBuilder
    private func itemReorderActions(for item: TierListItem) -> some View {
        if canMoveLeft(item) {
            Button("Сдвинуть влево") {
                moveItemLeft(item)
                tappedItem = nil
            }
        }
        if canMoveRight(item) {
            Button("Сдвинуть вправо") {
                moveItemRight(item)
                tappedItem = nil
            }
        }
    }

    @ViewBuilder
    private func itemTierMoveActions(for item: TierListItem) -> some View {
        ForEach(rows) { row in
            let isCurrentRow = row.items.contains(where: { $0.mediaId == item.mediaId })
            if !isCurrentRow {
                let trimmed = row.label.trimmingCharacters(in: .whitespaces)
                let rowTitle = trimmed.isEmpty ? "Без названия" : trimmed
                Button("В уровень «\(rowTitle)»") {
                    moveItem(item, toRowId: row.id)
                    tappedItem = nil
                }
            }
        }
        let isInPool = unranked.contains(where: { $0.mediaId == item.mediaId })
        if !isInPool {
            Button("В «Не распределено»") {
                moveItemToPool(item)
                tappedItem = nil
            }
        }
    }

    @ViewBuilder
    private func itemGeneralActions(for item: TierListItem) -> some View {
        Button("Открыть фильм") {
            openDetails(item)
            tappedItem = nil
        }
        Button("Убрать из тир-листа", role: .destructive) {
            removeItem(item)
            tappedItem = nil
        }
    }

    private func currentLocationDescription(for item: TierListItem) -> String {
        for row in rows {
            if row.items.contains(where: { $0.mediaId == item.mediaId }) {
                let trimmed = row.label.trimmingCharacters(in: .whitespaces)
                let name = trimmed.isEmpty ? "Без названия" : trimmed
                return "Текущий уровень: «\(name)»"
            }
        }
        if unranked.contains(where: { $0.mediaId == item.mediaId }) {
            return "Текущий уровень: «Не распределено»"
        }
        return ""
    }

    // MARK: - Диалоги и шторки

    @ViewBuilder
    private var addSheet: some View {
        TierItemPickerSheet(
            onAdd: { items in
                var known = Set(unranked.map(\.mediaId))
                rows.forEach { row in row.items.forEach { known.insert($0.mediaId) } }
                let fresh = items.filter { !known.contains($0.mediaId) }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    unranked.append(contentsOf: fresh)
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            },
            onDismiss: { showAddSheet = false }
        )
    }

    @ViewBuilder
    private func rowEditSheet(box: EditableRowBox) -> some View {
        TierRowEditSheet(
            row: box.row,
            canDelete: rows.count > 1,
            onSave: { updated, deleted, moveDirection in
                applyRowEdit(updated: updated, deleted: deleted, move: moveDirection)
                editingRow = nil
            }
        )
    }

    // MARK: - Публикация

    @ViewBuilder
    private var publishSheet: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например: Все фильмы MCU — мой вердикт", text: $title)
                }
                Section("Описание") {
                    TextField("Пара слов (необязательно)", text: $subtitle, axis: .vertical)
                        .lineLimit(1...4)
                }
                if let error = publishError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section {
                    Button {
                        Task { await publish() }
                    } label: {
                        HStack {
                            if isPublishing { ProgressView() }
                            Text("Опубликовать")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isPublishing || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Публикация")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { showPublishField = false }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Опубликовать") {
                        Task { await publish() }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.slooshAccent)
                    .disabled(isPublishing || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func publish() async {
        isPublishing = true
        publishError = nil
        do {
            if let published = try await TierListsRepository.shared.publish(draftSnapshot) {
                deleteDraftLocally()
                showPublishField = false
                onPublished(published)
                dismiss()
            } else {
                publishError = "Нужно войти в аккаунт"
            }
        } catch {
            publishError = "Не удалось опубликовать: \(error.localizedDescription)"
        }
        isPublishing = false
    }

    // MARK: - Перемещение и действия

    private func canMoveLeft(_ item: TierListItem) -> Bool {
        for row in rows {
            if let index = row.items.firstIndex(where: { $0.mediaId == item.mediaId }) {
                return index > 0
            }
        }
        if let index = unranked.firstIndex(where: { $0.mediaId == item.mediaId }) {
            return index > 0
        }
        return false
    }

    private func canMoveRight(_ item: TierListItem) -> Bool {
        for row in rows {
            if let index = row.items.firstIndex(where: { $0.mediaId == item.mediaId }) {
                return index < row.items.count - 1
            }
        }
        if let index = unranked.firstIndex(where: { $0.mediaId == item.mediaId }) {
            return index < unranked.count - 1
        }
        return false
    }

    private func moveItemLeft(_ item: TierListItem) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            for rowIndex in rows.indices {
                if let itemIndex = rows[rowIndex].items.firstIndex(where: { $0.mediaId == item.mediaId }), itemIndex > 0 {
                    rows[rowIndex].items.swapAt(itemIndex, itemIndex - 1)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    return
                }
            }
            if let itemIndex = unranked.firstIndex(where: { $0.mediaId == item.mediaId }), itemIndex > 0 {
                unranked.swapAt(itemIndex, itemIndex - 1)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    private func moveItemRight(_ item: TierListItem) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            for rowIndex in rows.indices {
                if let itemIndex = rows[rowIndex].items.firstIndex(where: { $0.mediaId == item.mediaId }),
                   itemIndex < rows[rowIndex].items.count - 1 {
                    rows[rowIndex].items.swapAt(itemIndex, itemIndex + 1)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    return
                }
            }
            if let itemIndex = unranked.firstIndex(where: { $0.mediaId == item.mediaId }),
               itemIndex < unranked.count - 1 {
                unranked.swapAt(itemIndex, itemIndex + 1)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    private func moveItem(_ item: TierListItem, toRowId: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            for index in rows.indices {
                rows[index].items.removeAll { $0.mediaId == item.mediaId }
            }
            unranked.removeAll { $0.mediaId == item.mediaId }
            if let targetIndex = rows.firstIndex(where: { $0.id == toRowId }) {
                rows[targetIndex].items.append(item)
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func moveItemToPool(_ item: TierListItem) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            for index in rows.indices { rows[index].items.removeAll { $0.mediaId == item.mediaId } }
            if !unranked.contains(where: { $0.mediaId == item.mediaId }) {
                unranked.append(item)
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func removeItem(_ item: TierListItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            for index in rows.indices { rows[index].items.removeAll { $0.mediaId == item.mediaId } }
            unranked.removeAll { $0.mediaId == item.mediaId }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func addNewRow() {
        let label = suggestNextRowLabel()
        let color = TierRowPalette.colors[rows.count % TierRowPalette.colors.count].hex
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            rows.append(TierRow(
                id: UUID().uuidString,
                label: label,
                colorHex: color,
                items: []
            ))
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func suggestNextRowLabel() -> String {
        let candidates = ["S", "A", "B", "C", "D", "E", "F"]
        let existing = Set(rows.map { $0.label.trimmingCharacters(in: .whitespaces).uppercased() })
        for candidate in candidates {
            if !existing.contains(candidate) {
                return candidate
            }
        }
        return "Tier \(rows.count + 1)"
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            autosaveDraft()
        }
    }

    private func autosaveDraft() {
        TierListsRepository.shared.saveDraft(draftSnapshot)
    }

    private func deleteDraftLocally() {
        TierListsRepository.shared.deleteDraft(id: draft.id)
    }

    private func openDetails(_ item: TierListItem) {
        autosaveDraft()
        DeepLinkManager.shared.handleURL(URL(string: "sloosh://details?id=\(item.mediaId)")!)
        dismiss()
    }

    private func applyRowEdit(updated: TierRow, deleted: Bool, move: Int) {
        guard let index = rows.firstIndex(where: { $0.id == updated.id }) else { return }
        if deleted {
            if rows.count > 1 {
                unranked.append(contentsOf: rows[index].items)
                rows.remove(at: index)
            }
        } else {
            rows[index] = updated
            let newIndex = index + move
            if move != 0, rows.indices.contains(newIndex) {
                rows.swapAt(index, newIndex)
            }
        }
    }
}

private struct EditableRowBox: Identifiable {
    let row: TierRow
    var id: String { row.id }
}

/// Правка уровня: название, цвет, порядок, удаление — обычная Form.
struct TierRowEditSheet: View {
    let row: TierRow
    let canDelete: Bool
    var onSave: (TierRow, Bool, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var colorHex: String

    init(row: TierRow, canDelete: Bool, onSave: @escaping (TierRow, Bool, Int) -> Void) {
        self.row = row
        self.canDelete = canDelete
        self.onSave = onSave
        _label = State(initialValue: row.label)
        _colorHex = State(initialValue: row.colorHex)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название уровня") {
                    TextField("Например S, Шедевры, Провал", text: $label)
                }
                Section("Цвет") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 10)], spacing: 10) {
                        ForEach(TierRowPalette.colors, id: \.hex) { palette in
                            Button {
                                colorHex = palette.hex
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(UIColor(hex: palette.hex) ?? .systemGray))
                                    .frame(height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(colorHex == palette.hex ? Color.primary : .clear, lineWidth: 2.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    Button("Поднять") {
                        onSave(TierRow(id: row.id, label: label, colorHex: colorHex, items: row.items), false, -1)
                        dismiss()
                    }
                    .foregroundStyle(.primary)

                    Button("Опустить") {
                        onSave(TierRow(id: row.id, label: label, colorHex: colorHex, items: row.items), false, 1)
                        dismiss()
                    }
                    .foregroundStyle(.primary)

                    if canDelete {
                        Button("Удалить уровень", role: .destructive) {
                            onSave(row, true, 0)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Уровень")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сохранить") {
                        onSave(TierRow(id: row.id, label: label.isEmpty ? row.label : label, colorHex: colorHex, items: row.items), false, 0)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
