import SwiftUI

/// Uses the existing public tier_templates node; writes remain protected by
/// Firebase admin rules. User drafts/publications are independent copies.
struct AdminTierTemplatesView: View {
    @ObservedObject private var repo = TierListsRepository.shared
    @ObservedObject private var auth = AuthRepository.shared
    @State private var editing: TemplateEditSession?
    @State private var isLoading = true
    @State private var isDeleting = false
    @State private var error: String?

    var body: some View {
        List {
            if auth.isAdmin {
                Section {
                    Button {
                        editing = TemplateEditSession(original: nil)
                    } label: { Label("Новый шаблон", systemImage: "plus") }
                    .foregroundStyle(.primary)
                } footer: {
                    Text("Изменения доступны без обновления приложения. Созданные пользователями списки не изменятся.")
                }
                if isLoading && repo.templates.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Section("Шаблоны") {
                        if repo.templates.isEmpty { Text("Шаблонов пока нет").foregroundStyle(.secondary) }
                        ForEach(repo.templates) { template in
                            Button {
                                editing = TemplateEditSession(original: template)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(template.title).foregroundStyle(.primary)
                                    Text("\(template.items.count) фильмов · Приоритет \(template.priority ?? 0)")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    guard !isDeleting else { return }
                                    isDeleting = true
                                    Task {
                                        defer { isDeleting = false }
                                        do { try await repo.deleteTemplate(template) }
                                        catch { self.error = error.localizedDescription }
                                    }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
                if let message = repo.templatesError {
                    Section {
                        Text(message).foregroundStyle(.secondary)
                        Button("Повторить") { Task { await reload() } }
                    }
                }
            } else {
                Text("Доступно только администраторам").foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .disabled(isDeleting)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $editing, onDismiss: { Task { await reload() } }) { session in
            AdminTierTemplateEditor(original: session.original)
        }
        .alert("Не удалось выполнить действие", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func reload() async {
        guard auth.isAdmin else { isLoading = false; return }
        _ = await repo.fetchTemplates(force: true)
        isLoading = false
    }
}

private struct TemplateEditSession: Identifiable {
    let id = UUID()
    let original: TierTemplate?
}

private struct AdminTierTemplateEditor: View {
    let original: TierTemplate?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthRepository.shared
    @State private var value: TierTemplate
    @State private var initial: TierTemplate
    @State private var showPicker = false
    @State private var discardChanges = false
    @State private var isSaving = false
    @State private var error: String?

    init(original: TierTemplate?) {
        self.original = original
        let template = original ?? TierTemplate(id: UUID().uuidString, title: "", subtitle: nil, priority: 0, items: [])
        _value = State(initialValue: template)
        _initial = State(initialValue: template)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Название и описание") {
                    TextField("Название", text: $value.title)
                    TextField("Описание (необязательно)", text: Binding(get: { value.subtitle ?? "" }, set: { value.subtitle = $0.isEmpty ? nil : $0 }), axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Stepper("Приоритет: \(value.priority ?? 0)", value: Binding(get: { value.priority ?? 0 }, set: { value.priority = $0 }), in: -1000...1000)
                } footer: { Text("Чем выше приоритет, тем раньше шаблон в списке.") }
                Section {
                    Button { showPicker = true } label: { Label("Добавить фильмы", systemImage: "plus") }
                        .foregroundStyle(.primary)
                    ForEach(value.items) { item in
                        HStack(spacing: 12) {
                            AsyncCachedImage(url: item.resolvedPosterURL.flatMap(URL.init(string:))) {
                                Rectangle().fill(Color.secondary.opacity(0.15))
                            } content: { image in
                                Image(uiImage: image).resizable().scaledToFill()
                            }
                            .frame(width: 34, height: 51).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).lineLimit(2)
                                if let year = item.year { Text(String(year)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .onDelete { value.items.remove(atOffsets: $0) }
                    .onMove { value.items.move(fromOffsets: $0, toOffset: $1) }
                    .tint(.red)
                } header: { Text("Фильмы: \(value.items.count)") }
                footer: { Text("Не менее четырёх. Первые четыре постера формируют обложку; порядок меняется за ручку справа.") }
            }
            .environment(\.editMode, .constant(.active))
            .disabled(isSaving || !auth.isAdmin)
            .navigationTitle(original == nil ? "Новый шаблон" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        if value != initial { discardChanges = true } else { dismiss() }
                    }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Сохранить") }
                    }
                    .disabled(isSaving || !auth.isAdmin || value == initial)
                }
            }
            .sheet(isPresented: $showPicker) {
                TierItemPickerSheet(existingIds: Set(value.items.map(\.mediaId)), onAdd: { items in
                    var known = Set(value.items.map(\.mediaId))
                    value.items.append(contentsOf: items.filter { known.insert($0.mediaId).inserted })
                }, onDismiss: { showPicker = false })
            }
            .confirmationDialog("Отменить изменения?", isPresented: $discardChanges, titleVisibility: .visible) {
                Button("Не сохранять", role: .destructive) { dismiss() }
                Button("Продолжить редактирование", role: .cancel) {}
            }
            .alert("Не удалось сохранить шаблон", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Понятно", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
        .interactiveDismissDisabled(isSaving || value != initial)
    }

    private func save() async {
        guard !isSaving else { return }
        if let message = value.validationMessage { error = message; return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await TierListsRepository.shared.saveTemplate(value, expected: original)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
