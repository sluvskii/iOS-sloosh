import SwiftUI

struct FavoritesView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "heart.slash")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)
                Text("No favorites yet")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .padding()
            }
            .navigationTitle("Favorites")
        }
    }
}
