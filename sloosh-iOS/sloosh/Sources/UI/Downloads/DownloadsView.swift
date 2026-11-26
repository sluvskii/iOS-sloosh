import SwiftUI

private struct DownloadArtworkView: View {
    let localUrl: URL?
    let remoteUrl: String?

    var body: some View {
        Group {
            if let local = localUrl, let image = UIImage(contentsOfFile: local.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let remote = remoteUrl, let normalized = normalizeImageUrl(path: remote), let url = URL(string: normalized) {
                AsyncCachedImage(url: url) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.18))
                        .overlay {
                            Rectangle()
                                .fill(Color.gray.opacity(0.12))
                                .shimmer()
                        }
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } fallback: {
                    DownloadArtworkPlaceholder()
                }
            } else {
                DownloadArtworkPlaceholder()
            }
        }
        .background(Color(UIColor.secondarySystemFill))
    }
}

private struct DownloadArtworkPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(UIColor.secondarySystemFill),
                    Color(UIColor.tertiarySystemFill)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "film")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct DownloadsView: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var selectedFilter = 0 // 0 = Все, 1 = Фильмы, 2 = Сериалы
    @State private var playerItem: DownloadItem? = nil
    @State private var isExporting: Bool = false
    @State private var exportingTitle: String = ""
    @Environment(\.dismiss) private var dismiss
    
    private var listItems: [DownloadItem] {
        downloadManager.downloads.filter { item in
            let isCartoon = isCartoonByTitle(item.title)
            switch selectedFilter {
            case 0: return true
            case 1: return item.mediaType == "movie" && !isCartoon
            case 2: return item.mediaType == "tv" && !isCartoon
            case 3: return isCartoon
            default: return true
            }
        }.sorted(by: { $0.addedAt > $1.addedAt })
    }
    
    var body: some View {
        ZStack {
            Group {
                if downloadManager.downloads.isEmpty {
                    emptyView
                } else {
                    List {
                        DownloadsCategoryPillStrip(selectedFilter: $selectedFilter)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 6, trailing: 0))

                        if listItems.isEmpty {
                            Text("В этой категории пока нет загрузок")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 48)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(listItems) { item in
                                Button {
                                    if item.status == .completed {
                                        playerItem = item
                                    }
                                } label: {
                                    DownloadRowView(item: item, onShare: { shareItem in
                                        shareDownloadedItem(shareItem)
                                    }, onSaveToPhotos: { photoItem in
                                        saveToPhotosAction(photoItem)
                                    })
                                }
                                .buttonStyle(DownloadCardScaleButtonStyle())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.hidden)
                    .scrollEdgeEffectStyle(.soft, for: .all)
                }
            }
            
            if isExporting {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        
                        VStack(spacing: 4) {
                            Text("Подготовка видео...")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            
                            if !exportingTitle.isEmpty {
                                Text(exportingTitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isExporting)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Загрузки")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            downloadManager.recalculateDiskSizesInBackground()
            HlsProxyServer.shared.start(headers: [:], voices: [], subtitles: [], mediaId: "local")
        }
        .fullWidthSwipeBack()
        .fullScreenCover(item: $playerItem, onDismiss: {
            playerItem = nil
            AppDelegate.lockToPortrait()
        }) { item in
            PlayerView(
                fallbackTitle: item.title,
                kpId: item.kpId > 0 ? item.kpId : nil,
                season: item.season,
                episode: item.episode,
                selectedVoiceover: item.translationName,
                directStreamUrl: item.localPlayableUrl?.absoluteString,
                mediaKey: item.kpId > 0 ? "kp_\(item.kpId)" : item.id,
                posterUrl: item.posterUrl
            )
            .preferredColorScheme(.dark)
            .environment(\.colorScheme, .dark)
        }
    }
    
    private func shareDownloadedItem(_ item: DownloadItem) {
        guard item.status == .completed else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        isExporting = true
        exportingTitle = item.title
        
        Task {
            do {
                let mp4Url = try await DownloadManager.shared.exportAsMP4(item: item)
                await MainActor.run {
                    self.isExporting = false
                    SharePresenter.presentShare(items: [mp4Url])
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    ToastManager.shared.show(title: error.localizedDescription, icon: "exclamationmark.triangle.fill")
                    AppDiagnostics.shared.log("Failed to export download item: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func saveToPhotosAction(_ item: DownloadItem) {
        guard item.status == .completed else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        isExporting = true
        exportingTitle = "Сохранение в Фото..."
        
        Task {
            do {
                try await DownloadManager.shared.saveToPhotos(item: item)
                await MainActor.run {
                    self.isExporting = false
                    ToastManager.shared.show(title: "Видео сохранено в Фото", icon: "checkmark.circle.fill")
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    ToastManager.shared.show(title: error.localizedDescription, icon: "exclamationmark.triangle.fill")
                    AppDiagnostics.shared.log("Failed to save to Photos: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @ViewBuilder
    private var emptyView: some View {
        AppEmptyStateView(
            icon: "arrow.down.circle",
            title: "Нет загрузок",
            description: "Скачивайте фильмы и сериалы для просмотра без интернета."
        )
    }
}

private struct DownloadCardScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct DownloadRowView: View {
    let item: DownloadItem
    var onShare: (DownloadItem) -> Void = { _ in }
    var onSaveToPhotos: (DownloadItem) -> Void = { _ in }
    
    var body: some View {
        HStack(spacing: 16) {
            DownloadArtworkView(localUrl: item.localPosterUrl, remoteUrl: item.posterUrl)
                .frame(width: 100, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if item.status == .downloading {
                    DownloadProgressBar(progress: item.progress)
                        .padding(.top, 4)
                    HStack {
                        Text("Скачивание...")
                        Spacer()
                        Text("\(Int(item.progress * 100))%")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                } else if item.status == .pending {
                    Text("В очереди...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if item.status == .failed {
                    Text(item.errorMessage ?? "Ошибка загрузки")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                } else if item.status == .completed {
                    Text(item.sizeString)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)

            HStack(spacing: 12) {
                if item.status == .completed {
                    Button {
                        onShare(item)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .glassForeground()
                            .frame(width: 32, height: 32)
                            .glassEffect(in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                
                statusBadge
            }
        }
        .frame(height: 150)
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .contextMenu {
            if item.status == .completed {
                Button {
                    onSaveToPhotos(item)
                } label: {
                    Label("Сохранить в Фото (Галерея)", systemImage: "photo.on.rectangle")
                }
                
                Button {
                    onShare(item)
                } label: {
                    Label("Поделиться / Сохранить в Файлы", systemImage: "square.and.arrow.up")
                }
                
                Divider()
            }
            
            Button(role: .destructive) {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.prepare()
                generator.impactOccurred()
                withAnimation {
                    DownloadManager.shared.deleteDownload(id: item.id)
                }
            } label: {
                Label("Удалить", systemImage: "trash.fill")
            }
        }
        .swipeActions(edge: .leading) {
            if item.status == .completed {
                Button {
                    onShare(item)
                } label: {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
                .tint(Color.slooshAccent)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.prepare()
                generator.impactOccurred()
                withAnimation {
                    DownloadManager.shared.deleteDownload(id: item.id)
                }
            } label: {
                Label("Удалить", systemImage: "trash.fill")
            }
        }
    }

    private var subtitleText: String? {
        var parts: [String] = []
        if let season = item.season, let episode = item.episode {
            parts.append("\(season) сезон, \(episode) серия")
        }
        if let voice = item.translationName, !voice.isEmpty {
            parts.append(voice)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private var radialState: RadialDownloadState {
        switch item.status {
        case .completed:
            return .downloaded
        case .downloading:
            return .downloading(progress: item.progress)
        case .paused:
            return .paused(progress: item.progress)
        case .pending:
            return .downloading(progress: 0.0)
        default:
            return .idle
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        RadialDownloadIndicator(state: radialState) {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if item.status == .downloading || item.status == .pending {
                    DownloadManager.shared.pauseDownload(id: item.id)
                } else if item.status == .paused || item.status == .failed {
                    DownloadManager.shared.resumeDownload(id: item.id)
                } else if item.status == .completed {
                    DownloadManager.shared.deleteDownload(id: item.id)
                } else {
                    // if idle, usually start download (but here it's already in the list)
                }
            }
        }
        .frame(width: 32, height: 32)
    }
}

private struct DownloadProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.white.opacity(0.2))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.slooshAccent)
                        .frame(width: max(0, geo.size.width * progress))
                }
        }
        .frame(height: 4)
    }
}

private struct DownloadsCategoryPillStrip: View {
    @Binding var selectedFilter: Int
    private let titles = ["Все", "Фильмы", "Сериалы", "Мульты"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                    let isSelected = selectedFilter == index
                    Button {
                        guard !isSelected else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            selectedFilter = index
                        }
                    } label: {
                        Text(title)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.14))
                                }
                            }
                            .contentShape(.capsule)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.glassPress)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selectedFilter)
    }
}
