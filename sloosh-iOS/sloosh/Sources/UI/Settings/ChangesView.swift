import SwiftUI

private struct ChangeEntry: Identifiable {
    let id = UUID()
    let version: String
    let notes: String
}

struct ChangesView: View {
    private let entries = [
        ChangeEntry(version: "Текущая iOS-ветка", notes: "Liquid Glass интерфейс, новый details screen, source switching, Alloha parser и Collaps playback."),
        ChangeEntry(version: "Поиск 2.0", notes: "История запросов, сетка результатов, пагинация и более удобная навигация по каталогу."),
        ChangeEntry(version: "Инфо и Credits", notes: "Новые экраны About, Changes и Credits с загрузкой списка поддержки."),
        ChangeEntry(version: "Дальнейший перенос", notes: "Следующие шаги: избранное, профиль, watch progress, расширенные настройки и offline-функции без torrent-части.")
    ]

    var body: some View {
        List {
            Section("История изменений") {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.version)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(entry.notes)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Изменения")
        .navigationBarTitleDisplayMode(.inline)
    }
}
