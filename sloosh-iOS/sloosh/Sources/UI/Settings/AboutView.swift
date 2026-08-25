import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Версия \(version) (\(build))"
    }

    @State private var scrollOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    
    private var blurOpacity: Double {
        let progress = max(0, scrollOffset) / 30.0
        return min(1.0, Double(progress))
    }

    @State private var secretTapCount: Int = 0
    @State private var showSecretPasscodeAlert: Bool = false
    @State private var enteredPasscode: String = ""

    var body: some View {
        List {
            // Секция заголовка с логотипом
            Section {
                VStack(spacing: 12) {
                    Spacer(minLength: 8)
                    
                    if UIImage(named: "LogoText") != nil {
                        Image("LogoText")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(Color.slooshAccent)
                            .frame(height: 64)
                    } else {
                        Text("sloosh")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    
                    Text(appVersion)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .onTapGesture {
                            secretTapCount += 1
                            if secretTapCount >= 5 {
                                secretTapCount = 0
                                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                showSecretPasscodeAlert = true
                            }
                        }
                    
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            .alert("Режим администратора", isPresented: $showSecretPasscodeAlert) {
                SecureField("Мастер-ключ", text: $enteredPasscode)
                Button("Активировать") {
                    let success = AuthRepository.shared.activateAdminModeWithPasscode(enteredPasscode)
                    enteredPasscode = ""
                    if success {
                        ToastManager.shared.show("Права администратора успешно активированы! 🛡️")
                    } else {
                        ToastManager.shared.show("Неверный мастер-ключ")
                    }
                }
                Button("Отмена", role: .cancel) {
                    enteredPasscode = ""
                }
            } message: {
                Text("Введите мастер-ключ создателя для постоянной активации админ-панели на этом устройстве.")
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
        .environment(\.defaultMinListHeaderHeight, .leastNonzeroMagnitude)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("О приложении")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                
                HStack {
                    TelegramGlassIconButton(systemName: "chevron.left") {
                        dismiss()
                    }
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .background(
                VariableBlurView(tintOpacity: 1.0)
                    .padding(.bottom, -60)
                    .ignoresSafeArea(edges: .top)
                    .opacity(blurOpacity)
                    .animation(.easeInOut(duration: 0.2), value: blurOpacity)
            )
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newOffset in
            scrollOffset = newOffset
        }
        .fullWidthSwipeBack()
    }
}
