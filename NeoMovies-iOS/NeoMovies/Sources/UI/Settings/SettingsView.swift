import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Основные")) {
                    NavigationLink("Язык", destination: Text("Настройки языка"))
                    NavigationLink("Настройки плеера", destination: Text("Настройки плеера"))
                    NavigationLink("Источники", destination: Text("Настройки источников"))
                }
                
                Section(header: Text("О приложении")) {
                    NavigationLink("О NeoMovies", destination: Text("Информация"))
                    NavigationLink("Авторы", destination: Text("Титры"))
                }
            }
            .navigationTitle("Настройки")
        }
    }
}
