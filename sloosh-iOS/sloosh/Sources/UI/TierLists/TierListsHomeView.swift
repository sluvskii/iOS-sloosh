import SwiftUI

/// Главная галерея тир-листов: «Мои», «Шаблоны», «Популярные».
/// Открывается из Профиля и по deep link.
struct TierListsHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var repo = TierListsRepository.shared
    @State private var tab: Tab = .mine
    @State private var scrollOffset: CGFloat = 0
    @State private var editorDraft: TierList?
    @State private var viewerList: TierList?
    @State private var myLists: [TierList] = []
    @State private var myDrafts: [TierList] = []
    @State private var isLoadingMine = true

    enum Tab: String, CaseIterable {
        case mine = "Мои"
        case templates = "Шаблоны"
        case popular = "Популярные"
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            SlooshTopBar(
                title: "Тир-листы",
                blendsTitle: false,
                scrollOffset: $scrollOffset,
                leadingIcon: "chevron.left",
                leadingAction: { dismiss() },
                trailing: {
                    Button {
                        editorDraft = TierListsRepository.shared.makeDraft()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(width: 34, height: 34)
                            .background(Color.slooshAccent, in: Circle())
                    }
                }
            )

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ScrollView {
                switch tab {
                case .mine: mineSection
                case .templates: templatesSection
                case .popular: popularSection
                }
                Spacer(minLength: 60)
            }
        }
        .background(TierListTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            myDrafts = TierListsRepository.shared.loadDrafts()
            async let mine = TierListsRepository.shared.fetchLists(forAuthorId: AuthRepository.shared.currentUser?.id ?? "")
            async let templates = TierListsRepository.shared.fetchTemplates()
            let mineResult = await mine
            let templatesResult = await templates
            myLists = mineResult
            isLoadingMine = false
            _ = templatesResult
        }
        .refreshable {
            myLists = await TierListsRepository.shared.fetchLists(forAuthorId: AuthRepository.shared.currentUser?.id ?? "")
            _ = await TierListsRepository.shared.fetchTemplates(force: true)
            myDrafts = TierListsRepository.shared.loadDrafts()
        }
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

    // MARK: Мои

    @ViewBuilder
    private var mineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                editorDraft = TierListsRepository.shared.makeDraft()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.line.vertical.and.square.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.slooshAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Создать тир-лист")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Из шаблона, из подборки или с нуля")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 6)

            if isLoadingMine {
                ProgressView().tint(Color.slooshAccent).frame(maxWidth: .infinity, minHeight: 160)
            } else if myDrafts.isEmpty && myLists.isEmpty {
                AppEmptyStateView(
                    icon: "list.star",
                    title: "Пока пусто",
                    description: "Соберите первый тир-лист из любимых фильмов — расставьте их по уровням и поделитесь с друзьями"
                )
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(myDrafts) { draft in
                        Button {
                            editorDraft = draft
                        } label: {
                            TierListCardView(
                                title: draft.title,
                                subtitle: "\(draft.itemsCount) фильмов",
                                posterUrls: draft.allItems.compactMap(\.posterUrl),
                                badge: "Черновик",
                                likesCount: nil
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                TierListsRepository.shared.deleteDraft(id: draft.id)
                                myDrafts = TierListsRepository.shared.loadDrafts()
                            } label: {
                                Label("Удалить черновик", systemImage: "trash")
                            }
                        }
                    }
                    ForEach(myLists) { list in
                        Button {
                            viewerList = list
                        } label: {
                            TierListCardView(
                                title: list.title,
                                subtitle: "\(list.itemsCount) фильмов",
                                posterUrls: list.allItems.compactMap(\.posterUrl),
                                badge: nil,
                                likesCount: list.likesCount
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                viewerList = list
                            } label: {
                                Label("Открыть", systemImage: "eye")
                            }
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
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Шаблоны

    @ViewBuilder
    private var templatesSection: some View {
        if repo.templates.isEmpty {
            VStack(spacing: 10) {
                ProgressView().tint(Color.slooshAccent).frame(maxWidth: .infinity, minHeight: 160)
                Text("Загружаем шаблоны…")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(repo.templates) { template in
                    Button {
                        editorDraft = TierListsRepository.shared.makeDraft(from: template)
                    } label: {
                        TierListCardView(
                            title: template.title,
                            subtitle: template.subtitle ?? "\(template.items.count) фильмов",
                            posterUrls: template.coverPosterUrls,
                            badge: "\(template.items.count) шт",
                            likesCount: nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    // MARK: Популярные

    @ViewBuilder
    private var popularSection: some View {
        let ranked = repo.rankLists(repo.publicLists)
        if ranked.isEmpty {
            AppEmptyStateView(
                icon: "flame",
                title: "Пока нет публичных тир-листов",
                description: "Создайте первый — он появится здесь и в вашем профиле"
            )
            .frame(maxWidth: .infinity)
        } else {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(ranked) { list in
                    Button {
                        viewerList = list
                    } label: {
                        TierListCardView(
                            title: list.title,
                            subtitle: "от \(list.authorName)",
                            posterUrls: list.allItems.compactMap(\.posterUrl),
                            badge: nil,
                            likesCount: list.likesCount
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}
