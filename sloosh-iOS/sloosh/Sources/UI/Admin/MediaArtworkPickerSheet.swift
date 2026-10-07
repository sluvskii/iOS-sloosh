import SwiftUI

// MARK: - Artwork Tab Enum

private enum ArtworkTab: String, CaseIterable, Identifiable {
    case logo = "Логотип"
    case poster = "Постер"
    case backdrop = "Задники"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .logo: return "photo.badge.checkmark"
        case .poster: return "rectangle.portrait"
        case .backdrop: return "rectangle.split.2x1"
        }
    }
}

// MARK: - Media Artwork Picker Sheet

struct MediaArtworkPickerSheet: View {
    let mediaId: String
    let mediaType: String // "movie" or "tv"
    let title: String
    let kpId: Int?
    let tmdbId: Int?
    let backdropUrl: String?
    let defaultPosterUrl: String?
    let defaultLogoUrl: String?

    // Preloaded image candidates from details (if any)
    let preloadedLogos: [MediaImageItemDto]?
    let preloadedPosters: [MediaImageItemDto]?
    let preloadedBackdrops: [MediaImageItemDto]?
    let initialCarouselUrls: [String]?

    @Environment(\.dismiss) private var dismiss

    // Active Tab
    @State private var selectedTab: ArtworkTab = .logo

    // Current selections
    @State private var selectedLogoUrl: String?
    @State private var selectedPosterUrl: String?
    @State private var selectedBackdropUrl: String?
    @State private var selectedCarouselUrls: [String] = []

    // Direct custom URL input
    @State private var customUrlText: String = ""

    // Language filter: "ALL", "RU", "EN", "NONE", etc.
    @State private var selectedLanguageFilter: String = "ALL"

    // Loaded image sets from TMDB / API
    @State private var logos: [MediaImageItemDto] = []
    @State private var posters: [MediaImageItemDto] = []
    @State private var backdrops: [MediaImageItemDto] = []

    // UI Loading & Saving state
    @State private var isLoading: Bool = false
    @State private var isSaving: Bool = false
    @State private var hasLoadedFullImages: Bool = false

    init(
        mediaId: String,
        mediaType: String,
        title: String,
        kpId: Int? = nil,
        tmdbId: Int? = nil,
        backdropUrl: String? = nil,
        defaultPosterUrl: String? = nil,
        defaultLogoUrl: String? = nil,
        preloadedLogos: [MediaImageItemDto]? = nil,
        preloadedPosters: [MediaImageItemDto]? = nil,
        preloadedBackdrops: [MediaImageItemDto]? = nil,
        initialCarouselUrls: [String]? = nil
    ) {
        self.mediaId = mediaId
        self.mediaType = mediaType
        self.title = title
        self.kpId = kpId
        self.tmdbId = tmdbId
        self.backdropUrl = backdropUrl
        self.defaultPosterUrl = defaultPosterUrl
        self.defaultLogoUrl = defaultLogoUrl
        self.preloadedLogos = preloadedLogos
        self.preloadedPosters = preloadedPosters
        self.preloadedBackdrops = preloadedBackdrops
        self.initialCarouselUrls = initialCarouselUrls

        _logos = State(initialValue: preloadedLogos ?? [])
        _posters = State(initialValue: preloadedPosters ?? [])
        _backdrops = State(initialValue: preloadedBackdrops ?? [])
        _selectedCarouselUrls = State(initialValue: initialCarouselUrls ?? [])
    }

    init(details: MediaDetailsDto) {
        let cleanId = details.id ?? ""
        let isTv = details.type?.lowercased() == "tv" || (details.seasons != nil && !(details.seasons?.isEmpty ?? true))
        let inferredType = isTv ? "tv" : "movie"

        self.init(
            mediaId: cleanId,
            mediaType: inferredType,
            title: details.title ?? details.originalTitle ?? "Без названия",
            kpId: details.externalIds?.kp ?? details.ids?.kp,
            tmdbId: details.externalIds?.tmdb ?? details.ids?.tmdb,
            backdropUrl: details.displayBackdropUrl ?? details.backdrop,
            defaultPosterUrl: details.displayPosterUrl,
            defaultLogoUrl: details.displayLogoUrl,
            preloadedLogos: details.availableLogos,
            preloadedPosters: details.availablePosters,
            preloadedBackdrops: details.availableBackdrops,
            initialCarouselUrls: details.displayBackdropUrls
        )
    }

    private var activeOverride: MediaArtworkOverride? {
        MediaOverridesRepository.shared.override(for: mediaId, tmdbId: tmdbId, kpId: kpId)
    }

    private var hasActiveOverride: Bool {
        activeOverride != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // 1. Live Preview Stage (Consistent 16pt margin)
                    livePreviewSection
                        .padding(.horizontal, 16)

                    // 2. Tab Segment Picker (Consistent 16pt margin)
                    tabPickerSection
                        .padding(.horizontal, 16)

                    // 3. Language Filter Pills (Full bleed edge-to-edge)
                    languageFilterSection

                    // 4. Custom Direct URL Input (Consistent 16pt margin)
                    customUrlSection
                        .padding(.horizontal, 16)

                    // 5. Active Carousel Management (Only in Backdrop tab)
                    if selectedTab == .backdrop {
                        activeCarouselSection
                    }

                    // 6. Grid of Available Options (Consistent 16pt margin)
                    imageGridSection
                        .padding(.horizontal, 16)

                    // 7. Reset Action Button (Only if override exists)
                    if hasActiveOverride {
                        resetActionSection
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await loadAvailableImagesIfNeeded(force: true)
            }
            .navigationTitle("Оформление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Native Close Button
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Отмена")
                }

                // Native Save Button
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveChanges() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                    }
                    .disabled(isSaving)
                    .accessibilityLabel("Сохранить")
                }
            }
            .task {
                setupInitialSelection()
                await loadAvailableImagesIfNeeded()
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Initial State Setup

    private func setupInitialSelection() {
        if let existing = activeOverride {
            self.selectedLogoUrl = existing.logoUrl ?? defaultLogoUrl
            self.selectedPosterUrl = existing.posterUrl ?? defaultPosterUrl
            self.selectedBackdropUrl = existing.backdropUrl ?? backdropUrl
            if let customBackdrops = existing.backdropUrls, !customBackdrops.isEmpty {
                self.selectedCarouselUrls = customBackdrops
            } else if self.selectedCarouselUrls.isEmpty {
                if let b = self.selectedBackdropUrl, !b.isEmpty {
                    self.selectedCarouselUrls = [b]
                }
            }
        } else {
            self.selectedLogoUrl = defaultLogoUrl
            self.selectedPosterUrl = defaultPosterUrl
            self.selectedBackdropUrl = backdropUrl
            if self.selectedCarouselUrls.isEmpty, let b = backdropUrl, !b.isEmpty {
                self.selectedCarouselUrls = [b]
            }
        }
    }

    // MARK: - Live Preview Section

    private var livePreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Предпросмотр")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(previewSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ZStack {
                if selectedTab == .backdrop {
                    backdropPreviewContent
                } else if selectedTab == .logo {
                    logoPreviewContent
                } else {
                    posterPreviewContent
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
        }
    }

    private var previewSubtitle: String {
        switch selectedTab {
        case .logo: return "На тёмном фоне"
        case .poster: return "Карточка"
        case .backdrop: return "Шапка фильма"
        }
    }

    private var logoPreviewContent: some View {
        ZStack {
            backdropBaseLayer

            LinearGradient(
                colors: [Color.black.opacity(0.35), Color.black.opacity(0.88)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 10) {
                Spacer()
                if let logoUrl = selectedLogoUrl, !logoUrl.isEmpty, let url = URL(string: logoUrl) {
                    AsyncCachedImage(url: url) {
                        ProgressView().controlSize(.small)
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 65)
                            .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 3)
                    } fallback: {
                        Text(title)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 6)
                }

                Text("Логотип отображается над описанием фильма")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.bottom, 12)
            }
            .padding(16)
        }
    }

    private var posterPreviewContent: some View {
        ZStack {
            backdropBaseLayer

            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(spacing: 16) {
                if let posterUrl = selectedPosterUrl, !posterUrl.isEmpty, let url = URL(string: posterUrl) {
                    AsyncCachedImage(url: url) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 80, height: 120)
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                    } fallback: {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 80, height: 120)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 80, height: 120)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text("Выбранный постер в каталоге и карточках")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))

                    Spacer()
                }
                .padding(.vertical, 8)

                Spacer()
            }
            .padding(16)
        }
    }

    private var backdropPreviewContent: some View {
        ZStack {
            if let bg = selectedBackdropUrl ?? backdropUrl, let url = URL(string: bg) {
                AsyncCachedImage(url: url) {
                    Rectangle().fill(Color.black.opacity(0.85))
                } content: { img in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } fallback: {
                    Rectangle().fill(Color.black.opacity(0.85))
                }
            } else {
                Color.black.opacity(0.85)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.25), Color.black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text("Основной фон")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white))

                    Spacer()

                    Text("Карусель: \(selectedCarouselUrls.count) кадров")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.68)))
                }
                .padding(12)

                Spacer()

                if let logoUrl = selectedLogoUrl, !logoUrl.isEmpty, let url = URL(string: logoUrl) {
                    AsyncCachedImage(url: url) {
                        EmptyView()
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 48)
                            .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 3)
                    } fallback: {
                        Text(title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                } else {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 6)
                }

                Text("Первый кадр карусели в шапке фильма")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
        }
    }

    private var backdropBaseLayer: some View {
        Group {
            if let bg = selectedBackdropUrl ?? backdropUrl, let url = URL(string: bg) {
                AsyncCachedImage(url: url) {
                    Rectangle().fill(Color.black.opacity(0.85))
                } content: { img in
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } fallback: {
                    Rectangle().fill(Color.black.opacity(0.85))
                }
            } else {
                Color.black.opacity(0.85)
            }
        }
    }

    // MARK: - Tab Picker Section

    private var tabPickerSection: some View {
        HStack(spacing: 6) {
            ForEach(ArtworkTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        selectedTab = tab
                        selectedLanguageFilter = "ALL"
                        customUrlText = ""
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 13, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isSelected {
                            Capsule().fill(Color.white.opacity(0.18))
                        }
                    }
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(in: Capsule())
    }

    // MARK: - Language Filter Section (Full bleed edge-to-edge)

    private var availableLanguagesForCurrentTab: [String] {
        let items: [MediaImageItemDto]
        switch selectedTab {
        case .logo: items = logos
        case .poster: items = posters
        case .backdrop: items = backdrops
        }

        let hasNoText = items.contains { $0.iso_639_1 == nil || $0.iso_639_1?.isEmpty == true }
        let langs = Set(items.compactMap { $0.iso_639_1?.uppercased() }.filter { !$0.isEmpty })
        var result = ["ALL"]
        if langs.contains("RU") { result.append("RU") }
        if langs.contains("EN") { result.append("EN") }
        if hasNoText { result.append("NONE") }
        for l in langs.sorted() where l != "RU" && l != "EN" {
            result.append(l)
        }
        return result
    }

    @ViewBuilder
    private var languageFilterSection: some View {
        let langs = availableLanguagesForCurrentTab
        if langs.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(langs, id: \.self) { lang in
                        let isSelected = selectedLanguageFilter == lang
                        let label: String = {
                            switch lang {
                            case "ALL": return "Все"
                            case "RU": return "🇷🇺 Русский"
                            case "EN": return "🇺🇸 Английский"
                            case "NONE": return "✨ Без текста"
                            case "UK": return "🇺🇦 Украинский"
                            case "DE": return "🇩🇪 Немецкий"
                            case "FR": return "🇫🇷 Французский"
                            case "ES": return "🇪🇸 Испанский"
                            case "IT": return "🇮🇹 Итальянский"
                            case "JA": return "🇯🇵 Японский"
                            case "KO": return "🇰🇷 Корейский"
                            case "ZH": return "🇨🇳 Китайский"
                            default: return lang
                            }
                        }()

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedLanguageFilter = lang
                            }
                        } label: {
                            Text(label)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background {
                                    if isSelected {
                                        Capsule().fill(Color.white.opacity(0.2))
                                    } else {
                                        Capsule().fill(Color.white.opacity(0.06))
                                    }
                                }
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
        }
    }

    // MARK: - Custom URL Section (Compact inline input)

    private var customUrlSection: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("Вставить свою прямую ссылку...", text: $customUrlText)
                    .font(.system(size: 13))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !customUrlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    applyCustomUrl()
                } label: {
                    Text("Применить")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private func applyCustomUrl() {
        let trimmed = customUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            if selectedTab == .logo {
                selectedLogoUrl = trimmed
            } else if selectedTab == .poster {
                selectedPosterUrl = trimmed
            } else {
                selectedBackdropUrl = trimmed
                if !selectedCarouselUrls.contains(trimmed) {
                    selectedCarouselUrls.insert(trimmed, at: 0)
                }
            }
            customUrlText = ""
        }
    }

    // MARK: - Active Carousel Section (Карусель задников)

    private var activeCarouselSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with 16pt margin
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Карусель в шапке")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)

                        Text("\(selectedCarouselUrls.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Text("Первый кадр (#1) является основным фоном")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selectedCarouselUrls.count > 1 {
                    Button {
                        removeDuplicateBackdrops()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Без дублей")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)

            // Horizontal cards with full bleed edge-to-edge
            if selectedCarouselUrls.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    Text("Карусель пуста. Добавьте кадры из каталога ниже.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(selectedCarouselUrls.enumerated()), id: \.element) { index, url in
                            carouselItemCard(url: url, index: index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
            }
        }
    }

    private func carouselItemCard(url: String, index: Int) -> some View {
        let isPrimary = index == 0

        return VStack(spacing: 6) {
            // Thumbnail
            ZStack(alignment: .topTrailing) {
                if let u = URL(string: url) {
                    AsyncCachedImage(url: u) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.08))
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .frame(width: 170, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } fallback: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 170, height: 96)
                    }
                }

                // Delete from carousel button (Top-Right)
                Button {
                    removeFromCarousel(at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.72)))
                        .padding(6)
                }
                .buttonStyle(.plain)

                // Index / Primary badge (Top-Left)
                VStack {
                    HStack {
                        if isPrimary {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8.5))
                                Text("Главный")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(Color.white))
                        } else {
                            Button {
                                makeBackdropPrimary(url: url)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "star")
                                        .font(.system(size: 8.5))
                                    Text("#\(index + 1)")
                                        .font(.system(size: 9.5, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(Capsule().fill(Color.black.opacity(0.72)))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .padding(6)
                    Spacer()
                }
            }
            .frame(width: 170, height: 96)
            .contentShape(Rectangle())
            .onTapGesture {
                if index != 0 {
                    makeBackdropPrimary(url: url)
                }
            }

            // Bottom Reordering & Counter Row (Spacious, zero wrapping!)
            HStack(spacing: 8) {
                // Move Left
                Button {
                    moveCarouselItem(from: index, up: true)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(index == 0 ? Color.white.opacity(0.2) : Color.white)
                        .frame(width: 28, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                }
                .disabled(index == 0)
                .buttonStyle(.plain)

                Spacer()

                Text("\(index + 1) из \(selectedCarouselUrls.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                // Move Right
                Button {
                    moveCarouselItem(from: index, up: false)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(index == selectedCarouselUrls.count - 1 ? Color.white.opacity(0.2) : Color.white)
                        .frame(width: 28, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                }
                .disabled(index == selectedCarouselUrls.count - 1)
                .buttonStyle(.plain)
            }
            .frame(width: 170)
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isPrimary ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isPrimary ? Color.white.opacity(0.85) : Color.white.opacity(0.08), lineWidth: isPrimary ? 1.5 : 1)
        }
    }

    private func removeDuplicateBackdrops() {
        var seen = Set<String>()
        var uniqueList: [String] = []

        for raw in selectedCarouselUrls {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { continue }

            let key: String = {
                if let url = URL(string: clean) {
                    return url.lastPathComponent.lowercased()
                }
                return clean.lowercased()
            }()

            if !seen.contains(key) && !seen.contains(clean) {
                seen.insert(key)
                seen.insert(clean)
                uniqueList.append(clean)
            }
        }

        let removedCount = selectedCarouselUrls.count - uniqueList.count
        if removedCount > 0 {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedCarouselUrls = uniqueList
                if let current = selectedBackdropUrl, !uniqueList.contains(current) {
                    selectedBackdropUrl = uniqueList.first
                }
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            ToastManager.shared.show(
                title: "Дубликаты удалены",
                subtitle: "Убрано повторяющихся кадров: \(removedCount)",
                icon: "checkmark.circle.fill"
            )
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            ToastManager.shared.show(
                title: "Всё чисто",
                subtitle: "В карусели нет дублирующихся кадров",
                icon: "sparkles"
            )
        }
    }

    private func moveCarouselItem(from index: Int, up: Bool) {
        let target = up ? (index - 1) : (index + 1)
        guard target >= 0, target < selectedCarouselUrls.count else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            selectedCarouselUrls.swapAt(index, target)
            if index == 0 || target == 0 {
                selectedBackdropUrl = selectedCarouselUrls.first
            }
        }
    }

    private func removeFromCarousel(at index: Int) {
        guard index >= 0, index < selectedCarouselUrls.count else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            let removed = selectedCarouselUrls.remove(at: index)
            if selectedBackdropUrl == removed {
                selectedBackdropUrl = selectedCarouselUrls.first
            }
        }
    }

    private func makeBackdropPrimary(url: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            selectedBackdropUrl = url
            if let idx = selectedCarouselUrls.firstIndex(of: url) {
                selectedCarouselUrls.remove(at: idx)
            }
            selectedCarouselUrls.insert(url, at: 0)
        }
    }

    private func toggleBackdropInCarousel(url: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            if let idx = selectedCarouselUrls.firstIndex(of: url) {
                selectedCarouselUrls.remove(at: idx)
                if selectedBackdropUrl == url {
                    selectedBackdropUrl = selectedCarouselUrls.first
                }
            } else {
                selectedCarouselUrls.append(url)
                if selectedBackdropUrl == nil {
                    selectedBackdropUrl = url
                }
            }
        }
    }

    // MARK: - Grid of Available Options

    private var filteredItems: [MediaImageItemDto] {
        let raw: [MediaImageItemDto]
        switch selectedTab {
        case .logo: raw = logos
        case .poster: raw = posters
        case .backdrop: raw = backdrops
        }

        if selectedLanguageFilter == "ALL" {
            return raw
        }
        if selectedLanguageFilter == "NONE" {
            return raw.filter { $0.iso_639_1 == nil || $0.iso_639_1?.isEmpty == true }
        }
        return raw.filter { $0.iso_639_1?.uppercased() == selectedLanguageFilter }
    }

    @ViewBuilder
    private var imageGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(gridSectionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("\(filteredItems.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if filteredItems.isEmpty && !isLoading {
                HStack(spacing: 10) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                    Text("Нет доступных вариантов для выбранного фильтра")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if selectedTab == .logo {
                logoGrid
            } else if selectedTab == .poster {
                posterGrid
            } else {
                backdropGrid
            }
        }
    }

    private var gridSectionTitle: String {
        switch selectedTab {
        case .logo: return "Доступные логотипы (TMDB)"
        case .poster: return "Доступные постеры (TMDB)"
        case .backdrop: return "Каталог всех задников (TMDB)"
        }
    }

    // MARK: - Logo Grid (2 columns)

    private var logoGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(filteredItems, id: \.url) { item in
                let fullUrl = item.fullUrl
                let isSelected = (selectedLogoUrl == fullUrl)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        selectedLogoUrl = fullUrl
                    }
                } label: {
                    VStack(spacing: 8) {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.65))
                                .frame(height: 90)

                            if let url = URL(string: fullUrl) {
                                AsyncCachedImage(url: url) {
                                    ProgressView().controlSize(.small)
                                } content: { img in
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 60)
                                        .padding(8)
                                } fallback: {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }

                            HStack {
                                if isSelected {
                                    HStack(spacing: 3) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8.5, weight: .bold))
                                        Text("Выбран")
                                            .font(.system(size: 9.5, weight: .bold))
                                    }
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.white))
                                    .padding(6)
                                }

                                Spacer()

                                if let lang = item.iso_639_1?.uppercased(), !lang.isEmpty {
                                    Text(lang)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2.5)
                                        .background(Capsule().fill(Color.black.opacity(0.68)))
                                        .padding(6)
                                }
                            }
                        }

                        HStack {
                            if let w = item.width, let h = item.height {
                                Text("\(w)×\(h)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 2)
                    }
                    .padding(6)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.85) : Color.white.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Poster Grid (3 columns)

    private var posterGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(filteredItems, id: \.url) { item in
                let fullUrl = item.fullUrl
                let isSelected = (selectedPosterUrl == fullUrl)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        selectedPosterUrl = fullUrl
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            if let url = URL(string: fullUrl) {
                                AsyncCachedImage(url: url) {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.08))
                                        .aspectRatio(2/3, contentMode: .fit)
                                } content: { img in
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(2/3, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                } fallback: {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.08))
                                        .aspectRatio(2/3, contentMode: .fit)
                                }
                            }

                            HStack {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.black)
                                        .frame(width: 20, height: 20)
                                        .background(Circle().fill(Color.white))
                                        .padding(5)
                                }

                                Spacer()

                                if let lang = item.iso_639_1?.uppercased(), !lang.isEmpty {
                                    Text(lang)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2.5)
                                        .background(Capsule().fill(Color.black.opacity(0.68)))
                                        .padding(5)
                                }
                            }
                        }

                        if let w = item.width, let h = item.height {
                            Text("\(w)×\(h)")
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? .white : .secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(5)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.85) : Color.white.opacity(0.06), lineWidth: isSelected ? 1.5 : 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Backdrop Grid (2 columns 16:9)

    private var backdropGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(filteredItems, id: \.url) { item in
                let fullUrl = item.fullUrl
                let inCarouselIndex = selectedCarouselUrls.firstIndex(of: fullUrl)
                let isInCarousel = inCarouselIndex != nil
                let isPrimary = (inCarouselIndex == 0) || (selectedBackdropUrl == fullUrl)

                VStack(spacing: 6) {
                    // 16:9 Thumbnail
                    ZStack(alignment: .topTrailing) {
                        if let url = URL(string: fullUrl) {
                            AsyncCachedImage(url: url) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.08))
                                    .aspectRatio(16/9, contentMode: .fit)
                            } content: { img in
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(16/9, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } fallback: {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(0.08))
                                    .aspectRatio(16/9, contentMode: .fit)
                            }
                        }

                        // Top Badges (Left: Primary or Index; Right: Language)
                        VStack {
                            HStack {
                                if isPrimary {
                                    HStack(spacing: 3) {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 8.5))
                                        Text("Главный")
                                            .font(.system(size: 9.5, weight: .bold))
                                    }
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.white))
                                } else if let idx = inCarouselIndex {
                                    Text("#\(idx + 1)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.black.opacity(0.68)))
                                }

                                Spacer()

                                if let lang = item.iso_639_1?.uppercased(), !lang.isEmpty {
                                    Text(lang)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2.5)
                                        .background(Capsule().fill(Color.black.opacity(0.68)))
                                }
                            }
                            .padding(5)
                            Spacer()
                        }
                    }
                    .frame(height: 94)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        makeBackdropPrimary(url: fullUrl)
                    }

                    // Card Bottom: Resolution (Left) & Carousel Toggle Button (Right)
                    HStack(alignment: .center) {
                        if let w = item.width, let h = item.height {
                            Text("\(w)×\(h)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            toggleBackdropInCarousel(url: fullUrl)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isInCarousel ? "checkmark" : "plus")
                                    .font(.system(size: 9.5, weight: .bold))
                                Text(isInCarousel ? "В карусели" : "В карусель")
                                    .font(.system(size: 10.5, weight: isInCarousel ? .semibold : .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(isInCarousel ? Color.white.opacity(0.2) : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 2)
                }
                .padding(6)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isPrimary ? Color.white.opacity(0.08) : (isInCarousel ? Color.white.opacity(0.05) : Color.white.opacity(0.03)))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isPrimary ? Color.white.opacity(0.85) : (isInCarousel ? Color.white.opacity(0.22) : Color.white.opacity(0.06)),
                            lineWidth: isPrimary ? 1.5 : 1
                        )
                }
            }
        }
    }

    // MARK: - Reset Action Section

    private var resetActionSection: some View {
        Button(role: .destructive) {
            Task { await resetToDefault() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                Text("Сбросить к оригиналу")
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.red.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .glassEffect(in: Capsule())
        }
        .disabled(isSaving)
        .padding(.top, 8)
    }

    // MARK: - Data Loading & Actions

    private func loadAvailableImagesIfNeeded(force: Bool = false) async {
        if hasLoadedFullImages && !force { return }
        isLoading = true
        defer { isLoading = false }

        let effectiveId: String = {
            if let tmdb = tmdbId, tmdb > 0 {
                return "\(tmdb)"
            }
            if let kp = kpId, kp > 0 {
                return "kp_\(kp)"
            }
            return mediaId
        }()

        do {
            let res = try await MoviesApi.shared.getMediaImages(id: effectiveId, type: mediaType)
            if let data = res.data {
                await MainActor.run {
                    self.hasLoadedFullImages = true

                    if let incomingLogos = data.logos, !incomingLogos.isEmpty {
                        var merged = incomingLogos
                        for existing in self.logos {
                            if !merged.contains(where: { $0.url == existing.url }) {
                                merged.append(existing)
                            }
                        }
                        self.logos = merged
                    }

                    if let incomingPosters = data.posters, !incomingPosters.isEmpty {
                        var merged = incomingPosters
                        for existing in self.posters {
                            if !merged.contains(where: { $0.url == existing.url }) {
                                merged.append(existing)
                            }
                        }
                        self.posters = merged
                    }

                    if let incomingBackdrops = data.backdrops, !incomingBackdrops.isEmpty {
                        var merged = incomingBackdrops
                        for existing in self.backdrops {
                            if !merged.contains(where: { $0.url == existing.url }) {
                                merged.append(existing)
                            }
                        }
                        self.backdrops = merged
                    }

                    if self.selectedLogoUrl == nil, let firstLogo = self.logos.first {
                        self.selectedLogoUrl = firstLogo.fullUrl
                    }
                    if self.selectedPosterUrl == nil, let firstPoster = self.posters.first {
                        self.selectedPosterUrl = firstPoster.fullUrl
                    }
                    if self.selectedCarouselUrls.isEmpty && !self.backdrops.isEmpty {
                        self.selectedCarouselUrls = Array(self.backdrops.prefix(6).map { $0.fullUrl })
                    }
                    if self.selectedBackdropUrl == nil {
                        self.selectedBackdropUrl = self.selectedCarouselUrls.first ?? self.backdrops.first?.fullUrl
                    }
                }
            }
        } catch {
            AppDiagnostics.shared.log("MediaArtworkPickerSheet: failed to load images for id=\(effectiveId): \(error)")
            if effectiveId != mediaId && !mediaId.isEmpty {
                do {
                    let fallbackRes = try await MoviesApi.shared.getMediaImages(id: mediaId, type: mediaType)
                    if let fallbackData = fallbackRes.data {
                        await MainActor.run {
                            self.hasLoadedFullImages = true
                            if let incomingLogos = fallbackData.logos, !incomingLogos.isEmpty {
                                var merged = incomingLogos
                                for existing in self.logos {
                                    if !merged.contains(where: { $0.url == existing.url }) {
                                        merged.append(existing)
                                    }
                                }
                                self.logos = merged
                            }
                            if let incomingPosters = fallbackData.posters, !incomingPosters.isEmpty {
                                var merged = incomingPosters
                                for existing in self.posters {
                                    if !merged.contains(where: { $0.url == existing.url }) {
                                        merged.append(existing)
                                    }
                                }
                                self.posters = merged
                            }
                            if let incomingBackdrops = fallbackData.backdrops, !incomingBackdrops.isEmpty {
                                var merged = incomingBackdrops
                                for existing in self.backdrops {
                                    if !merged.contains(where: { $0.url == existing.url }) {
                                        merged.append(existing)
                                    }
                                }
                                self.backdrops = merged
                            }
                            if self.selectedCarouselUrls.isEmpty && !self.backdrops.isEmpty {
                                self.selectedCarouselUrls = Array(self.backdrops.prefix(6).map { $0.fullUrl })
                            }
                            if self.selectedBackdropUrl == nil {
                                self.selectedBackdropUrl = self.selectedCarouselUrls.first ?? self.backdrops.first?.fullUrl
                            }
                        }
                    }
                } catch {
                    AppDiagnostics.shared.log("MediaArtworkPickerSheet: fallback also failed for id=\(mediaId): \(error)")
                }
            }
        }
    }

    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await MediaOverridesRepository.shared.saveOverride(
                mediaId: mediaId,
                kpId: kpId,
                tmdbId: tmdbId,
                title: title,
                posterUrl: selectedPosterUrl,
                logoUrl: selectedLogoUrl,
                backdropUrl: selectedBackdropUrl,
                backdropUrls: selectedCarouselUrls.isEmpty ? nil : selectedCarouselUrls
            )

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            ToastManager.shared.show(
                title: "Оформление обновлено",
                subtitle: "Изменения применены ко всем устройствам",
                icon: "checkmark.circle.fill"
            )
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ToastManager.shared.show(
                title: "Ошибка сохранения",
                subtitle: error.localizedDescription,
                icon: "exclamationmark.triangle.fill"
            )
        }
    }

    private func resetToDefault() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await MediaOverridesRepository.shared.deleteOverride(
                mediaId: mediaId,
                kpId: kpId,
                tmdbId: tmdbId
            )

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            ToastManager.shared.show(
                title: "Оригинал восстановлен",
                subtitle: "Сброшено к стандартным изображениям TMDB",
                icon: "arrow.counterclockwise"
            )
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            ToastManager.shared.show(
                title: "Ошибка сброса",
                subtitle: error.localizedDescription,
                icon: "exclamationmark.triangle.fill"
            )
        }
    }
}
