import SwiftUI

/// Главная тир-листов: чисто нативный List с секциями (Создать, Мои,
/// Шаблоны, Популярные), системный навбар, системный back, swipe-удаление.
struct TierListsHomeView: View {
    @Environment(\.dismiss) private var dismiss
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
                    Label("Новый тир-лист", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Расставьте фильмы по уровням и поделитесь картинкой")
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
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                TierListsRepository.shared.deleteDraft(id: draft.id)
                                myDrafts = TierListsRepository.shared.loadDrafts()
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                    ForEach(myLists) { list in
                        Button {
                            viewerList = list
                        } label: {
                            row(title: list.title, detail: "\(list.itemsCount) фильмов", posters: list.allItems.compactMap(\.posterUrl))
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task {
                                    try? await TierListsRepository.shared.deleteList(id: list.id)
                                    myLists.removeAll { $0.id == list.id }
                                }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section("Шаблоны") {
                if repo.templates.isEmpty {
                    ProgressView()
                } else {
                    ForEach(repo.templates) { template in
                        Button {
                            editorDraft = TierListsRepository.shared.makeDraft(from: template)
                        } label: {
                            row(title: template.title, detail: template.subtitle ?? "\(template.items.count) фильмов", posters: template.coverPosterUrls)
                        }
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
                    }
                }
            }
        }
        .navigationTitle("Тир-листы")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorDraft = TierListsRepository.shared.makeDraft()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await reload() }
        .refreshable { await reload(force: true) }
        .navigationDestination(item: $editorDraft) { draft in
            TierListEditorView(
                draft: draft,
                onPublished: { published in
                    myLists.insert(published, at: 0)
                    viewerList = published
                },
                onDismiss: {}
            )
        }
        .navigationDestination(item: $viewerList) { list in
            TierListViewerView(listId: list.id, initialList: list)
        }
    }

    private func reload(force: Bool = false) async {
        myDrafts = TierListsRepository.shared.loadDrafts()
        myLists = await TierListsRepository.shared.fetchLists(forAuthorId: AuthRepository.shared.currentUser?.id ?? "")
        _ = await TierListsRepository.shared.fetchTemplates(force: force)
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
