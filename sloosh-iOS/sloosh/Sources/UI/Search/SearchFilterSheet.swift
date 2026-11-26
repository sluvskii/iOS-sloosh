import SwiftUI
import UIKit

enum FilterContext {
    case home
    case search
}

struct SearchFilterSheet: View {
    @Binding var filters: SearchFilters
    var context: FilterContext = .search
    @Environment(\.dismiss) private var dismiss
    @Namespace private var contentTypeNamespace
    @State private var draft: SearchFilters
    @State private var scrollOffset: CGFloat = 0

    init(filters: Binding<SearchFilters>, context: FilterContext = .search) {
        self._filters = filters
        self.context = context
        self._draft = State(initialValue: filters.wrappedValue.normalized)
    }

    private let currentYear = Calendar.current.component(.year, from: Date())

    private let contentTypes: [(title: String, value: String?)] = [
        ("Все", nil),
        ("Фильмы", "FILM"),
        ("Сериалы", "TV_SERIES"),
        ("Мульты", "CARTOON"),
        ("Аниме", "ANIME")
    ]

    private let ratingPresets: [Double] = [9.0, 8.5, 8.0, 7.5, 7.0, 6.0, 5.0]
    private var ratingOptions: [Double] {
        stride(from: 1.0, through: 9.5, by: 0.5).map { round($0 * 10) / 10 }
    }

    private var yearOptions: [Int] {
        Array(stride(from: currentYear, through: 1960, by: -1))
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

    private var blurOpacity: Double {
        min(1.0, Double(max(0, scrollOffset) / 25.0))
    }

    private var hasPendingChanges: Bool {
        draft.normalized != filters.normalized
    }

    var body: some View {
        NavigationStack {
            List {
                if context == .search {
                    Section {
                        contentTypeRow
                    }
                }

                Section {
                    sortRow
                    if context == .home { studioRow }
                    genreRow
                    countryRow
                }

                Section {
                    ratingRow
                    yearRow
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListHeaderHeight, .leastNonzeroMagnitude)
            .scrollBounceBehavior(.basedOnSize)
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
                    .padding(.bottom, 6)
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
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: draft.type)
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        draft = SearchFilters()
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(draft.isEmpty ? Color.secondary.opacity(0.35) : Color.primary)
                        .glassForeground(isEnabled: !draft.isEmpty)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.glassPress)
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(draft.isEmpty)
                .accessibilityLabel("Сбросить фильтры")

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    filters = draft.normalized
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(hasPendingChanges ? Color.slooshAccent : Color.primary)
                        .glassForeground(isEnabled: GlassForegroundAppearance.shouldBlend(tint: hasPendingChanges ? Color.slooshAccent : .primary))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.glassPress)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Применить фильтры")
            }
        }
    }

    // MARK: - Content Type Sliding Pill Bar (Zero Truncation)

    private var contentTypeRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.on.rectangle")
                    .foregroundStyle(Color.slooshAccent)
                    .font(.system(size: 18))
                    .frame(width: 24)

                Text("Тип контента")
                    .font(.body)
            }

            HStack(spacing: 2) {
                ForEach(contentTypes, id: \.title) { option in
                    let isSelected = draft.type == option.value
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            draft.type = option.value
                        }
                    } label: {
                        Text(option.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.16))
                                        .matchedGeometryEffect(id: "contentTypePill", in: contentTypeNamespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.07), in: Capsule())
        }
        .padding(.vertical, 4)
    }

    // MARK: - Core Parameter Rows

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
                sortOptionButton(title: context == .search ? "Релевантность" : "Смотрят сейчас", value: nil)
                if context == .home {
                    sortOptionButton(title: "По популярности", value: "NUM_VOTE")
                }
                sortOptionButton(title: "По рейтингу", value: "RATING")
                sortOptionButton(title: "По году выпуска", value: "YEAR")
            } label: {
                trailingMenuLabel(currentSortTitle)
            }
        }
    }

    private func sortOptionButton(title: String, value: String?) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            draft.order = value
        } label: {
            HStack {
                Text(title)
                if draft.order == value { Image(systemName: "checkmark") }
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
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    draft.studio = nil
                } label: {
                    HStack {
                        Text("Любая")
                        if draft.studio == nil { Image(systemName: "checkmark") }
                    }
                }

                Section("Студии") {
                    ForEach(StudioBrand.all.filter { !$0.isNetwork }) { brand in
                        studioOption(brand)
                    }
                }

                Section("Стриминги") {
                    ForEach(StudioBrand.all.filter { $0.isNetwork }) { brand in
                        studioOption(brand)
                    }
                }
            } label: {
                trailingMenuLabel(currentStudioTitle)
            }
        }
    }

    private func studioOption(_ brand: StudioBrand) -> some View {
        let isSelected = draft.studio == brand.id
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            draft.studio = isSelected ? nil : brand.id
        } label: {
            HStack {
                Text(brand.name)
                if isSelected { Image(systemName: "checkmark") }
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
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    draft.selectedGenres = []
                } label: {
                    HStack {
                        Text("Любой")
                        if draft.selectedGenres.isEmpty { Image(systemName: "checkmark") }
                    }
                }

                Divider()

                ForEach(genresList, id: \.self) { genre in
                    let isSelected = draft.selectedGenres.contains(genre.lowercased())
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        var current = draft.selectedGenres
                        if isSelected {
                            current.remove(genre.lowercased())
                        } else {
                            current.insert(genre.lowercased())
                        }
                        draft.selectedGenres = current
                    } label: {
                        HStack {
                            Text(genreDisplayName(genre))
                            if isSelected { Image(systemName: "checkmark") }
                        }
                    }
                    .menuActionDismissBehavior(.disabled)
                }
            } label: {
                trailingMenuLabel(currentGenreTitle)
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
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    draft.selectedCountries = []
                } label: {
                    HStack {
                        Text("Любая")
                        if draft.selectedCountries.isEmpty { Image(systemName: "checkmark") }
                    }
                }

                Divider()

                ForEach(countriesList, id: \.self) { country in
                    let isSelected = draft.selectedCountries.contains(country)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        var current = draft.selectedCountries
                        if isSelected {
                            current.remove(country)
                        } else {
                            current.insert(country)
                        }
                        draft.selectedCountries = current
                    } label: {
                        HStack {
                            Text(country)
                            if isSelected { Image(systemName: "checkmark") }
                        }
                    }
                    .menuActionDismissBehavior(.disabled)
                }
            } label: {
                trailingMenuLabel(currentCountryTitle)
            }
        }
    }

    // MARK: - Rating & Year Rows

    private var ratingRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .foregroundStyle(Color.slooshAccent)
                .font(.system(size: 17))
                .frame(width: 24)

            Text("Рейтинг")
                .font(.body)
                .foregroundStyle(Color.primary)

            Spacer()

            Menu {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    draft.ratingFrom = nil
                    draft.ratingTo = nil
                } label: {
                    HStack {
                        Text("Любой")
                        if draft.ratingFrom == nil && draft.ratingTo == nil { Image(systemName: "checkmark") }
                    }
                }

                Divider()

                ForEach(ratingPresets, id: \.self) { minRating in
                    let isSelected = draft.ratingFrom == minRating && draft.ratingTo == nil
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        draft.ratingFrom = minRating
                        draft.ratingTo = nil
                    } label: {
                        HStack {
                            Text(String(format: "%.1f и выше", locale: Locale(identifier: "ru_RU"), minRating))
                            if isSelected { Image(systemName: "checkmark") }
                        }
                    }
                }

                Divider()

                Menu("Точный минимум") {
                    ForEach(Array(ratingOptions.reversed()), id: \.self) { value in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            draft.ratingFrom = value
                            if let to = draft.ratingTo, value > to { draft.ratingTo = nil }
                        } label: {
                            HStack {
                                Text(String(format: "От %.1f", locale: Locale(identifier: "ru_RU"), value))
                                if draft.ratingFrom == value { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            } label: {
                trailingMenuLabel(currentRatingTitle)
            }
        }
    }

    private var yearRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .foregroundStyle(Color.slooshAccent)
                .font(.system(size: 17))
                .frame(width: 24)

            Text("Год выпуска")
                .font(.body)
                .foregroundStyle(Color.primary)

            Spacer()

            Menu {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    draft.yearFrom = nil
                    draft.yearTo = nil
                } label: {
                    HStack {
                        Text("Любой")
                        if draft.yearFrom == nil && draft.yearTo == nil { Image(systemName: "checkmark") }
                    }
                }

                Divider()

                yearRangeButton(title: "\(currentYear)", from: currentYear, to: currentYear)
                yearRangeButton(title: "\(currentYear - 1)", from: currentYear - 1, to: currentYear - 1)
                yearRangeButton(title: "\(currentYear - 2)", from: currentYear - 2, to: currentYear - 2)

                Divider()

                yearRangeButton(title: "2020-е", from: 2020, to: currentYear)
                yearRangeButton(title: "2010-е", from: 2010, to: 2019)
                yearRangeButton(title: "2000-е", from: 2000, to: 2009)
                yearRangeButton(title: "1990-е", from: 1990, to: 1999)
                yearRangeButton(title: "Классика (до 1990)", from: nil, to: 1989)

                Divider()

                Menu("Выбрать год…") {
                    ForEach(yearOptions, id: \.self) { year in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            draft.yearFrom = year
                            draft.yearTo = year
                        } label: {
                            HStack {
                                Text(verbatim: "\(year)")
                                if draft.yearFrom == year && draft.yearTo == year {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                trailingMenuLabel(currentYearTitle)
            }
        }
    }

    private func yearRangeButton(title: String, from: Int?, to: Int?) -> some View {
        let isSelected = draft.yearFrom == from && draft.yearTo == to
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            draft.yearFrom = from
            draft.yearTo = to
        } label: {
            HStack {
                Text(title)
                if isSelected { Image(systemName: "checkmark") }
            }
        }
    }

    private func trailingMenuLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.body)
                .lineLimit(1)
                .foregroundStyle(Color.slooshAccent)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.slooshAccent)
        }
        .contentShape(Rectangle())
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

    private var currentRatingTitle: String {
        let normalized = draft.normalized
        func format(_ value: Double) -> String {
            String(format: "%.1f", locale: Locale(identifier: "ru_RU"), value)
        }
        if let from = normalized.ratingFrom, let to = normalized.ratingTo {
            return "\(format(from))–\(format(to))"
        }
        if let from = normalized.ratingFrom {
            return "от \(format(from))"
        }
        if let to = normalized.ratingTo {
            return "до \(format(to))"
        }
        return "Любой"
    }

    private var currentYearTitle: String {
        let normalized = draft.normalized
        if let from = normalized.yearFrom, let to = normalized.yearTo {
            return from == to ? String(from) : "\(from)–\(to)"
        }
        if let from = normalized.yearFrom {
            return "с \(from)"
        }
        if let to = normalized.yearTo {
            return "до \(to)"
        }
        return "Любой"
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
