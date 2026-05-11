import SwiftUI

struct DownloadsView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)
                Text("No downloads yet")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding()
            }
            .navigationTitle("Downloads")
        }
    }
}
