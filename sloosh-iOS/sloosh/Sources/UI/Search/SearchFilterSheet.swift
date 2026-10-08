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

    @State private var scrollOffset: CGFloat = 0

    private var blurOpacity: Double {
        let progress = max(0, scrollOffset) / 25.0
        return min(1.0, Double(progress))
    }

    var body: some View {
        NavigationStack {
            List {
                // 1. Content Type (only in Search context)
                if context == .search {
                    Section {
                        contentTypeRow
                    }
                }

                // 2. Main Parameters Card (Сортировка, Студия, Жанр, Страна)
                Section {
                    sortRow
                    studioRow
                    genreRow
                    countryRow
                }

                // 3. Dual Wheel Drum Picker (Рейтинг и Год выпуска)
                Section {
                    ratingAndYearWheelCard
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListHeaderHeight, .leastNonzeroMagnitude)
            .scrollBounceBehavior(.always)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, newOffset in
                scrollOffset = newOffset
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                headerBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, -6)
                    .background(
                        VariableBlurView(tintColor: .clear, tintOpacity: 0.0)
                            .padding(.bottom, -30)
                            .ignoresSafeArea(edges: .top)
                            .opacity(blurOpacity)
                            .animation(.easeInOut(duration: 0.2), value: blurOpacity)
                    )
            }
            .background(Color.clear)
        }
        .presentationDetents(context == .search ? [.height(550)] : [.height(466)])
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        ZStack {
            Text("Фильтры")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 200)

            HStack {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.prepare()
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        filters = SearchFilters()
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(filters.isEmpty ? Color.secondary.opacity(0.35) : Color.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.glassPress)
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(filters.isEmpty)
                .accessibilityLabel("Сбросить")

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.glassPress)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Закрыть")
            }
        }
    }

    // MARK: - Content Type Row (Segmented, Standard Settings Style)

    private var contentTypeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .foregroundStyle(Color.slooshAccent)
                    .font(.system(size: 18))
                    .frame(width: 24)

                Text("Тип контента")
                    .font(.body)
            }

            Picker("Тип контента", selection: $filters.type) {
                Text("Все").tag(String?.none)
                Text("Фильмы").tag(Optional("FILM"))
                Text("Сериалы").tag(Optional("TV_SERIES"))
                Text("Мульты").tag(Optional("CARTOON"))
                Text("Аниме").tag(Optional("ANIME"))
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Filter Rows (Standard Settings Style, Only Trailing Selection Animates)

    private var sortRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.arrow.down")
                .foregroundStyle(Color.slooshAccent)
                .font(.system(size: 18))
                .frame(width: 24)

            Text("Сортировка")
                .font(.body)
                .foregroundStyle(Color.primary)

            Spacer()

            Menu {
                if context == .search {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.prepare()
                        generator.impactOccurred()
                        filters.order = nil
                    } label: {
                        HStack {
                            Text("Релевантность")
                            if filters.order == nil { Image(systemName: "checkmark") }
                        }
                    }
                } else {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.prepare()
                        generator.impactOccurred()
                        filters.order = nil
                    } label: {
                        HStack {
                            Text("Смотрят сейчас")
                            if filters.order == nil { Image(systemName: "checkmark") }
                        }
                    }
                }
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    filters.order = "NUM_VOTE"
                } label: {
                    HStack {
                        Text("По популярности")
                        if filters.order == "NUM_VOTE" { Image(systemName: "checkmark") }
                    }
                }
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    filters.order = "RATING"
                } label: {
                    HStack {
                        Text("По рейтингу")
                        if filters.order == "RATING" { Image(systemName: "checkmark") }
                    }
                }
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    filters.order = "YEAR"
                } label: {
                    HStack {
                        Text("По году выпуска")
                        if filters.order == "YEAR" { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentSortTitle)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(Color.slooshAccent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.slooshAccent)
                }
                .contentShape(Rectangle())
            }
        }
    }

    private var studioRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "tv")
                .foregroundStyle(Color.slooshAccent)
                .font(.system(size: 18))
                .frame(width: 24)

            Text("Студия")
                .font(.body)
                .foregroundStyle(Color.primary)

            Spacer()

            Menu {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        filters.studio = nil
                    }
                } label: {
                    HStack {
                        Text("Любая")
                        if filters.studio == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Section("Студии") {
                    ForEach(StudioBrand.all.filter { !$0.isNetwork }) { brand in
                        let isSelected = filters.studio == brand.id
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                filters.studio = isSelected ? nil : brand.id
                            }
                        } label: {
                            HStack {
                                Text(brand.name)
                                if isSelected {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Section("Стриминги") {
                    ForEach(StudioBrand.all.filter { $0.isNetwork }) { brand in
                        let isSelected = filters.studio == brand.id
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                filters.studio = isSelected ? nil : brand.id
                            }
                        } label: {
                            HStack {
                                Text(brand.name)
                                if isSelected {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentStudioTitle)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(Color.slooshAccent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.slooshAccent)
                }
                .contentShape(Rectangle())
            }
        }
    }

    private var genreRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "theatermasks")
                .foregroundStyle(Color.slooshAccent)
                .font(.system(size: 18))
                .frame(width: 24)

            Text("Жанр")
                .font(.body)
                .foregroundStyle(Color.primary)

            Spacer()

            Menu {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
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
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(Color.slooshAccent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.slooshAccent)
                }
                .contentShape(Rectangle())
            }
        }
    }

    private var countryRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .foregroundStyle(Color.slooshAccent)
                .font(.system(size: 18))
                .frame(width: 24)

            Text("Страна")
                .font(.body)
                .foregroundStyle(Color.primary)

            Spacer()

            Menu {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
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
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(Color.slooshAccent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.slooshAccent)
                }
                .contentShape(Rectangle())
            }
        }
    }

    // MARK: - Dual Wheel Drum Picker (Рейтинг и Год выпуска)

    private var ratingAndYearWheelCard: some View {
        VStack(spacing: 2) {
            // Header: Clean column titles above each wheel
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.slooshAccent)
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
                        .foregroundStyle(Color.slooshAccent)
                    Text("Год выпуска")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 10)

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
    }

    // MARK: - Formatters & Titles

    private var currentStudioTitle: String {
        guard let studioId = filters.studio, let brand = StudioBrand.find(by: studioId) else {
            return "Любая"
        }
        return brand.name
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
}
