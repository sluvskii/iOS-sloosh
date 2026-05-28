import SwiftUI

struct TestView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                ForEach(0..<100) { i in
                    Text("Item \(i)")
                }
            }
            .navigationTitle("Главная")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Cat", selection: .constant(0)) {
                        Text("1").tag(0)
                        Text("2").tag(1)
                    }.pickerStyle(.segmented)
                }
            }
        }
    }
}
