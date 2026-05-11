import SwiftUI

struct DownloadsView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.gray.opacity(0.5))
                    .padding(.bottom, 8)
                Text("Нет загрузок")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Скачивайте фильмы для\nпросмотра без интернета")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .navigationTitle("Загрузки")
            .background(Color(UIColor.systemGroupedBackground))
        }
    }
}
