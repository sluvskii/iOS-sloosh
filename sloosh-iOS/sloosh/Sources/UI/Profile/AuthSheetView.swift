import SwiftUI

public struct AuthSheetView: View {
    enum AuthTab: String, CaseIterable {
        case signIn = "Вход"
        case signUp = "Регистрация"
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var authRepo = AuthRepository.shared
    
    @State private var selectedTab: AuthTab = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var name: String = ""
    @State private var showResetAlert: Bool = false
    @State private var resetEmail: String = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Режим", selection: $selectedTab.animation(.spring(response: 0.3, dampingFraction: 0.8))) {
                        ForEach(AuthTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section {
                    if selectedTab == .signUp {
                        HStack(spacing: 12) {
                            Image(systemName: "person.fill")
                                .foregroundStyle(Color.slooshAccent)
                                .frame(width: 20)
                            TextField("Ваше имя (необязательно)", text: $name)
                        }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(Color.slooshAccent)
                            .frame(width: 20)
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(Color.slooshAccent)
                            .frame(width: 20)
                        SecureField("Пароль", text: $password)
                    }
                }

                if selectedTab == .signIn {
                    Section {
                        Button("Забыли пароль?") {
                            resetEmail = email
                            showResetAlert = true
                        }
                        .foregroundStyle(Color.slooshAccent)
                    }
                }

                Section {
                    Button {
                        Task {
                            let success: Bool
                            if selectedTab == .signIn {
                                success = await authRepo.signIn(email: email, password: password)
                            } else {
                                success = await authRepo.signUp(email: email, password: password, displayName: name)
                            }
                            if success { dismiss() }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if authRepo.isLoading {
                                ProgressView()
                            } else {
                                Text(selectedTab == .signIn ? "Войти" : "Зарегистрироваться")
                                    .font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.slooshAccent)
                    .foregroundColor(.black)
                    .disabled(authRepo.isLoading)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(selectedTab == .signIn ? "Авторизация" : "Регистрация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .presentationBackground { Color.clear.glassEffect(in: .rect) }
            .presentationDragIndicator(.visible)
            .alert("Сброс пароля", isPresented: $showResetAlert) {
                TextField("Введите Email", text: $resetEmail)
                Button("Отмена", role: .cancel) {}
                Button("Отправить") {
                    Task {
                        _ = await authRepo.resetPassword(email: resetEmail)
                    }
                }
            } message: {
                Text("Инструкция по сбросу пароля будет отправлена на ваш Email.")
            }
        }
    }
}
