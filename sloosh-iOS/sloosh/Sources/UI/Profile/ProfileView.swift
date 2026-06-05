import SwiftUI

struct ProfileView: View {
    @State private var showingSettings = false
    
    var body: some View {
        NavigationStack {
            VStack {
                Text("Избранное и Подборки будут здесь")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Профиль")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}
