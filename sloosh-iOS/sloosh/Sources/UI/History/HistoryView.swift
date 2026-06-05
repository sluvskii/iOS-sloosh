import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("История просмотров будет здесь")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("История")
        }
    }
}
