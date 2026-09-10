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

    private var ratingOptions: [Double] {
        stride(from: 1.0, through: 9.5, by: 0.5).map { round($0 * 10) / 10 }
    }

    private var yearOptions: [Int] {
        Array(stride(from: currentYear, through: 1980, by: -1))
    }

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
                VStack(spacing: 12) {
                    // 1. Content Type (for Search context)
                    if context == .search {
                        typeSection
                    }

                    // 2. Dropdown Pickers (Сортировка, Жанр, Страна)
                    pickersCard

                    // 3. Alarm Clock-style Dual Wheel Picker (Рейтинг и Год выпуска)
                    ratingAndYearWheelCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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
                    .foregroundColor(filters.isEmpty ? .secondary : .primary)
                    .disabled(filters.isEmpty)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                    .bold()
                    .foregroundColor(.primary)
                }
            }
            .background(Color.clear)
        }
        .presentationDetents(context == .search ? [.fraction(0.56), .large] : [.fraction(0.46), .large])
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content Type Section
    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundColor(.secondary)

                Text("Тип контента")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()
            }
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
            .foregroundColor(isSelected ? Color(UIColor.systemBackground) : .primary)
            .background {
                if isSelected {
                    Capsule().fill(Color.primary)
                } else {
                    Capsule().fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pickers Card (Sort, Genre, Country)
    private var pickersCard: some View {
        VStack(spacing: 0) {
            // Sort
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundColor(.secondary)

                Text("Сортировка")
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
                    .foregroundColor(.primary)
                    .background(Color(UIColor.systemFill))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .padding(.leading, 52)

            // Genre
            HStack(spacing: 12) {
                Image(systemName: "theatermasks")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundColor(.secondary)

                Text("Жанр")
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
                    .foregroundColor(.primary)
                    .background(Color(UIColor.systemFill))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
                .padding(.leading, 52)

            // Country
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24, height: 24, alignment: .center)
                    .foregroundColor(.secondary)

                Text("Страна")
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
                    .foregroundColor(.primary)
                    .background(Color(UIColor.systemFill))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
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

    // MARK: - Rating & Year Wheel Card (Alarm Clock Style)
    private var ratingAndYearWheelCard: some View {
        VStack(spacing: 2) {
            // Header: Clean column titles above each wheel
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Рейтинг")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 1)

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Год выпуска")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Dual Wheel Drum
            HStack(spacing: 0) {
                Picker("Рейтинг", selection: $filters.ratingFrom) {
                    Text("Любой").tag(Double?.none)
                    ForEach(ratingOptions, id: \.self) { val in
                        Text(String(format: "%.1f+", val)).tag(Optional(val))
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()

                Rectangle()
                    .fill(Color(UIColor.separator).opacity(0.3))
                    .frame(width: 1, height: 72)
                    .padding(.horizontal, 4)

                Picker("Год", selection: $filters.yearFrom) {
                    Text("Любой").tag(Int?.none)
                    ForEach(yearOptions, id: \.self) { year in
                        Text(verbatim: "\(year)").tag(Optional(year))
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .frame(height: 116)
            .padding(.bottom, 6)
        }
        .background(Color(UIColor.secondarySystemGroupedBackground).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
