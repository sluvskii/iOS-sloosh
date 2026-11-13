import SwiftUI

/// Добавление фильмов в тир-лист: чисто нативный List с системным поиском
/// (.searchable), быстрым доступом к избранному, популярным фильмам и подборкам.
struct TierItemPickerSheet: View {
    var onAdd: ([TierListItem]) -> Void
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [TierListItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var favoriteItems: [TierListItem] = []
    @State private var popularItems: [TierListItem] = []
    @State private var studios: [CategoryItemDto] = []
    @State private var selectedStudio: CategoryItemDto?
    @State private var studioItems: [TierListItem] = []
    @State private var studioPage = 1
    @State private var studioTotalPages = 1
    @State private var isLoadingStudio = false
    @State private var selected: [String: TierListItem] = [:]

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
                        if studios.isEmpty {
                            ProgressView()
                                .padding(.vertical, 4)
                        } else {
                            ForEach(studios, id: \.id) { studio in
                                Button {
                                    selectedStudio = studio
                                    Task { await loadStudioItems(studio) }
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
            .searchable(text: $searchText, prompt: "Название фильма или сериала")
            .navigationTitle("Добавить фильмы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { onDismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Добавить (\(selected.count))") {
                        onAdd(Array(selected.values))
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
        .onChange(of: searchText) { _, newValue in
            searchTask?.cancel()
            let query = newValue.trimmingCharacters(in: .whitespaces)
            guard query.count >= 2 else {
                searchResults = []
                isSearching = false
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { isSearching = true }
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

    @ViewBuilder
    private func pickerRows(items: [TierListItem], paged: Bool) -> some View {
        ForEach(items) { item in
            let isSelected = selected[item.mediaId] != nil
            Button {
                if isSelected {
                    selected.removeValue(forKey: item.mediaId)
                } else {
                    selected[item.mediaId] = item
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 12) {
                    AsyncCachedImage(
                        url: item.posterUrl.flatMap { URL(string: $0) },
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

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? Color.primary : Color(UIColor.tertiaryLabel))
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

    private func loadInitialData() async {
        // 1. Избранное пользователя
        let favs = FavoritesRepository.shared.favorites.compactMap { fav -> TierListItem? in
            guard let id = fav.mediaId ?? fav.id, !id.isEmpty else { return nil }
            let title = fav.title ?? "Без названия"
            let type = fav.type ?? "movie"
            let typedId: String
            if id.hasPrefix("movie_") || id.hasPrefix("tv_") || id.hasPrefix("kp_") || id.hasPrefix("tmdb_") {
                typedId = id
            } else {
                typedId = "\(type)_\(id)"
            }
            return TierListItem(
                mediaId: typedId,
                mediaType: type,
                title: title,
                year: fav.year.flatMap(Int.init),
                posterUrl: fav.posterUrl
            )
        }
        await MainActor.run { favoriteItems = favs }

        // 2. Популярные фильмы
        if let popular = try? await MoviesRepository.shared.getPopularMovies(page: 1) {
            let items = popular.compactMap(TierListItem.init)
            await MainActor.run { popularItems = items }
        }

        // 3. Подборки и студии
        let sections = await MoviesRepository.shared.getCategories()
        let allStudios = sections.flatMap(\.items)
        await MainActor.run { studios = allStudios }
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

// MARK: - Адаптеры MediaDto / MediaDetailsDto → TierListItem

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
