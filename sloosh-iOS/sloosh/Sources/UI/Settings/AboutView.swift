import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Версия \(version) (\(build))"
    }

    var body: some View {
        List {
            // Секция заголовка с логотипом
            Section {
                VStack(spacing: 12) {
                    Spacer(minLength: 8)
                    
                    if UIImage(named: "LogoText") != nil {
                        Image("LogoText")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 64)
                    } else {
                        Text("sloosh")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    
                    Text(appVersion)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            
            // Секция ссылок сообщества
            Section("Сообщество") {
                Link(destination: URL(string: "https://t.me/slooshapp")!) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 18))
                            .frame(width: 24)
                        Text("Telegram-канал")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                }
                
                Link(destination: URL(string: "https://t.me/slooshbeta")!) {
                    HStack {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 18))
                            .frame(width: 24)
                        Text("Telegram-канал (Beta)")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14))
                    }
                }
            }
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }
}
