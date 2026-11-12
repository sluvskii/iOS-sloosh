import SwiftUI

/// Главная галерея тир-листов: «Мои», «Шаблоны», «Популярные».
/// Открывается из Профиля и по deep link. Паттерн — как DownloadsView:
/// systemBackground, кастомная шапка со скрытым системным баром, swipe-back.
struct TierListsHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var repo = TierListsRepository.shared
    @State private var tab: Tab = .mine
    @State private var editorDraft: TierList?
    @State private var viewerList: TierList?
    @State private var myLists: [TierList] = []
    @State private var myDrafts: [TierList] = []
    @State private var isLoadingMine = true
    @State private var scrollOffset: CGFloat = 0

    enum Tab: String, CaseIterable {
        case mine = "Мои"
        case templates = "Шаблоны"
        case popular = "Популярные"
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ZStack {
            Group {
                switch tab {
                case .mine: mineSection
                case .templates: templatesSection
                case .popular: popularSection
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 10) {
                    header
                    Picker("", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                }
            }
        }
        .navigationTitle("Тир-листы")
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(UIColor.systemBackground))
        .fullWidthSwipeBack()
        .scrollEdgeEffectStyle(.soft, for: .bottom)
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
    private var header: some View {
        ZStack {
            Text("Тир-листы")
                .font(.system(size: 18, weight: .semibold))
                .backdropForeground()

            HStack {
                TelegramGlassIconButton(systemName: "chevron.left") {
                    dismiss()
                }
                Spacer()
                Button {
                    editorDraft = TierListsRepository.shared.makeDraft()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .glassForeground()
                        .frame(width: 34, height: 34)
                        .background(Color.slooshAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Создать тир-лист")
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Мои

    @ViewBuilder
    private var mineSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    editorDraft = TierListsRepository.shared.makeDraft()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.line.vertical.and.square.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.slooshAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Создать тир-лист")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Из шаблона, из подборки или с нуля")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(UIColor.secondarySystemFill).opacity(0.55))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if isLoadingMine {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(UIColor.tertiarySystemFill))
                                .frame(height: 150)
                                .shimmer()
                        }
                    }
                    .padding(.horizontal, 16)
                } else if myDrafts.isEmpty && myLists.isEmpty {
                    AppEmptyStateView(
                        icon: "list.star",
                        title: "Пока пусто",
                        description: "Соберите первый тир-лист из любимых фильмов — расставьте их по уровням и поделитесь с друзьями"
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
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
                            .buttonStyle(.cardPress)
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
                            .buttonStyle(.cardPress)
                            .contextMenu {
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
        .scrollIndicators(.hidden)
    }

    // MARK: Шаблоны

    @ViewBuilder
    private var templatesSection: some View {
        ScrollView {
            if repo.templates.isEmpty {
                VStack(spacing: 10) {
                    ProgressView().tint(Color.slooshAccent).frame(maxWidth: .infinity, minHeight: 160)
                    Text("Загружаем шаблоны…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
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
                        .buttonStyle(.cardPress)
                    }
                }
                .padding(16)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Популярные

    @ViewBuilder
    private var popularSection: some View {
        ScrollView {
            let ranked = repo.rankLists(repo.publicLists)
            if ranked.isEmpty {
                AppEmptyStateView(
                    icon: "flame",
                    title: "Пока нет публичных тир-листов",
                    description: "Создайте первый — он появится здесь и в вашем профиле"
                )
                .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
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
                        .buttonStyle(.cardPress)
                    }
                }
                .padding(16)
            }
        }
        .scrollIndicators(.hidden)
    }
}
