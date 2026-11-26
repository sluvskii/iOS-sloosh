import SwiftUI

/// Главная тир-листов: чисто нативный List с секциями (Создать, Мои,
/// Шаблоны, Популярные), системный навбар, системный back, swipe-удаление.
struct TierListsHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthRepository.shared
    @State private var actionError: String?
    @StateObject private var repo = TierListsRepository.shared
    @State private var editorDraft: TierList?
    @State private var viewerList: TierList?
    @State private var myLists: [TierList] = []
    @State private var myDrafts: [TierList] = []
    @State private var isLoadingMine = true

    private var columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        List {
            Section {
                Button {
                    editorDraft = TierListsRepository.shared.makeDraft()
                } label: {
                    Label("Новый тир-лист", systemImage: "plus")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                }
            } footer: {
                Text("Расставьте фильмы по уровням и поделитесь картинкой")
            }

            if let error = repo.lastError {
                Section { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }

            Section("Мои тир-листы") {
                if isLoadingMine {
                    ForEach(0..<3, id: \.self) { _ in
                        Text("…").foregroundStyle(.secondary)
                    }
                } else if myDrafts.isEmpty && myLists.isEmpty {
                    Text("Пока ничего нет")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(myDrafts) { draft in
                        Button {
                            editorDraft = draft
                        } label: {
                            row(title: draft.title, detail: "Черновик · \(draft.itemsCount) фильмов", posters: draft.allItems.compactMap(\.posterUrl))
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                repo.deleteDraft(id: draft.id)
                                myDrafts = repo.loadDrafts()
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                    ForEach(myLists) { list in
                        Button {
                            viewerList = list
                        } label: {
                            row(title: list.title, detail: "\(list.itemsCount) фильмов", posters: list.allItems.compactMap(\.posterUrl))
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    do {
                                        try await repo.deleteList(id: list.id)
                                        myLists.removeAll { $0.id == list.id }
                                    } catch { actionError = "Не удалось удалить тир-лист. Повторите попытку." }
                                }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
            }

            Section("Шаблоны") {
                if repo.templates.isEmpty && isLoadingMine {
                    ProgressView()
                } else if repo.templates.isEmpty {
                    Text("Шаблоны пока недоступны. Можно создать свой тир-лист.").foregroundStyle(.secondary)
                } else {
                    ForEach(repo.templates) { template in
                        Button {
                            editorDraft = TierListsRepository.shared.makeDraft(from: template)
                        } label: {
                            row(title: template.title, detail: template.subtitle ?? "\(template.items.count) фильмов", posters: template.coverPosterUrls)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Популярные") {
                let ranked = repo.rankLists(repo.publicLists)
                if ranked.isEmpty {
                    Text("Пока нет публичных тир-листов")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ranked) { list in
                        Button {
                            viewerList = list
                        } label: {
                            row(title: list.title, detail: "от \(list.authorName) · \(list.likesCount ?? 0) ❤︎", posters: list.allItems.compactMap(\.posterUrl))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .navigationTitle("Тир-листы")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorDraft = TierListsRepository.shared.makeDraft()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .tint(.primary)
            }
        }
        .task(id: auth.currentUser?.id) {
            myLists = []
            myDrafts = []
            isLoadingMine = true
            await reload()
        }
        .onChange(of: repo.publicLists) { _, lists in
            let fresh = lists.filter { $0.authorId == auth.currentUser?.id }
            for list in fresh {
                if let i = myLists.firstIndex(where: { $0.id == list.id }) { myLists[i] = list }
                else { myLists.insert(list, at: 0) }
            }
        }
        .alert("Не удалось выполнить действие", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: { Text(actionError ?? "") }
        .refreshable { await reload(force: true) }
        .navigationDestination(item: $editorDraft) { draft in
            TierListEditorView(
                draft: draft,
                onPublished: { published in
                    myLists.removeAll { $0.id == published.id }
                    myLists.insert(published, at: 0)
                    myDrafts = repo.loadDrafts()
                    viewerList = published
                },
                onDismiss: {}
            )
            .onDisappear { myDrafts = repo.loadDrafts() }
        }
        .navigationDestination(item: $viewerList) { list in
            TierListViewerView(listId: list.id, initialList: list)
        }
    }

    private func reload(force: Bool = false) async {
        let userId = auth.currentUser?.id
        myDrafts = repo.loadDrafts()
        _ = await repo.fetchPublicLists(force: force)
        let mine = await repo.fetchLists(forAuthorId: userId ?? "")
        _ = await repo.fetchTemplates(force: true)
        guard !Task.isCancelled, userId == auth.currentUser?.id else { return }
        myLists = mine
        isLoadingMine = false
    }

    @ViewBuilder
    private func row(title: String, detail: String, posters: [String]) -> some View {
        HStack(spacing: 12) {
            posterStrip(posters)
                .frame(width: 74, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func posterStrip(_ posters: [String]) -> some View {
        if posters.isEmpty {
            Rectangle()
                .fill(Color(UIColor.tertiarySystemFill))
                .overlay(Image(systemName: "list.star").foregroundStyle(.tertiary))
        } else {
            HStack(spacing: 2) {
                ForEach(Array(posters.prefix(2).enumerated()), id: \.offset) { _, url in
                    AsyncCachedImage(
                        url: URL(string: url),
                        placeholder: { Rectangle().fill(Color(UIColor.tertiarySystemFill)) },
                        content: { image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        },
                        fallback: { Rectangle().fill(Color(UIColor.tertiarySystemFill)) }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
