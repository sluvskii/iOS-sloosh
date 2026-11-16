import SwiftUI

enum FilterContext {
    case home
    case search
}

struct SearchFilterSheet: View {
    @Binding var filters: SearchFilters
    var context: FilterContext = .search
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SearchFilters

    init(filters: Binding<SearchFilters>, context: FilterContext = .search) {
        self._filters = filters
        self.context = context
        self._draft = State(initialValue: filters.wrappedValue.normalized)
    }

    private let currentYear = Calendar.current.component(.year, from: Date())

    private var ratingOptions: [Double] {
        stride(from: 0.5, through: 10.0, by: 0.5).map { round($0 * 10) / 10 }
    }

    private var yearOptions: [Int] {
        Array(stride(from: currentYear + 3, through: 1880, by: -1))
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
                    if context == .home { studioRow }
                    genreRow
                    countryRow
                }

                // 3. Explicit inclusive ranges, including archive and future releases.
                Section("Рейтинг") {
                    Picker("От", selection: $draft.ratingFrom) {
                        Text("Любой").tag(Double?.none)
                        ForEach(ratingOptions, id: \.self) { Text(String(format: "%.1f", $0)).tag(Optional($0)) }
                    }
                    Picker("До", selection: $draft.ratingTo) {
                        Text("Любой").tag(Double?.none)
                        ForEach(ratingOptions, id: \.self) { Text(String(format: "%.1f", $0)).tag(Optional($0)) }
                    }
                }
                Section("Год выпуска") {
                    Picker("От", selection: $draft.yearFrom) {
                        Text("Любой").tag(Int?.none)
                        ForEach(yearOptions, id: \.self) { Text(String($0)).tag(Optional($0)) }
                    }
                    Picker("До", selection: $draft.yearTo) {
                        Text("Любой").tag(Int?.none)
                        ForEach(yearOptions, id: \.self) { Text(String($0)).tag(Optional($0)) }
                    }
                }
                Section {
                    Button("Отмена") { dismiss() }.foregroundStyle(.primary)
                } footer: {
                    Text("Жанры: все выбранные. Страны: любая из выбранных. Условия действуют вместе. Изменения применятся по кнопке ✓.")
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
                    .padding(.bottom, 4)
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
        .presentationDetents([.medium, .large])
        .onChange(of: draft.yearFrom) { _, value in
            if let value, let end = draft.yearTo, value > end { draft.yearTo = value }
        }
        .onChange(of: draft.yearTo) { _, value in
            if let value, let start = draft.yearFrom, value < start { draft.yearFrom = value }
        }
        .onChange(of: draft.ratingFrom) { _, value in
            if let value, let end = draft.ratingTo, value > end { draft.ratingTo = value }
        }
        .onChange(of: draft.ratingTo) { _, value in
            if let value, let start = draft.ratingFrom, value < start { draft.ratingFrom = value }
        }
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        ZStack {
            Text("Фильтры")
                .font(.system(size: 18, weight: .semibold))
                .backdropForeground()
                .lineLimit(1)
                .frame(maxWidth: 200)

            HStack {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.prepare()
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        draft = SearchFilters()
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(draft.isEmpty ? Color.secondary.opacity(0.35) : Color.primary)
                        .glassForeground(isEnabled: !draft.isEmpty)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.glassPress)
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(draft.isEmpty)
                .accessibilityLabel("Сбросить")

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    filters = draft.normalized
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .glassForeground()
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.glassPress)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Применить фильтры")
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

            Picker("Тип контента", selection: $draft.type) {
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
                        draft.order = nil
                    } label: {
                        HStack {
                            Text("Релевантность")
                            if draft.order == nil { Image(systemName: "checkmark") }
                        }
                    }
                } else {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.prepare()
                        generator.impactOccurred()
                        draft.order = nil
                    } label: {
                        HStack {
                            Text("Смотрят сейчас")
                            if draft.order == nil { Image(systemName: "checkmark") }
                        }
                    }
                }
                if context == .home {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.prepare()
                        generator.impactOccurred()
                        draft.order = "NUM_VOTE"
                    } label: {
                        HStack {
                            Text("По популярности")
                            if draft.order == "NUM_VOTE" { Image(systemName: "checkmark") }
                        }
                    }
                }
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    draft.order = "RATING"
                } label: {
                    HStack {
                        Text("По рейтингу")
                        if draft.order == "RATING" { Image(systemName: "checkmark") }
                    }
                }
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    draft.order = "YEAR"
                } label: {
                    HStack {
                        Text("По году выпуска")
                        if draft.order == "YEAR" { Image(systemName: "checkmark") }
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
                        draft.studio = nil
                    }
                } label: {
                    HStack {
                        Text("Любая")
                        if draft.studio == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Section("Студии") {
                    ForEach(StudioBrand.all.filter { !$0.isNetwork }) { brand in
                        let isSelected = draft.studio == brand.id
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                draft.studio = isSelected ? nil : brand.id
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
                        let isSelected = draft.studio == brand.id
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                draft.studio = isSelected ? nil : brand.id
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
                        draft.selectedGenres = []
                    }
                } label: {
                    HStack {
                        Text("Любой")
                        if draft.selectedGenres.isEmpty {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(genresList, id: \.self) { genre in
                    let isSelected = draft.selectedGenres.contains(genre.lowercased())
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.prepare()
                        generator.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            var current = draft.selectedGenres
                            if isSelected {
                                current.remove(genre.lowercased())
                            } else {
                                current.insert(genre.lowercased())
                            }
                            draft.selectedGenres = current
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
                        draft.selectedCountries = []
                    }
                } label: {
                    HStack {
                        Text("Любая")
                        if draft.selectedCountries.isEmpty {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                ForEach(countriesList, id: \.self) { country in
                    let isSelected = draft.selectedCountries.contains(country)
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.prepare()
                        generator.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            var current = draft.selectedCountries
                            if isSelected {
                                current.remove(country)
                            } else {
                                current.insert(country)
                            }
                            draft.selectedCountries = current
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

    // MARK: - Formatters & Titles

    private var currentStudioTitle: String {
        guard let studioId = draft.studio, let brand = StudioBrand.find(by: studioId) else {
            return "Любая"
        }
        return brand.name
    }

    private var currentGenreTitle: String {
        let selected = draft.selectedGenres
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
        let selected = draft.selectedCountries
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
        switch draft.order {
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
