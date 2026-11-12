import SwiftUI

/// Редактор тир-листа: доска с drag&drop, правка уровней, пул «Не распределено»,
/// добавление фильмов, автосохранение черновика и публикация. Нативный стиль.
struct TierListEditorView: View {
    /// Черновик (из шаблона, «Создать», ремикса или «В тир-лист» из карточки фильма).
    let draft: TierList
    var onPublished: (TierList) -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var subtitle: String
    @State private var rows: [TierRow]
    @State private var unranked: [TierListItem]
    @State private var showAddSheet = false
    @State private var showPublishSheet = false
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
        VStack(spacing: 0) {
            TextField("Название тир-листа", text: $title)
                .font(.system(size: 22, weight: .bold))
                .padding(.horizontal, 16)
                .padding(.top, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TierListBoardView(
                        mode: .edit,
                        rows: $rows,
                        unranked: $unranked,
                        onTapItem: { item in tappedItem = item }
                    )
                    .padding(.top, 8)

                    rowControls
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .safeAreaInset(edge: .top, spacing: 0) { editorHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) { editorBottomBar }
        .navigationTitle("Редактор")
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(UIColor.systemBackground))
        .fullWidthSwipeBack()
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
        .sheet(isPresented: $showPublishSheet) { publishSheet }
        .confirmationDialog(
            tappedItem?.title ?? "",
            isPresented: Binding(get: { tappedItem != nil }, set: { if !$0 { tappedItem = nil } }),
            titleVisibility: .visible
        ) {
            Button("Открыть фильм") {
                if let item = tappedItem { openDetails(item) }
                tappedItem = nil
            }
            Button("Переместить в «Не распределено»") {
                if let item = tappedItem { moveItemToPool(item) }
                tappedItem = nil
            }
            Button("Убрать из тир-листа", role: .destructive) {
                if let item = tappedItem { removeItem(item) }
                tappedItem = nil
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

    // MARK: Шапка и нижняя панель

    @ViewBuilder
    private var editorHeader: some View {
        ZStack {
            Text(draft.isDraftList ? "Новый тир-лист" : "Редактирование")
                .font(.system(size: 18, weight: .semibold))
                .backdropForeground()
            HStack {
                TelegramGlassIconButton(systemName: "xmark") {
                    autosaveDraft()
                    onDismiss()
                }
                Spacer()
                Button {
                    showPublishSheet = true
                } label: {
                    Text("Готово")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.slooshAccent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isPublishing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var editorBottomBar: some View {
        HStack(spacing: 10) {
            Button {
                showAddSheet = true
            } label: {
                Label("Добавить", systemImage: "plus.square.on.square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.secondarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                showPublishSheet = true
            } label: {
                Label("Опубликовать", systemImage: "paperplane.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.slooshAccent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(unranked.isEmpty && rows.allSatisfy { $0.items.isEmpty })
            .opacity(unranked.isEmpty && rows.allSatisfy { $0.items.isEmpty } ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Управление строками

    @ViewBuilder
    private var rowControls: some View {
        HStack(spacing: 10) {
            Button {
                rows.append(TierRow(
                    id: UUID().uuidString,
                    label: "",
                    colorHex: TierRowPalette.colors[rows.count % TierRowPalette.colors.count].hex,
                    items: []
                ))
            } label: {
                Label("Уровень", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemFill), in: Capsule())
            }
            .buttonStyle(.plain)
            Text("Тап по цветному чипу — название, цвет и порядок")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: Публикация

    @ViewBuilder
    private var publishSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Название")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Например: Все фильмы MCU — мой вердикт", text: $title)
                        .font(.system(size: 16, weight: .semibold))
                        .padding(12)
                        .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))

                    Text("Описание (необязательно)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("Пара слов о том, как вы оценивали", text: $subtitle)
                        .font(.system(size: 15))
                        .padding(12)
                        .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)

                if let error = publishError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }

                Spacer()

                Button {
                    Task { await publish() }
                } label: {
                    HStack {
                        if isPublishing { ProgressView().tint(.white) }
                        Text("Опубликовать")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.slooshAccent, in: Capsule())
                }
                .disabled(isPublishing || title.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .navigationTitle("Публикация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { showPublishSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func publish() async {
        isPublishing = true
        publishError = nil
        do {
            if let published = try await TierListsRepository.shared.publish(draftSnapshot) {
                deleteDraftLocally()
                showPublishSheet = false
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

    // MARK: Черновик

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

    // MARK: Операции с айтемами и строками

    private func openDetails(_ item: TierListItem) {
        autosaveDraft()
        DeepLinkManager.shared.handleURL(URL(string: "sloosh://details?id=\(item.mediaId)")!)
        dismiss()
    }

    private func moveItemToPool(_ item: TierListItem) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            for index in rows.indices { rows[index].items.removeAll { $0.mediaId == item.mediaId } }
            if !unranked.contains(where: { $0.mediaId == item.mediaId }) {
                unranked.append(item)
            }
        }
    }

    private func removeItem(_ item: TierListItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            for index in rows.indices { rows[index].items.removeAll { $0.mediaId == item.mediaId } }
            unranked.removeAll { $0.mediaId == item.mediaId }
        }
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

/// Обёртка для sheet(item:) по строке уровня.
private struct EditableRowBox: Identifiable {
    let row: TierRow
    var id: String { row.id }
}

/// Правка одного уровня: название, цвет, порядок, удаление.
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
            VStack(alignment: .leading, spacing: 16) {
                TextField("Название (например S, Шедевры, Провал)", text: $label)
                    .font(.system(size: 17, weight: .semibold))
                    .padding(12)
                    .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)

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
                .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    Button {
                        onSave(TierRow(id: row.id, label: label.isEmpty ? row.label : label, colorHex: colorHex, items: row.items), false, -1)
                    } label: {
                        Image(systemName: "arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Button {
                        onSave(TierRow(id: row.id, label: label.isEmpty ? row.label : label, colorHex: colorHex, items: row.items), false, 1)
                    } label: {
                        Image(systemName: "arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if canDelete {
                        Button(role: .destructive) {
                            onSave(row, true, 0)
                        } label: {
                            Image(systemName: "trash")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(.horizontal, 16)

                Button {
                    onSave(TierRow(id: row.id, label: label.isEmpty ? row.label : label, colorHex: colorHex, items: row.items), false, 0)
                } label: {
                    Text("Сохранить")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.slooshAccent, in: Capsule())
                }
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.top, 16)
            .navigationTitle("Уровень")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
