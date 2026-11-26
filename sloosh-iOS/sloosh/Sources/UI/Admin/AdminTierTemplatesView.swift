import SwiftUI

/// Uses the existing public tier_templates node; writes remain protected by
/// Firebase admin rules. User drafts/publications are independent copies.
struct AdminTierTemplatesView: View {
    @ObservedObject private var repo = TierListsRepository.shared
    @ObservedObject private var auth = AuthRepository.shared
    @State private var editing: AdminTierTemplateSession?
    @State private var ownerId = AuthRepository.shared.currentUser?.id ?? ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLoading = true
    @State private var isDeleting = false
    @State private var error: String?

    var body: some View {
        List {
            if auth.isAdmin {
                Section {
                    Button {
                        editing = AdminTierTemplateSession(original: nil)
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
                                editing = AdminTierTemplateSession(original: template)
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
        .scrollEdgeEffectStyle(.soft, for: .all)
        .task(id: auth.isAdmin) {
            if auth.isAdmin, ownerId == auth.currentUser?.id, editing == nil {
                editing = sessionStore.load()
            }
            await reload()
        }
        .onChange(of: editing) { _, _ in checkpoint() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { checkpoint() }
        }
        .refreshable { await reload() }
        .sheet(item: $editing, onDismiss: {
            // Interactive dismissal is allowed only for an unchanged editor.
            if sessionStore.load()?.hasUnsavedWork == false { sessionStore.clear() }
            Task { await reload() }
        }) { session in
            AdminTierTemplateEditor(session: Binding(
                get: { editing ?? session },
                set: { updated in
                    guard editing != nil, auth.isAdmin, ownerId == auth.currentUser?.id else { return }
                    editing = updated
                    sessionStore.save(updated)
                }
            ), onFinish: {
                sessionStore.clear()
                editing = nil
            })
        }
        .alert("Не удалось выполнить действие", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private var sessionStore: AdminTierTemplateSessionStore {
        AdminTierTemplateSessionStore(defaults: .standard, userId: ownerId)
    }

    private func checkpoint() {
        guard auth.isAdmin, ownerId == auth.currentUser?.id, let editing else { return }
        sessionStore.save(editing)
    }

    private func reload() async {
        guard auth.isAdmin else { isLoading = false; return }
        _ = await repo.fetchTemplates(force: true)
        isLoading = false
    }
}

private struct AdminTierTemplateEditor: View {
    @Binding var session: AdminTierTemplateSession
    var onFinish: () -> Void
    private var original: TierTemplate? { session.original }
    @ObservedObject private var auth = AuthRepository.shared
    @State private var discardChanges = false
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Название и описание") {
                    TextField("Название", text: $session.value.title)
                    TextField("Описание (необязательно)", text: Binding(get: { session.value.subtitle ?? "" }, set: { session.value.subtitle = $0.isEmpty ? nil : $0 }), axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Stepper("Приоритет: \(session.value.priority ?? 0)", value: Binding(get: { session.value.priority ?? 0 }, set: { session.value.priority = $0 }), in: -1000...1000)
                } footer: { Text("Чем выше приоритет, тем раньше шаблон в списке.") }
                Section {
                    Button { session.showPicker = true } label: { Label("Добавить фильмы", systemImage: "plus") }
                        .foregroundStyle(.primary)
                    ForEach(session.value.items) { item in
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
                    .onDelete { session.value.items.remove(atOffsets: $0) }
                    .onMove { session.value.items.move(fromOffsets: $0, toOffset: $1) }
                    .tint(.red)
                } header: { Text("Фильмы: \(session.value.items.count)") }
                footer: { Text("Не менее четырёх. Первые четыре постера формируют обложку; порядок меняется за ручку справа.") }
            }
            .environment(\.editMode, .constant(.active))
            .scrollEdgeEffectStyle(.soft, for: .all)
            .disabled(isSaving || !auth.isAdmin)
            .navigationTitle(original == nil ? "Новый шаблон" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        if session.hasUnsavedWork { discardChanges = true } else { onFinish() }
                    }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Сохранить") }
                    }
                    .disabled(isSaving || !auth.isAdmin || !session.hasTemplateChanges)
                }
            }
            .sheet(isPresented: $session.showPicker) {
                TierItemPickerSheet(existingIds: Set(session.value.items.map(\.mediaId)),
                                    draft: $session.picker, onAdd: { _ in
                    session.addSelectedItems()
                }, onDismiss: {
                    session.picker = TierItemPickerDraft()
                    session.showPicker = false
                })
            }
            .confirmationDialog("Отменить изменения?", isPresented: $discardChanges, titleVisibility: .visible) {
                Button("Не сохранять", role: .destructive) { onFinish() }
                Button("Продолжить редактирование", role: .cancel) {}
            }
            .alert("Не удалось сохранить шаблон", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Понятно", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
        .interactiveDismissDisabled(isSaving || session.hasUnsavedWork)
    }

    private func save() async {
        guard !isSaving else { return }
        if let message = session.value.validationMessage { error = message; return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await TierListsRepository.shared.saveTemplate(session.value, expected: original)
            onFinish()
        } catch { self.error = error.localizedDescription }
    }
}
