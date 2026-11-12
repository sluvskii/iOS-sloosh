import SwiftUI

/// Редактор тир-листа: системный навбар («Готово»), доска уровней с drag&drop
/// и быстрым тапом для распределения, плавающая кнопка добавления фильмов.
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Название", text: $title)
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                TextField("Описание (необязательно)", text: $subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                TierListBoardView(
                    mode: .edit,
                    rows: $rows,
                    unranked: $unranked,
                    onTapItem: { item in tappedItem = item },
                    onTapRow: { row in editingRow = row },
                    onAddMovies: { showAddSheet = true }
                )
                .padding(.top, 4)

                Button {
                    rows.append(TierRow(
                        id: UUID().uuidString,
                        label: "",
                        colorHex: TierRowPalette.colors[rows.count % TierRowPalette.colors.count].hex,
                        items: []
                    ))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Добавить уровень")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemFill))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Text("Тап по фильму — быстро переместить по уровням. Тап по уровню — изменить название и цвет.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 60) // Запас под плавающую кнопку снизу
            }
        }
        .navigationTitle("Редактор")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Готово") { showPublishField = true }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .disabled(isPublishing)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("Добавить фильмы")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color(UIColor.separator).opacity(0.6), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color(UIColor.systemBackground).opacity(0), Color(UIColor.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
        .onDisappear { autosaveDraft() }
        .onChange(of: rows) { _, _ in scheduleAutosave() }
        .onChange(of: unranked) { _, _ in scheduleAutosave() }
        .onChange(of: title) { _, _ in scheduleAutosave() }
        .sheet(isPresented: $showAddSheet) {
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
        .sheet(isPresented: $showPublishField) { publishSheet }
        .confirmationDialog(
            tappedItem?.title ?? "",
            isPresented: Binding(get: { tappedItem != nil }, set: { if !$0 { tappedItem = nil } }),
            titleVisibility: .visible
        ) {
            if let item = tappedItem {
                // Быстрый перевод в любой уровень в 1 тап
                ForEach(rows) { row in
                    let isCurrentRow = row.items.contains(where: { $0.mediaId == item.mediaId })
                    if !isCurrentRow {
                        Button("В уровень «\(row.label)»") {
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
                Button("Открыть фильм") {
                    openDetails(item)
                    tappedItem = nil
                }
                Button("Убрать из тир-листа", role: .destructive) {
                    removeItem(item)
                    tappedItem = nil
                }
            }
            Button("Отмена", role: .cancel) { tappedItem = nil }
        }
        .sheet(item: Binding(
            get: { editingRow.map { EditableRowBox(row: $0) } },
            set: { editingRow = $0?.row }
        )) { box in
            TierRowEditSheet(
                row: box.row,
                canDelete: rows.count > 1,
                onSave: { updated, deleted, moveDirection in
                    applyRowEdit(updated: updated, deleted: deleted, move: moveDirection)
                    editingRow = nil
                }
            )
        }
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
                    TextField("Пара слов (необязательно)", text: $subtitle)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { showPublishField = false }
                        .foregroundStyle(.primary)
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

    // MARK: - Перемещение и черновик

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
            .toolbar {
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
