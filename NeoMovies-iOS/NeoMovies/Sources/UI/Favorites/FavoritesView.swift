import SwiftUI

struct FavoritesView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.gray.opacity(0.5))
                    .padding(.bottom, 8)
                Text("Пока нет избранного")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Добавляйте фильмы и сериалы,\nчтобы посмотреть их позже")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .navigationTitle("Избранное")
            .background(Color(UIColor.systemGroupedBackground))
        }
    }
}
