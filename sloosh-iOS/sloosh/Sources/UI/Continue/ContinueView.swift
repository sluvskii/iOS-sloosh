import SwiftUI

struct ContinueView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Здесь будет история просмотров")
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Продолжить")
        }
    }
}
