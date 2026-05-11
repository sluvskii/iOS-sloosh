import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("General")) {
                    NavigationLink("Language", destination: Text("Language Settings"))
                    NavigationLink("Player Settings", destination: Text("Player Settings"))
                    NavigationLink("Sources", destination: Text("Source Settings"))
                }
                
                Section(header: Text("About")) {
                    NavigationLink("About NeoMovies", destination: Text("About Info"))
                    NavigationLink("Credits", destination: Text("Credits"))
                }
            }
            .navigationTitle("Settings")
        }
    }
}
