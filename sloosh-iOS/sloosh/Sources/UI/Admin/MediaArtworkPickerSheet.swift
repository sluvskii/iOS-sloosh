import SwiftUI

// MARK: - Media Artwork Picker Sheet (iOS 26+ Liquid Glass Admin Tool)

struct MediaArtworkPickerSheet: View {
    let mediaId: String
    let mediaType: String?
    let title: String
    let kpId: Int?
    let tmdbId: Int?
    let backdropUrl: String?
    let defaultPosterUrl: String?
    let defaultLogoUrl: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab: ArtworkTab = .logo
    @State private var selectedLogoUrl: String?
    @State private var selectedPosterUrl: String?
    @State private var customUrlText: String = ""
    @State private var selectedLanguageFilter: String = "ALL"

    @State private var logos: [MediaImageItemDto] = []
    @State private var posters: [MediaImageItemDto] = []
    @State private var isLoading: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    enum ArtworkTab: String, CaseIterable, Identifiable {
        case logo = "Логотип"
        case poster = "Постер"

        var id: Self { self }
        var icon: String {
            switch self {
            case .logo: return "text.below.photo"
            case .poster: return "photo.fill"
            }
        }
    }

    init(
        mediaId: String,
        mediaType: String? = nil,
        title: String,
        kpId: Int? = nil,
        tmdbId: Int? = nil,
        backdropUrl: String? = nil,
        defaultPosterUrl: String? = nil,
        defaultLogoUrl: String? = nil,
        preloadedLogos: [MediaImageItemDto]? = nil,
        preloadedPosters: [MediaImageItemDto]? = nil
    ) {
        self.mediaId = mediaId
        self.mediaType = mediaType
        self.title = title
        self.kpId = kpId
        self.tmdbId = tmdbId
        self.backdropUrl = backdropUrl
        self.defaultPosterUrl = defaultPosterUrl
        self.defaultLogoUrl = defaultLogoUrl
        _logos = State(initialValue: preloadedLogos ?? [])
        _posters = State(initialValue: preloadedPosters ?? [])
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
            preloadedPosters: details.availablePosters
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
                    // 1. Live Preview Stage
                    livePreviewSection

                    // 2. Tab Segment Picker (Логотип / Постер)
                    tabPickerSection

                    // 3. Language Filter Pills
                    languageFilterSection

                    // 4. Custom Direct URL Input
                    customUrlSection

                    // 5. Grid of Available Options
                    imageGridSection

                    // 6. Action Buttons (Сохранить / Сбросить)
                    actionsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Оформление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.secondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveChanges() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Сохранить")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.slooshAccent)
                        }
                    }
                    .disabled(isSaving)
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
        } else {
            self.selectedLogoUrl = defaultLogoUrl
            self.selectedPosterUrl = defaultPosterUrl
        }
    }

    // MARK: - Live Preview Section

    private var livePreviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Предпросмотр в приложении")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedTab == .logo ? "На тёмном фоне" : "Карточка")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            ZStack {
                // Backdrop background
                if let bg = backdropUrl, let url = URL(string: bg) {
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

                // Dark cinematic gradient overlay
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.3),
                        Color.black.opacity(0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Foreground Content according to active tab
                if selectedTab == .logo {
                    VStack(spacing: 12) {
                        Spacer()
                        if let logoUrl = selectedLogoUrl, !logoUrl.isEmpty, let url = URL(string: logoUrl) {
                            AsyncCachedImage(url: url) {
                                ProgressView().controlSize(.small)
                            } content: { img in
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 70)
                                    .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 3)
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

                        Text("Логотип отображается над информацией о фильме")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                            .padding(.bottom, 8)
                    }
                    .padding(16)
                } else {
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
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            Text("Основной постер каталога")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.7))

                            if let poster = selectedPosterUrl, !poster.isEmpty {
                                Text("Выбран пользователем")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Color.slooshAccent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.slooshAccent.opacity(0.18))
                                    .clipShape(Capsule())
                            }
                        }

                        Spacer()
                    }
                    .padding(16)
                }
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
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
                            Capsule()
                                .fill(Color.white.opacity(0.18))
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

    // MARK: - Language Filter Section

    private var availableLanguagesForCurrentTab: [String] {
        let items = (selectedTab == .logo) ? logos : posters
        let langs = Set(items.compactMap { $0.iso_639_1?.uppercased() }.filter { !$0.isEmpty })
        var result = ["ALL"]
        if langs.contains("RU") { result.append("RU") }
        if langs.contains("EN") { result.append("EN") }
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
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Custom URL Section

    private var customUrlSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Или укажите прямую ссылку на изображение:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                TextField("https://...", text: $customUrlText)
                    .font(.system(size: 13))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    applyCustomUrl()
                } label: {
                    Text("Выбрать")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(customUrlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            } else {
                selectedPosterUrl = trimmed
            }
        }
    }

    // MARK: - Grid of Available Options

    private var filteredItems: [MediaImageItemDto] {
        let raw = (selectedTab == .logo) ? logos : posters
        if selectedLanguageFilter == "ALL" {
            return raw
        }
        return raw.filter { $0.iso_639_1?.uppercased() == selectedLanguageFilter }
    }

    @ViewBuilder
    private var imageGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedTab == .logo ? "Доступные логотипы (TMDB)" : "Доступные постеры (TMDB)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("\(filteredItems.count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

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
            } else {
                posterGrid
            }
        }
    }

    // MARK: - Logo Grid (2 columns)

    private var logoGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(filteredItems) { item in
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
                            // Dark preview background for logo
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

                            // Language Pill
                            if let lang = item.iso_639_1?.uppercased(), !lang.isEmpty {
                                Text(lang)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.65))
                                    .clipShape(Capsule())
                                    .padding(6)
                            }
                        }

                        // Status / Selected Indicator
                        HStack(spacing: 4) {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.slooshAccent)
                                    .font(.system(size: 12))
                                Text("Основной")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.slooshAccent)
                            } else {
                                if let w = item.width, let h = item.height {
                                    Text("\(w)×\(h)")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(8)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? Color.slooshAccent.opacity(0.12) : Color.white.opacity(0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.slooshAccent : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
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
            ForEach(filteredItems) { item in
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
                                        .fill(Color.white.opacity(0.1))
                                        .aspectRatio(2/3, contentMode: .fit)
                                } content: { img in
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(2/3, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                } fallback: {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.1))
                                        .aspectRatio(2/3, contentMode: .fit)
                                }
                            }

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.slooshAccent)
                                    .background(Circle().fill(Color.black))
                                    .font(.system(size: 16))
                                    .padding(6)
                            } else if let lang = item.iso_639_1?.uppercased(), !lang.isEmpty {
                                Text(lang)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(Capsule())
                                    .padding(4)
                            }
                        }

                        if let w = item.width, let h = item.height {
                            Text("\(w)×\(h)")
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? Color.slooshAccent : .secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(6)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Color.slooshAccent.opacity(0.12) : Color.white.opacity(0.04))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.slooshAccent : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await saveChanges() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Сохранить как основной")
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .glassEffect(in: Capsule())
            }
            .disabled(isSaving)

            if hasActiveOverride {
                Button(role: .destructive) {
                    Task { await resetToDefault() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Сбросить к оригиналу")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassEffect(in: Capsule())
                }
                .disabled(isSaving)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Data Loading & Actions

    private func loadAvailableImagesIfNeeded() async {
        guard logos.isEmpty && posters.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let res = try await MoviesApi.shared.getMediaImages(id: mediaId, type: mediaType)
            if let data = res.data {
                await MainActor.run {
                    self.logos = data.logos ?? []
                    self.posters = data.posters ?? []
                }
            }
        } catch {
            AppDiagnostics.shared.log("MediaArtworkPickerSheet: failed to load images: \(error)")
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
                backdropUrl: backdropUrl
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
                subtitle: "Сброшено к стандартным постерам TMDB",
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
