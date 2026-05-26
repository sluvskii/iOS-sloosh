import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Версия \(version) (\(build))"
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Spacer()
                
                // Иконка приложения
                if let iconDict = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
                   let primaryIcon = iconDict["CFBundlePrimaryIcon"] as? [String: Any],
                   let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
                   let lastIcon = iconFiles.last,
                   let uiImage = UIImage(named: lastIcon) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                } else {
                    // Fallback если иконка не найдена в бандле
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: 120, height: 120)
                        .overlay(
                            Text("S")
                                .font(.system(size: 60, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        )
                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                }
                
                Text("sloosh")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(appVersion)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 16)
            }
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
