import SwiftUI

enum FilterContext {
    case home
    case search
}

struct SearchFilterSheet: View {
    @Binding var filters: SearchFilters
    var context: FilterContext = .search
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Тип")) {
                    Picker("Тип", selection: $filters.type) {
                        Text("Всё").tag(String?.none)
                        Text("Фильмы").tag(String?.some("FILM"))
                        Text("Сериалы").tag(String?.some("TV_SERIES"))
                    }
                    .pickerStyle(.segmented)
                }

                Section(header: Text("Сортировка")) {
                    Picker("Сортировка", selection: $filters.order) {
                        if context == .search {
                            Text("Релевантность").tag(String?.none)
                            Text("По популярности").tag(String?.some("NUM_VOTE"))
                        } else {
                            Text("Смотрят сейчас").tag(String?.none)
                        }
                        Text("По рейтингу").tag(String?.some("RATING"))
                        Text("По году выпуска").tag(String?.some("YEAR"))
                    }
                    .pickerStyle(.menu)
                }

                Section(header: Text("Рейтинг"), footer: Text("Минимальный рейтинг фильма на Кинопоиске")) {
                    HStack {
                        Text(filters.ratingFrom == nil ? "Любой" : String(format: "%.1f", filters.ratingFrom!))
                            .frame(width: 50, alignment: .leading)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(filters.ratingFrom == nil ? .secondary : .primary)
                        
                        Slider(
                            value: Binding(
                                get: { filters.ratingFrom ?? 1.0 },
                                set: { filters.ratingFrom = $0 <= 1.0 ? nil : $0 }
                            ),
                            in: 1.0...10.0,
                            step: 0.5
                        )
                        .tint(Color.slooshAccent)
                    }
                }
                
                Section(header: Text("Год выпуска"), footer: Text("Искать начиная с указанного года")) {
                    let currentYear = Calendar.current.component(.year, from: Date())
                    HStack {
                        Text(filters.yearFrom == nil ? "Любой" : String(filters.yearFrom!))
                            .frame(width: 55, alignment: .leading)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(filters.yearFrom == nil ? .secondary : .primary)
                        
                        Slider(
                            value: Binding(
                                get: { Double(filters.yearFrom ?? 1990) },
                                set: { filters.yearFrom = $0 <= 1990.0 ? nil : Int($0) }
                            ),
                            in: 1990.0...Double(currentYear),
                            step: 1
                        )
                        .tint(Color.slooshAccent)
                    }
                }
            }
            .scrollContentBackground(.hidden) // For custom background
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Сбросить") {
                        withAnimation {
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
                }
            }
            .background(Color.clear)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }
}
