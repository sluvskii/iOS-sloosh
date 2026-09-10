import SwiftUI

enum FilterContext {
    case home
    case search
}

struct SearchFilterSheet: View {
    @Binding var filters: SearchFilters
    var context: FilterContext = .search
    @Environment(\.dismiss) private var dismiss

    private let currentYear = Calendar.current.component(.year, from: Date())

    private let genresList = [
        "боевик", "комедия", "драма", "фантастика", "фэнтези", "нф и фэнтези",
        "триллер", "ужасы", "детектив", "мелодрама", "приключения",
        "мультфильм", "криминал", "семейный", "документальный", "аниме", "военный", "история"
    ]

    private let countriesList = [
        "Россия", "США", "Великобритания", "Франция", "Южная Корея",
        "Япония", "СССР", "Германия", "Испания", "Италия", "Турция",
        "Канада", "Индия", "Китай"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Content Type (for Search context)
                    if context == .search {
                        typeSection
                    }

                    // 2. Dropdown Pickers (Сортировка, Жанр, Страна)
                    pickersCard

                    // 3. Compact Rating Capsule Slider
                    ratingSliderCard

                    // 4. Compact Release Year Capsule Slider
                    yearSliderCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Сбросить") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            filters = SearchFilters()
                        }
                    }
                    .disabled(filters.isEmpty)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                    .bold()
                    .foregroundStyle(Color.slooshAccent)
                }
            }
            .background(Color.clear)
        }
        .presentationDetents([.fraction(0.85), .large])
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content Type Section
    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Тип контента", systemImage: "play.rectangle.on.rectangle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    typeCapsule(title: "Всё", tag: nil, icon: "sparkles")
                    typeCapsule(title: "Фильмы", tag: "FILM", icon: "film")
                    typeCapsule(title: "Сериалы", tag: "TV_SERIES", icon: "tv")
                    typeCapsule(title: "Мульты", tag: "CARTOON", icon: "face.smiling")
                    typeCapsule(title: "Аниме", tag: "ANIME", icon: "wand.and.stars")
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private func typeCapsule(title: String, tag: String?, icon: String) -> some View {
        let isSelected = filters.type == tag
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                filters.type = tag
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? .white : .primary)
            .background {
                if isSelected {
                    Capsule().fill(Color.slooshAccent)
                }
            }
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pickers Card (Sort, Genre, Country)
    private var pickersCard: some View {
        VStack(spacing: 0) {
            // Sort
            HStack {
                Label("Сортировка", systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Menu {
                    if context == .search {
                        Button("Релевантность") { filters.order = nil }
                        Button("По популярности") { filters.order = "NUM_VOTE" }
                    } else {
                        Button("Смотрят сейчас") { filters.order = nil }
                        Button("По популярности") { filters.order = "NUM_VOTE" }
                    }
                    Button("По рейтингу") { filters.order = "RATING" }
                    Button("По году выпуска") { filters.order = "YEAR" }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentSortTitle)
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundColor(filters.order == nil ? .primary : Color.slooshAccent)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider()
                .padding(.leading, 48)

            // Genre
            HStack {
                Label("Жанр", systemImage: "theatermasks")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Menu {
                    Button("Любой") { filters.genres = nil }
                    Divider()
                    ForEach(genresList, id: \.self) { genre in
                        Button(genreDisplayName(genre)) {
                            filters.genres = genre
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(filters.genres.map { genreDisplayName($0) } ?? "Любой")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundColor(filters.genres == nil ? .primary : Color.slooshAccent)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider()
                .padding(.leading, 48)

            // Country
            HStack {
                Label("Страна", systemImage: "globe")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)

                Spacer()

                Menu {
                    Button("Любая") { filters.countries = nil }
                    Divider()
                    ForEach(countriesList, id: \.self) { country in
                        Button(country) {
                            filters.countries = country
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(filters.countries ?? "Любая")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundColor(filters.countries == nil ? .primary : Color.slooshAccent)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var currentSortTitle: String {
        switch filters.order {
        case "NUM_VOTE":
            return "По популярности"
        case "RATING":
            return "По рейтингу"
        case "YEAR":
            return "По году выпуска"
        default:
            return context == .search ? "Релевантность" : "Смотрят сейчас"
        }
    }

    private func genreDisplayName(_ genre: String) -> String {
        if genre.lowercased() == "нф и фэнтези" {
            return "НФ и фэнтези"
        }
        return genre.capitalized
    }

    // MARK: - Rating Slider Card
    private var ratingSliderCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Минимальный рейтинг", systemImage: "star.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 6) {
                    if let rating = filters.ratingFrom {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                            Text(String(format: "%.1f+", rating))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color.slooshAccent)

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                filters.ratingFrom = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Любой")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular.interactive(), in: Capsule())
            }

            HStack(spacing: 10) {
                Text("1.0")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { filters.ratingFrom ?? 1.0 },
                        set: { newValue in
                            filters.ratingFrom = newValue <= 1.0 ? nil : (round(newValue * 10) / 10)
                        }
                    ),
                    in: 1.0...10.0,
                    step: 0.5
                )
                .tint(Color.slooshAccent)

                Text("10.0")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Year Slider Card
    private var yearSliderCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Год выпуска", systemImage: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                HStack(spacing: 6) {
                    if let year = filters.yearFrom {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text("от \(String(year)) г.")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color.slooshAccent)

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                filters.yearFrom = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Любой")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.regular.interactive(), in: Capsule())
            }

            HStack(spacing: 10) {
                Text("1980")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(filters.yearFrom ?? 1980) },
                        set: { newValue in
                            let year = Int(newValue)
                            filters.yearFrom = year <= 1980 ? nil : year
                        }
                    ),
                    in: 1980.0...Double(currentYear),
                    step: 1.0
                )
                .tint(Color.slooshAccent)

                Text("\(currentYear)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
