import SwiftUI

/// Добавление фильмов в тир-лист: чисто нативный List с системным поиском
/// (.searchable), быстрым доступом к избранному, популярным фильмам и подборкам.
struct TierItemPickerSheet: View {
    var existingIds: Set<String> = []
    // Admin editing owns this outside the sheet and checkpoints it locally.
    // Other callers retain their existing sheet-local selection behavior.
    var draft: Binding<TierItemPickerDraft>? = nil
    var onAdd: ([TierListItem]) -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var localDraft = TierItemPickerDraft()
    private var searchText: String {
        get { draft?.wrappedValue.searchText ?? localDraft.searchText }
        nonmutating set {
            if let draft { draft.wrappedValue.searchText = newValue }
            else { localDraft.searchText = newValue }
        }
    }
    private var selected: [TierListItem] {
        get { draft?.wrappedValue.selected ?? localDraft.selected }
        nonmutating set {
            if let draft { draft.wrappedValue.selected = newValue }
            else { localDraft.selected = newValue }
        }
    }
    @State private var searchResults: [TierListItem] = []
    @State private var isSearching = false
    @State private var favoriteItems: [TierListItem] = []
    @State private var popularItems: [TierListItem] = []
    @State private var studios: [CategoryItemDto] = []
    private var selectedStudio: CategoryItemDto? {
        get {
            let collection: TierPickerCollection?
            if let draft { collection = draft.wrappedValue.collection }
            else { collection = localDraft.collection }
            return collection.map { CategoryItemDto(id: $0.id, name: $0.name) }
        }
        nonmutating set {
            let collection = newValue.map { TierPickerCollection(id: $0.id, name: $0.name) }
            if let draft { draft.wrappedValue.collection = collection }
            else { localDraft.collection = collection }
        }
    }
    @State private var studioItems: [TierListItem] = []
    @State private var studioPage = 1
    @State private var studioTotalPages = 1
    @State private var isLoadingStudio = false
    @State private var studioError: String?
    @State private var loadError: String?
    @State private var didLoadInitial = false

    var body: some View {
        NavigationStack {
            List {
                let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
                if !trimmedSearch.isEmpty {
                    Section("Результаты поиска") {
                        if isSearching {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else if let loadError {
                            Text(loadError).foregroundStyle(.secondary)
                        } else if trimmedSearch.count < 2 {
                            Text("Введите хотя бы два символа").foregroundStyle(.secondary)
                        } else if searchResults.isEmpty {
                            Text("Ничего не найдено")
                                .foregroundStyle(.secondary)
                        } else {
                            pickerRows(items: searchResults, paged: false)
                        }
                    }
                } else if let studio = selectedStudio {
                    Section {
                        Button {
                            selectedStudio = nil
                            studioItems = []
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.caption.weight(.bold))
                                Text("Все подборки")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                    Section("\(studio.name)") {
                        if isLoadingStudio && studioItems.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else {
                            pickerRows(items: studioItems, paged: true)
                            if let studioError { Text(studioError).font(.footnote).foregroundStyle(.secondary) }
                            if studioItems.isEmpty {
                                Button("Повторить загрузку") { Task { await loadStudioItems(studio) } }
                            } else if studioPage < studioTotalPages {
                                Button(isLoadingStudio ? "Загрузка…" : "Загрузить ещё") { Task { await loadStudioItemsNextPage() } }
                                    .disabled(isLoadingStudio)
                            }
                        }
                    }
                } else {
                    if !favoriteItems.isEmpty {
                        Section("Избранное") {
                            pickerRows(items: favoriteItems, paged: false)
                        }
                    }

                    if !popularItems.isEmpty {
                        Section("Популярное сейчас") {
                            pickerRows(items: popularItems, paged: false)
                        }
                    }

                    Section("Франшизы и подборки") {
                        if studios.isEmpty && didLoadInitial {
                            Button("Повторить загрузку") { Task { await loadInitialData() } }
                        } else if studios.isEmpty {
                            ProgressView()
                                .padding(.vertical, 4)
                        } else {
                            ForEach(studios, id: \.id) { studio in
                                Button {
                                    selectedStudio = studio
                                } label: {
                                    HStack {
                                        Label(studio.name, systemImage: "folder")
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: Binding(get: { searchText }, set: { searchText = $0 }), prompt: "Название фильма или сериала")
            .navigationTitle("Добавить фильмы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { onDismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Добавить (\(selected.count))") {
                        onAdd(selected)
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .disabled(selected.isEmpty)
                }
            }
        }
        .tint(.primary)
        .task {
            await loadInitialData()
        }
        .task(id: searchText) {
            await search()
        }
        .task(id: selectedStudio?.id) {
            if let studio = selectedStudio { await loadStudioItems(studio) }
        }
    }

    private func search() async {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchResults = []
        loadError = nil
        do {
            try await Task.sleep(nanoseconds: 280_000_000)
            let items = try await MoviesRepository.shared.searchMovies(query: query, page: 1).compactMap(TierListItem.init)
            guard !Task.isCancelled else { return }
            searchResults = items
            isSearching = false
        } catch {
            guard !Task.isCancelled else { return }
            loadError = "Не удалось выполнить поиск. Попробуйте ещё раз."
            isSearching = false
        }
    }

    @ViewBuilder
    private func pickerRows(items: [TierListItem], paged: Bool) -> some View {
        ForEach(items) { item in
            let isSelected = selected.contains { $0.mediaId == item.mediaId }
            let isExisting = existingIds.contains(item.mediaId)
            Button {
                if isSelected {
                    selected.removeAll { $0.mediaId == item.mediaId }
                } else {
                    selected.append(item)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 12) {
                    AsyncCachedImage(
                        url: item.resolvedPosterURL.flatMap { URL(string: $0) },
                        placeholder: { Rectangle().fill(Color(UIColor.tertiarySystemFill)) },
                        content: { image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        },
                        fallback: { Rectangle().fill(Color(UIColor.tertiarySystemFill)) }
                    )
                    .frame(width: 40, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        if let year = item.year {
                            Text(String(year))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)

                    Image(systemName: (isSelected || isExisting) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? Color.primary : Color(UIColor.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)
            .disabled(isExisting)
            .accessibilityValue(isExisting ? "Уже в тир-листе" : (isSelected ? "Выбрано" : "Не выбрано"))
            .onAppear {
                if paged, item.mediaId == items.last?.mediaId, studioPage < studioTotalPages, !isLoadingStudio {
                    Task { await loadStudioItemsNextPage() }
                }
            }
        }
    }

    private func loadInitialData() async {
        // 1. Избранное пользователя
        didLoadInitial = false
        let favs = FavoritesRepository.shared.favorites.compactMap { TierListItem(from: $0.toMediaDto()) }
        await MainActor.run { favoriteItems = favs }

        // 2. Популярные фильмы
        if let popular = try? await MoviesRepository.shared.getPopularMovies(page: 1) {
            let items = popular.compactMap(TierListItem.init)
            await MainActor.run { popularItems = items }
        }

        // 3. Подборки и студии
        let sections = await MoviesRepository.shared.getCategories()
        let allStudios = sections.flatMap(\.items)
        await MainActor.run { studios = allStudios; didLoadInitial = true }
    }

    private func loadStudioItems(_ studio: CategoryItemDto) async {
        isLoadingStudio = true
        studioError = nil
        studioPage = 1
        guard let response = try? await MoviesRepository.shared.getCollection(id: studio.id, page: 1) else {
            guard selectedStudio?.id == studio.id else { return }
            studioItems = []
            studioError = "Не удалось загрузить подборку."
            isLoadingStudio = false
            return
        }
        let items = response.items.compactMap(TierListItem.init)
        let pages = response.totalPages
        guard !Task.isCancelled, selectedStudio?.id == studio.id else { return }
        await MainActor.run {
            studioItems = items
            studioTotalPages = max(1, pages)
            isLoadingStudio = false
        }
    }

    private func loadStudioItemsNextPage() async {
        guard !isLoadingStudio, let studio = selectedStudio else { return }
        isLoadingStudio = true
        studioError = nil
        let nextPage = studioPage + 1
        guard let response = try? await MoviesRepository.shared.getCollection(id: studio.id, page: nextPage) else {
            guard selectedStudio?.id == studio.id else { return }
            studioError = "Не удалось загрузить следующую страницу."
            isLoadingStudio = false
            return
        }
        guard !Task.isCancelled, selectedStudio?.id == studio.id else { return }
        studioPage = nextPage
        let items = response.items.compactMap(TierListItem.init)
        await MainActor.run {
            let known = Set(studioItems.map(\.mediaId))
            studioItems.append(contentsOf: items.filter { !known.contains($0.mediaId) })
            isLoadingStudio = false
        }
    }
}

// MARK: - Адаптеры MediaDto / MediaDetailsDto → TierListItem

extension TierListItem {
    var resolvedPosterURL: String? {
        let item = MediaOverridesRepository.shared.catalogOverride(id: mediaId, type: mediaType, kpId: nil)
        let chosen = item?.artworkURL(item?.posterUrl) ?? posterUrl
        return normalizeImageUrl(path: chosen, id: mediaId)
    }

    init?(from media: MediaDto) {
        guard let identity = CatalogArtworkIdentity(id: media.originalId?.stringValue, type: media.type)
                ?? (media.externalIds?.tmdb).flatMap({ CatalogArtworkIdentity(id: String($0), type: media.type) }) else { return nil }
        let typedId = identity.requestId
        self.init(
            mediaId: typedId,
            mediaType: identity.mediaType ?? media.type ?? "movie",
            title: media.title ?? media.originalTitle ?? "",
            year: media.year?.intValue,
            posterUrl: media.displayPosterUrl(forLogoMode: false)
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
            posterUrl: details.displayPosterUrl
        )
    }
}
