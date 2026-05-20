import SwiftUI

private struct StaticCreditItem: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let url: String
}

struct CreditsView: View {
    @StateObject private var viewModel = CreditsViewModel()
    @Environment(\.openURL) private var openURL

    private let libraries = [
        StaticCreditItem(name: "SwiftUI", description: "Основной UI слой приложения", url: "https://developer.apple.com/xcode/swiftui/"),
        StaticCreditItem(name: "AVFoundation", description: "Нативное воспроизведение видео", url: "https://developer.apple.com/av-foundation/"),
        StaticCreditItem(name: "WebKit", description: "Парсинг iframe и интеграция Alloha", url: "https://developer.apple.com/documentation/webkit"),
        StaticCreditItem(name: "Network.framework", description: "Локальный HLS proxy", url: "https://developer.apple.com/documentation/network")
    ]

    private let inspiration = [
        StaticCreditItem(name: "NeoMovies Android", description: "Основной референс архитектуры и функциональности", url: "https://github.com/Neo-Open-Source/neomovies-android"),
        StaticCreditItem(name: "Findroid", description: "Идеи для video UX и media flows", url: "https://github.com/jarnedemeulemeester/findroid"),
        StaticCreditItem(name: "Seal", description: "Идеи по UX и плавности интерфейса", url: "https://github.com/JunkFood02/Seal")
    ]

    var body: some View {
        List {
            Section("Библиотеки") {
                ForEach(libraries) { item in
                    CreditRow(title: item.name, description: item.description) {
                        open(item.url)
                    }
                }
            }

            Section("Референсы и идеи") {
                ForEach(inspiration) { item in
                    CreditRow(title: item.name, description: item.description) {
                        open(item.url)
                    }
                }
            }

            Section("Поддержка") {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Загружаем список...")
                } else if let error = viewModel.error, viewModel.items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Повторить") {
                            Task {
                                await viewModel.load(force: true)
                            }
                        }
                    }
                } else {
                    ForEach(viewModel.items, id: \.id) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name ?? item.text ?? "Без названия")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))

                            if let description = item.description ?? item.text, !description.isEmpty {
                                Text(description)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }

                            let contributions = item.contributions?.filter { !$0.isEmpty } ?? []
                            if !contributions.isEmpty {
                                Text(contributions.joined(separator: " • "))
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Благодарности")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    private func open(_ rawUrl: String) {
        guard let url = URL(string: rawUrl) else { return }
        openURL(url)
    }
}

private struct CreditRow: View {
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class CreditsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var items: [SupportItemDto] = []
    @Published var error: String?

    private var hasLoaded = false

    func load(force: Bool = false) async {
        if hasLoaded && !force {
            return
        }
        hasLoaded = true

        if let cached = SupportRepository.shared.getCached(), !cached.isEmpty {
            items = cached
        }

        isLoading = true
        error = nil

        do {
            items = try await SupportRepository.shared.fetch()
        } catch {
            if items.isEmpty {
                self.error = "Не удалось загрузить список поддержки"
            }
        }

        isLoading = false
    }
}
