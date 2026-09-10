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
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
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
        .presentationDetents(context == .search ? [.fraction(0.62), .large] : [.fraction(0.52), .large])
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

            HStack(spacing: 6) {
                typeCapsule(title: "Все", tag: nil)
                typeCapsule(title: "Фильмы", tag: "FILM")
                typeCapsule(title: "Сериалы", tag: "TV_SERIES")
                typeCapsule(title: "Мульты", tag: "CARTOON")
                typeCapsule(title: "Аниме", tag: "ANIME")
            }
        }
    }

    private func typeCapsule(title: String, tag: String?) -> some View {
        let isSelected = filters.type == tag
        return Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                filters.type = tag
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white : Color.clear)
                )
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .glassEffect(isSelected ? .regular : .regular.interactive(), in: Capsule())
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
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            filters.selectedGenres = []
                        }
                    } label: {
                        HStack {
                            Text("Любой")
                            if filters.selectedGenres.isEmpty {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(genresList, id: \.self) { genre in
                        let isSelected = filters.selectedGenres.contains(genre.lowercased())
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                var current = filters.selectedGenres
                                if isSelected {
                                    current.remove(genre.lowercased())
                                } else {
                                    current.insert(genre.lowercased())
                                }
                                filters.selectedGenres = current
                            }
                        } label: {
                            HStack {
                                Text(genreDisplayName(genre))
                                if isSelected {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .menuActionDismissBehavior(.disabled)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentGenreTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
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
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            filters.selectedCountries = []
                        }
                    } label: {
                        HStack {
                            Text("Любая")
                            if filters.selectedCountries.isEmpty {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(countriesList, id: \.self) { country in
                        let isSelected = filters.selectedCountries.contains(country)
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                var current = filters.selectedCountries
                                if isSelected {
                                    current.remove(country)
                                } else {
                                    current.insert(country)
                                }
                                filters.selectedCountries = current
                            }
                        } label: {
                            HStack {
                                Text(country)
                                if isSelected {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .menuActionDismissBehavior(.disabled)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentCountryTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
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

    private var currentGenreTitle: String {
        let selected = filters.selectedGenres
        if selected.isEmpty {
            return "Любой"
        } else if selected.count == 1, let first = selected.first {
            return genreDisplayName(first)
        } else if selected.count == 2 {
            let sorted = selected.map { genreDisplayName($0) }.sorted()
            return sorted.joined(separator: ", ")
        } else {
            return "Выбрано: \(selected.count)"
        }
    }

    private var currentCountryTitle: String {
        let selected = filters.selectedCountries
        if selected.isEmpty {
            return "Любая"
        } else if selected.count == 1, let first = selected.first {
            return first
        } else if selected.count == 2 {
            let sorted = Array(selected).sorted()
            return sorted.joined(separator: ", ")
        } else {
            return "Выбрано: \(selected.count)"
        }
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
