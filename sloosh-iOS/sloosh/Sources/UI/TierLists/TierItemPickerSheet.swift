import SwiftUI

/// Шит добавления фильмов в тир-лист: поиск по базе и подборки
/// (студии/сети из getCategories, франшизы и жанры — через то же API).
/// Мультивыбор: тап по постеру отмечает, кнопка внизу добавляет всё в пул.
struct TierItemPickerSheet: View {
    var onAdd: ([TierListItem]) -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: PickerMode = .search
    @State private var searchText = ""
    @State private var searchResults: [TierListItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var studios: [CategoryItemDto] = []
    @State private var selectedStudio: CategoryItemDto?
    @State private var studioItems: [TierListItem] = []
    @State private var studioPage = 1
    @State private var studioTotalPages = 1
    @State private var isLoadingStudio = false
    @State private var selected: [String: TierListItem] = [:]
    @State private var scrollOffset: CGFloat = 0

    enum PickerMode: String, CaseIterable {
        case search = "Поиск"
        case collections = "Подборки"
    }

    var body: some View {
        VStack(spacing: 0) {
            SlooshTopBar(
                title: "Добавить фильмы",
                blendsTitle: false,
                scrollOffset: $scrollOffset,
                leadingIcon: "xmark",
                leadingAction: { onDismiss() }
            )

            Picker("", selection: $mode) {
                ForEach(PickerMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 4)

            switch mode {
            case .search: searchSection
            case .collections: collectionsSection
            }

            bottomBar
        }
        .background(TierListTheme.background.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .task { await loadStudios() }
    }

    // MARK: Поиск

    @ViewBuilder
    private var searchSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Название фильма или сериала", text: $searchText)
                    .foregroundStyle(.white)
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if isSearching && searchResults.isEmpty {
                ProgressView()
                    .tint(Color.slooshAccent)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if searchResults.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Найдите фильмы и сериалы,\nчтобы расставить их по уровням")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                itemsGrid(items: searchResults, paged: false)
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            let query = newValue.trimmingCharacters(in: .whitespaces)
            guard query.count >= 2 else {
                searchResults = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                isSearching = true
                let items = ((try? await MoviesRepository.shared.searchMovies(query: query, page: 1)) ?? [])
                    .compactMap(TierListItem.init)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    searchResults = items
                    isSearching = false
                }
            }
        }
    }

    // MARK: Подборки

    @ViewBuilder
    private var collectionsSection: some View {
        if let studio = selectedStudio {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        withAnimation { selectedStudio = nil }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.leading, 16)
                    Text(studio.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.vertical, 10)

                if isLoadingStudio && studioItems.isEmpty {
                    ProgressView().tint(Color.slooshAccent).frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    itemsGrid(items: studioItems, paged: true)
                }
            }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 14) {
                    ForEach(studios, id: \.id) { studio in
                        Button {
                            selectedStudio = studio
                            Task { await loadStudioItems(studio) }
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "buildings.2")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Color.slooshAccent)
                                Text(studio.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, minHeight: 84)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: Сетка айтемов

    @ViewBuilder
    private func itemsGrid(items: [TierListItem], paged: Bool) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 12) {
                ForEach(items) { item in
                    let isSelected = selected[item.mediaId] != nil
                    Button {
                        if isSelected { selected.removeValue(forKey: item.mediaId) }
                        else { selected[item.mediaId] = item }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 0) {
                            AsyncCachedImage(
                                url: item.posterUrl.flatMap { URL(string: $0) },
                                placeholder: { Rectangle().fill(Color.white.opacity(0.08)) },
                                content: { image in Image(uiImage: image).resizable().aspectRatio(contentMode: .fill) },
                                fallback: {
                                    Rectangle().fill(Color.white.opacity(0.08))
                                        .overlay(Text(String(item.title.prefix(1))).foregroundStyle(.white.opacity(0.5)))
                                }
                            )
                            .frame(height: 132)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(isSelected ? Color.slooshAccent : .clear, lineWidth: 2.5)
                            )
                            .overlay(alignment: .topTrailing) {
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(Color.slooshAccent)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                        .padding(4)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if paged, item.mediaId == items.last?.mediaId, studioPage < studioTotalPages, !isLoadingStudio {
                            Task { await loadStudioItemsNextPage() }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: Нижняя панель

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 12) {
            Text("Выбрано: \(selected.count)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button {
                onAdd(Array(selected.values))
                dismiss()
            } label: {
                Text("Добавить")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Color.slooshAccent, in: Capsule())
            }
            .disabled(selected.isEmpty)
            .opacity(selected.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.25))
    }

    // MARK: Данные

    private func loadStudios() async {
        if studios.isEmpty {
            let sections = (try? await MoviesRepository.shared.getCategories()) ?? []
            let all = sections.flatMap(\.items)
            await MainActor.run { studios = all }
        }
    }

    private func loadStudioItems(_ studio: CategoryItemDto) async {
        isLoadingStudio = true
        studioPage = 1
        let response = try? await MoviesRepository.shared.getCollection(id: studio.id, page: 1)
        let items = (response?.items ?? []).compactMap(TierListItem.init)
        let pages = response?.totalPages ?? 1
        await MainActor.run {
            studioItems = items
            studioTotalPages = max(1, pages)
            isLoadingStudio = false
        }
    }

    private func loadStudioItemsNextPage() async {
        guard let studio = selectedStudio else { return }
        isLoadingStudio = true
        studioPage += 1
        let response = try? await MoviesRepository.shared.getCollection(id: studio.id, page: studioPage)
        let items = (response?.items ?? []).compactMap(TierListItem.init)
        await MainActor.run {
            let known = Set(studioItems.map(\.mediaId))
            studioItems.append(contentsOf: items.filter { !known.contains($0.mediaId) })
            isLoadingStudio = false
        }
    }
}

// MARK: - Адаптер MediaDto → TierListItem

extension TierListItem {
    init?(from media: MediaDto) {
        let id = media.identifier
        guard !id.isEmpty else { return nil }
        let typedId: String
        if id.hasPrefix("movie_") || id.hasPrefix("tv_") || id.hasPrefix("kp_") || id.hasPrefix("tmdb_") {
            typedId = id
        } else if let tmdb = media.externalIds?.tmdb {
            typedId = "\(media.type == "tv" ? "tv" : "movie")_\(tmdb)"
        } else {
            typedId = "\(media.type == "tv" ? "tv" : "movie")_\(id)"
        }
        self.init(
            mediaId: typedId,
            mediaType: media.type ?? "movie",
            title: media.title ?? media.originalTitle ?? "",
            year: media.year?.intValue,
            posterUrl: media.poster ?? media.posterUrl
        )
    }

    init(from details: MediaDetailsDto) {
        let id = details.id ?? String(details.ids?.tmdb ?? 0)
        let type = details.type ?? "movie"
        var typedId = id
        if !id.hasPrefix("movie_") && !id.hasPrefix("tv_") && !id.hasPrefix("kp_") && !id.hasPrefix("tmdb_") {
            typedId = "\(type == "tv" ? "tv" : "movie")_\(id)"
        }
        self.init(
            mediaId: typedId,
            mediaType: type,
            title: details.title ?? details.originalTitle ?? "",
            year: details.year,
            posterUrl: details.poster ?? details.displayPosterUrl
        )
    }
}
