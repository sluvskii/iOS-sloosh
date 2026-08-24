import SwiftUI

public struct MovieSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var repo = MoviesRepository.shared

    @State private var query: String = ""
    @State private var searchResults: [MediaDto] = []
    @State private var popularMovies: [MediaDto] = []
    @State private var isLoading: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil

    public let onSelect: (MediaCardPayload) -> Void

    public init(onSelect: @escaping (MediaCardPayload) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                // Liquid Glass Search Bar
                searchBar

                if isLoading && searchResults.isEmpty && !query.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        ProgressView("Поиск...")
                            .tint(Color.slooshAccent)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    trendingSection
                } else if searchResults.isEmpty {
                    VStack {
                        Spacer()
                        AppEmptyStateView(
                            icon: "film",
                            title: "Ничего не найдено",
                            description: "Попробуйте изменить поисковый запрос"
                        )
                        Spacer()
                    }
                } else {
                    resultsGrid(searchResults)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .navigationTitle("Прикрепить фильм")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
            }
            .task {
                if popularMovies.isEmpty {
                    popularMovies = (try? await repo.getPopularMovies(page: 1)) ?? []
                }
            }
        }
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Название фильма или сериала", text: $query)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .autocorrectionDisabled()
                .onChange(of: query) { _, newQuery in
                    performDebouncedSearch(query: newQuery)
                }

            if !query.isEmpty {
                Button {
                    query = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ПОПУЛЯРНОЕ СЕЙЧАС")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            resultsGrid(popularMovies)
        }
    }

    private func resultsGrid(_ items: [MediaDto]) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(items) { movie in
                    Button {
                        selectMovie(movie)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack(alignment: .topLeading) {
                                AsyncCachedImage(urlString: movie.displayPosterUrl ?? "") {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.08))
                                        .aspectRatio(2/3, contentMode: .fit)
                                } content: { image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(2/3, contentMode: .fill)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                if let rating = movie.rating ?? movie.ratings?.kp, rating > 0 {
                                    Text(String(format: "%.1f", rating))
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.rating(rating))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .padding(5)
                                }
                            }

                            Text(movie.displayTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            if let year = movie.year?.stringValue, !year.isEmpty {
                                Text(year)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func performDebouncedSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isLoading = false
            return
        }

        isLoading = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let response = try? await repo.searchMovies(query: trimmed, page: 1)
            if !Task.isCancelled {
                self.searchResults = response ?? []
                self.isLoading = false
            }
        }
    }

    private func selectMovie(_ movie: MediaDto) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let ratingValue = movie.rating ?? movie.ratings?.kp
        let payload = MediaCardPayload(
            mediaId: movie.id,
            type: movie.type ?? "movie",
            title: movie.displayTitle,
            posterUrl: movie.displayPosterUrl,
            rating: ratingValue,
            year: movie.year?.stringValue
        )
        onSelect(payload)
        dismiss()
    }
}
