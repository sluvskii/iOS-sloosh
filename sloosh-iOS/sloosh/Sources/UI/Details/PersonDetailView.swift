import SwiftUI
import Photos
import UIKit

struct PersonDetailView: View {
    let personId: Int
    let initialName: String?
    let navigationTransitionID: String?
    let navigationTransitionNamespace: Namespace.ID?

    @StateObject private var viewModel: PersonDetailViewModel
    @State private var dominantColor: UIColor? = nil
    @State private var isTitleAtTop: Bool = false
    @State private var showPhotoGallery: Bool = false
    @State private var selectedPhotoIndex: Int = 0
    @State private var selectedPhotoTransitionId: String? = nil
    @Namespace private var photoGalleryNamespace
    @Namespace private var filmographyTransitionNamespace
    @Environment(\.dismiss) private var dismiss

    init(
        personId: Int,
        initialName: String? = nil,
        navigationTransitionID: String? = nil,
        navigationTransitionNamespace: Namespace.ID? = nil
    ) {
        self.personId = personId
        self.initialName = initialName
        self.navigationTransitionID = navigationTransitionID
        self.navigationTransitionNamespace = navigationTransitionNamespace
        _viewModel = StateObject(wrappedValue: PersonDetailViewModel(personId: personId))
    }

    private var effectiveBackgroundColor: Color {
        if let dominant = dominantColor {
            return Color(uiColor: dominant).opacity(0.35)
        } else {
            return Color(red: 0.05, green: 0.05, blue: 0.05)
        }
    }

    private var allPhotos: [String] {
        var list: [String] = []
        if let primary = viewModel.details?.photo, !primary.isEmpty {
            list.append(primary)
        }
        if let additional = viewModel.details?.photos {
            for p in additional {
                if !list.contains(p) && !p.isEmpty {
                    list.append(p)
                }
            }
        }
        return list
    }

    private func preloadDominantColor(from photoUrl: String?) async {
        guard let photoUrl, let url = URL(string: photoUrl) else { return }
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let image = UIImage(data: data) else { return }
            let color = image.averageColor
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.dominantColor = color
                }
            }
        } catch { }
    }

    private func savePhotoToLibrary(_ urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                ToastManager.shared.show(title: "Не удалось загрузить фото", icon: "xmark.circle")
                return
            }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                ToastManager.shared.show(title: "Нет доступа к Фото", icon: "lock")
                return
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            ToastManager.shared.show(title: "Сохранено в Фото", icon: "checkmark.circle.fill")
        } catch {
            ToastManager.shared.show(title: "Ошибка при сохранении", icon: "xmark.circle")
        }
    }

    private func sharePhotoUrl(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        var items: [Any] = []
        if let data = URLCache.shared.cachedResponse(for: URLRequest(url: url))?.data,
           let img = UIImage(data: data) {
            items.append(img)
        } else {
            items.append(url)
        }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
           let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController { topVC = presented }
            av.popoverPresentationController?.sourceView = topVC.view
            topVC.present(av, animated: true)
        }
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.isLoading && viewModel.details == nil {
                        PersonSkeletonView()
                            .transition(.opacity)
                    } else if let details = viewModel.details {
                        personContent(details: details)
                            .transition(.opacity)
                    } else if let error = viewModel.errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 44))
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.secondary)
                            Button("Повторить") {
                                Task { await viewModel.loadDetails(force: true) }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .glassEffect(.regular.interactive(), in: Capsule())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea(edges: .top)
        .hideNavigationBarWithRestore()
        .fullWidthSwipeBack()
        .optionalZoomTransition(sourceID: navigationTransitionID, in: navigationTransitionNamespace)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                if isTitleAtTop {
                    Text(viewModel.details?.name ?? initialName ?? "")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 68)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                HStack {
                    TelegramGlassIconButton(systemName: "chevron.left") {
                        dismiss()
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(
                VariableBlurView(tintColor: effectiveBackgroundColor, tintOpacity: 1.0)
                    .padding(.bottom, -60)
                    .ignoresSafeArea(edges: .top)
                    .opacity(isTitleAtTop ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.25), value: isTitleAtTop)
                    .allowsHitTesting(false)
            )
        }
        .background {
            effectiveBackgroundColor
                .animation(.easeInOut(duration: 0.4), value: effectiveBackgroundColor)
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showPhotoGallery) {
            PersonPhotoGalleryView(photos: allPhotos, selectedIndex: $selectedPhotoIndex)
                .ignoresSafeArea()
                .presentationBackground(.clear)
                .optionalZoomTransition(sourceID: selectedPhotoTransitionId, in: photoGalleryNamespace)
        }
        .onChange(of: selectedPhotoIndex) { _, newIndex in
            selectedPhotoTransitionId = "person_photo_\(newIndex)"
        }
        .task {
            await viewModel.loadDetails()
            if let photo = viewModel.details?.photo {
                await preloadDominantColor(from: photo)
            }
        }
        .refreshable {
            await viewModel.loadDetails(force: true)
            if let photo = viewModel.details?.photo {
                await preloadDominantColor(from: photo)
            }
        }
    }

    // MARK: - Person Content

    @ViewBuilder
    private func personContent(details: PersonDetailsDto) -> some View {
        let baseHeight: CGFloat = 380

        // Stretchy Parallax Hero Header (edge-to-edge top, softly fading downward)
        GeometryReader { geometry in
            let minY = geometry.frame(in: .global).minY
            let isScrollingDown = minY > 0
            let height = isScrollingDown ? baseHeight + minY : baseHeight
            let offset = isScrollingDown ? -minY : 0

            PersonHeroHeaderView(
                url: URL(string: details.photo ?? ""),
                width: geometry.size.width,
                height: height
            )
            .matchedTransitionSource(id: "person_photo_0", in: photoGalleryNamespace)
            .offset(y: offset)
            .contentShape(Rectangle())
            .onTapGesture {
                if !allPhotos.isEmpty {
                    selectedPhotoIndex = 0
                    selectedPhotoTransitionId = "person_photo_0"
                    showPhotoGallery = true
                }
            }
            .contextMenu {
                if !allPhotos.isEmpty {
                    Button {
                        selectedPhotoIndex = 0
                        showPhotoGallery = true
                    } label: {
                        Label("Открыть фото", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                }
                if let photo = details.photo {
                    Button {
                        Task { await savePhotoToLibrary(photo) }
                    } label: {
                        Label("Сохранить в Фото", systemImage: "photo.badge.arrow.down")
                    }
                    Button {
                        sharePhotoUrl(photo)
                    } label: {
                        Label("Поделиться", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .frame(height: baseHeight)

        // Information stack
        VStack(spacing: 20) {
            // Main name & original name (smoothly fades away when top bar title appears)
            VStack(spacing: 6) {
                Text(details.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .opacity(isTitleAtTop ? 0 : 1)
                    .blur(radius: isTitleAtTop ? 8 : 0)
                    .scaleEffect(isTitleAtTop ? 0.92 : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isTitleAtTop)

                if let originalName = details.originalName, !originalName.isEmpty, originalName.lowercased() != details.name.lowercased() {
                    Text(originalName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .opacity(isTitleAtTop ? 0 : 1)
                        .blur(radius: isTitleAtTop ? 6 : 0)
                        .scaleEffect(isTitleAtTop ? 0.92 : 1.0)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isTitleAtTop)
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .global).midY) { _, midY in
                            let isAtTop = midY < 80
                            if isTitleAtTop != isAtTop {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isTitleAtTop = isAtTop
                                }
                            }
                        }
                        .onAppear {
                            isTitleAtTop = geo.frame(in: .global).midY < 80
                        }
                }
            )

            // Minimalist typography-driven metadata section (NO icons)
            PersonMetadataSection(details: details)

            // Parsed biography & separated sections (Awards, Projects, Facts)
            let parsedBio = ParsedBiography.parse(from: details.biography, details: details)

            if !parsedBio.bio.isEmpty {
                PersonBiographySection(biography: parsedBio.bio)
                    .padding(.horizontal, 16)
            }

            if let awards = parsedBio.awards, !awards.isEmpty {
                PersonExtraInfoBlock(title: "Главные награды", content: awards)
                    .padding(.horizontal, 16)
            }

            if let keyProjects = parsedBio.keyProjects, !keyProjects.isEmpty {
                PersonExtraInfoBlock(title: "Главные проекты", content: keyProjects)
                    .padding(.horizontal, 16)
            }

            if let fact = parsedBio.interestingFact, !fact.isEmpty {
                PersonExtraInfoBlock(title: "Интересный факт", content: fact)
                    .padding(.horizontal, 16)
            }

            // Additional Photos (if present)
            if let photos = details.photos, photos.count > 1 {
                PersonPhotosSection(
                    photos: photos,
                    allPhotos: allPhotos,
                    namespace: photoGalleryNamespace,
                    onSelect: { idx, transitionId in
                        selectedPhotoIndex = idx
                        selectedPhotoTransitionId = transitionId
                        showPhotoGallery = true
                    },
                    onSave: { url in
                        Task { await savePhotoToLibrary(url) }
                    },
                    onShare: { url in
                        sharePhotoUrl(url)
                    }
                )
            }

            // Filmography
            PersonFilmographySection(
                viewModel: viewModel,
                details: details,
                namespace: filmographyTransitionNamespace
            )
                .padding(.top, 4)
                .padding(.bottom, 36)
        }
        .offset(y: -25)
    }
}

// MARK: - Hero Header View

private struct PersonHeroHeaderView: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        AsyncCachedImage(url: url) {
            Rectangle()
                .fill(Color.gray.opacity(0.18))
                .frame(width: width, height: height)
                .shimmer()
        } content: { image in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
        } fallback: {
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.15))
                Image(systemName: "person.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .frame(width: width, height: height)
        }
        .mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .black, location: 0.0),
                    .init(color: .black, location: 0.55),
                    .init(color: .black.opacity(0.85), location: 0.70),
                    .init(color: .black.opacity(0.50), location: 0.82),
                    .init(color: .black.opacity(0.18), location: 0.92),
                    .init(color: .clear, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Metadata Section (Clean, typography-first, NO icons)

private struct PersonMetadataSection: View {
    let details: PersonDetailsDto

    var body: some View {
        VStack(spacing: 12) {
            if let birth = details.formattedBirthdayWithAge {
                metadataRow(label: "Дата рождения", value: birth)
            }
            if let place = details.placeOfBirth, !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                metadataRow(label: "Место рождения", value: place)
            }
            if let death = details.deathday, !death.isEmpty {
                metadataRow(label: "Дата смерти", value: death)
            }
            if let count = details.filmography?.count, count > 0 {
                metadataRow(label: "Карьера", value: "\(count) \(declinedProjects(count))")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func declinedProjects(_ count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if lastTwo >= 11 && lastTwo <= 19 { return "работ" }
        if last == 1 { return "работа" }
        if last >= 2 && last <= 4 { return "работы" }
        return "работ"
    }
}

// MARK: - Biography Section

private struct PersonBiographySection: View {
    let biography: String
    @State private var isExpanded: Bool = false
    @State private var canExpand: Bool = false
    @State private var fullHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Биография")
                .font(.system(size: 18, weight: .bold))

            ZStack(alignment: .bottomLeading) {
                Text(biography)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineSpacing(4)
                    .lineLimit(isExpanded ? nil : 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    visibleHeight = geo.size.height
                                    checkTruncation()
                                }
                                .onChange(of: geo.size.height) { _, newHeight in
                                    visibleHeight = newHeight
                                    checkTruncation()
                                }
                        }
                    )
                    .mask(
                        Group {
                            if canExpand && !isExpanded {
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: .black, location: 0.0),
                                        .init(color: .black, location: 0.5),
                                        .init(color: .clear, location: 1.0)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            } else {
                                Color.black
                            }
                        }
                    )
            }
            .background(
                Text(biography)
                    .font(.system(size: 15, weight: .regular))
                    .lineSpacing(4)
                    .lineLimit(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    fullHeight = geo.size.height
                                    checkTruncation()
                                }
                                .onChange(of: geo.size.height) { _, newHeight in
                                    fullHeight = newHeight
                                    checkTruncation()
                                }
                        }
                    )
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)

            if canExpand {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "Свернуть" : "Читать далее")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .heavy))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, isExpanded ? 10 : -20)
                .zIndex(1)
            }
        }
    }

    private func checkTruncation() {
        if !isExpanded {
            canExpand = fullHeight > visibleHeight + 2
        }
    }
}

// MARK: - Extra Info Block (Awards, Key Projects, Facts)

private struct PersonExtraInfoBlock: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .bold))

            Text(content)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.primary.opacity(0.85))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Biography Parser & Sanitizer

private struct ParsedBiography {
    let bio: String
    let awards: String?
    let keyProjects: String?
    let interestingFact: String?

    static func parse(from raw: String?, details: PersonDetailsDto) -> ParsedBiography {
        var awards = details.awards
        var keyProjects = details.keyProjects
        var interestingFact = details.interestingFact

        guard let text = raw, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ParsedBiography(bio: "", awards: awards, keyProjects: keyProjects, interestingFact: interestingFact)
        }

        // Remove emojis and pictographs
        var cleaned = text.unicodeScalars
            .filter { scalar in
                let v = scalar.value
                if v >= 0x1F300 && v <= 0x1FAFF { return false }
                if v >= 0x2600 && v <= 0x27BF { return false }
                if v == 0x2B50 || v == 0xFE0F { return false }
                return true
            }
            .map { String($0) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // If not already separated on backend, parse via regex
        if awards == nil {
            if let match = cleaned.range(of: #"(?:^|\n)\s*Главные награды\s*:\s*([\s\S]*?)(?=(?:\n\s*(?:Главные проекты|Интересн))|$)"#, options: .regularExpression) {
                let sub = String(cleaned[match])
                let parts = sub.components(separatedBy: ":")
                if parts.count > 1 {
                    awards = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                cleaned.removeSubrange(match)
            }
        }

        if keyProjects == nil {
            if let match = cleaned.range(of: #"(?:^|\n)\s*Главные проекты\s*:\s*([\s\S]*?)(?=(?:\n\s*(?:Главные награды|Интересн))|$)"#, options: .regularExpression) {
                let sub = String(cleaned[match])
                let parts = sub.components(separatedBy: ":")
                if parts.count > 1 {
                    keyProjects = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                cleaned.removeSubrange(match)
            }
        }

        if interestingFact == nil {
            if let match = cleaned.range(of: #"(?:^|\n)\s*Интересны[ей]\s+факты?\s*:\s*([\s\S]*?)(?=(?:\n\s*(?:Главные награды|Главные проекты))|$)"#, options: .regularExpression) {
                let sub = String(cleaned[match])
                let parts = sub.components(separatedBy: ":")
                if parts.count > 1 {
                    interestingFact = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                cleaned.removeSubrange(match)
            }
        }

        let finalBio = cleaned
            .replacingOccurrences(of: #"\n\s*\n+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedBiography(
            bio: finalBio,
            awards: awards,
            keyProjects: keyProjects,
            interestingFact: interestingFact
        )
    }
}

// MARK: - Photos Section

private struct PersonPhotosSection: View {
    let photos: [String]
    let allPhotos: [String]
    let namespace: Namespace.ID
    let onSelect: (Int, String) -> Void
    let onSave: (String) -> Void
    let onShare: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Фотографии")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(photos, id: \.self) { photoUrl in
                        let idx = allPhotos.firstIndex(of: photoUrl) ?? 0
                        let transitionId = "person_photo_\(idx)"

                        Button {
                            onSelect(idx, transitionId)
                        } label: {
                            AsyncCachedImage(url: URL(string: photoUrl)) {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 120, height: 160)
                                    .shimmer()
                            } content: { img in
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 120, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            } fallback: {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 120, height: 160)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .matchedTransitionSource(id: transitionId, in: namespace)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onSelect(idx, transitionId)
                            } label: {
                                Label("Открыть фото", systemImage: "arrow.up.left.and.arrow.down.right")
                            }
                            Button {
                                onSave(photoUrl)
                            } label: {
                                Label("Сохранить в Фото", systemImage: "photo.badge.arrow.down")
                            }
                            Button {
                                onShare(photoUrl)
                            } label: {
                                Label("Поделиться", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Full-Screen Photo Gallery Viewer

struct PersonPhotoGalleryView: View {
    let photos: [String]
    @Binding var selectedIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var showControls: Bool = true

    private var safeAreaInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                if window.safeAreaInsets.top > 0 {
                    return window.safeAreaInsets
                }
            }
        }
        return UIEdgeInsets(top: 54, left: 0, bottom: 34, right: 0)
    }

    private var topPadding: CGFloat {
        let top = safeAreaInsets.top
        return max(top, 47) + 16
    }

    private var bottomPadding: CGFloat {
        let bottom = safeAreaInsets.bottom
        return max(bottom, 34) + 20
    }

    var body: some View {
        ZStack {
            // Native UIKit Pager with UIScrollView per page & interactive pull-down-to-dismiss
            PhotoGalleryPagerRepresentable(
                photos: photos,
                currentIndex: $selectedIndex,
                onSingleTap: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls.toggle()
                    }
                },
                onDismiss: {
                    dismiss()
                },
                onControlsVisibilityChange: { visible in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls = visible
                    }
                }
            )
            .ignoresSafeArea()

            // Floating Controls Overlay
            VStack {
                // Top Bar
                HStack {
                    TelegramGlassIconButton(systemName: "xmark") {
                        dismiss()
                    }

                    Spacer()

                    if photos.count > 1 {
                        Text("\(selectedIndex + 1) из \(photos.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: Capsule())
                    }

                    Spacer()

                    TelegramGlassIconButton(systemName: "square.and.arrow.up") {
                        sharePhoto(at: selectedIndex)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, topPadding)

                Spacer()

                // Bottom Save Button
                Button {
                    Task { await savePhoto(at: selectedIndex) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Сохранить в Фото")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .padding(.bottom, bottomPadding)
            }
            .opacity(showControls ? 1.0 : 0.0)
            .allowsHitTesting(showControls)
            .animation(.easeInOut(duration: 0.2), value: showControls)
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(!showControls)
        .persistentSystemOverlays(showControls ? .visible : .hidden)
    }

    private func savePhoto(at index: Int) async {
        guard photos.indices.contains(index), let url = URL(string: photos[index]) else { return }
        let effectiveUrl = resolveEffectiveUrl(url)
        do {
            var request = URLRequest(url: effectiveUrl, cachePolicy: .returnCacheDataElseLoad)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let image = UIImage(data: data) else {
                ToastManager.shared.show(title: "Не удалось загрузить фото", icon: "xmark.circle")
                return
            }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                ToastManager.shared.show(title: "Нет доступа к Фото", icon: "lock")
                return
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            ToastManager.shared.show(title: "Сохранено в Фото", icon: "checkmark.circle.fill")
        } catch {
            ToastManager.shared.show(title: "Ошибка: фото не сохранено", icon: "xmark.circle")
        }
    }

    private func sharePhoto(at index: Int) {
        guard photos.indices.contains(index), let url = URL(string: photos[index]) else { return }
        let effectiveUrl = resolveEffectiveUrl(url)
        var items: [Any] = []
        if let cached = ImageCache.shared.image(forKey: effectiveUrl.absoluteString) {
            items.append(cached)
        } else if let data = URLCache.shared.cachedResponse(for: URLRequest(url: effectiveUrl))?.data,
                  let img = UIImage(data: data) {
            items.append(img)
        } else {
            items.append(effectiveUrl)
        }
        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
           let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController { topVC = presented }
            av.popoverPresentationController?.sourceView = topVC.view
            topVC.present(av, animated: true)
        }
    }

    private func resolveEffectiveUrl(_ targetUrl: URL) -> URL {
        let str = targetUrl.absoluteString
        if str.contains("image.tmdb.org/t/p/") {
            let proxied = str.replacingOccurrences(of: "https://image.tmdb.org/t/p/", with: "https://api-sloosh.vercel.app/api/v1/images/tmdb/")
            return URL(string: proxied) ?? targetUrl
        }
        return targetUrl
    }
}

// MARK: - Native UIKit Photo Pager Representable

private struct PhotoGalleryPagerRepresentable: UIViewControllerRepresentable {
    let photos: [String]
    @Binding var currentIndex: Int
    let onSingleTap: () -> Void
    let onDismiss: () -> Void
    let onControlsVisibilityChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> PhotoGalleryContainerViewController {
        let vc = PhotoGalleryContainerViewController(
            photos: photos,
            initialIndex: currentIndex
        )
        vc.onIndexChanged = { newIndex in
            context.coordinator.parent.currentIndex = newIndex
        }
        vc.onSingleTap = onSingleTap
        vc.onDismiss = onDismiss
        vc.onControlsVisibilityChange = onControlsVisibilityChange
        return vc
    }

    func updateUIViewController(_ uiViewController: PhotoGalleryContainerViewController, context: Context) {
        if uiViewController.currentIndex != currentIndex {
            uiViewController.goTo(index: currentIndex, animated: true)
        }
    }

    class Coordinator {
        var parent: PhotoGalleryPagerRepresentable
        init(_ parent: PhotoGalleryPagerRepresentable) {
            self.parent = parent
        }
    }
}

// MARK: - Photo Gallery Container View Controller

private final class PhotoGalleryContainerViewController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
    let photos: [String]
    var currentIndex: Int
    var onIndexChanged: ((Int) -> Void)?
    var onSingleTap: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onControlsVisibilityChange: ((Bool) -> Void)?

    private let dimmingView = UIView()
    private var pageViewController: UIPageViewController!
    private var panGesture: UIPanGestureRecognizer!

    init(photos: [String], initialIndex: Int) {
        self.photos = photos
        self.currentIndex = initialIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        // Dimming backdrop
        dimmingView.backgroundColor = .black
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimmingView)
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Page view controller with 20pt inter-page spacing
        pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: 20]
        )
        pageViewController.dataSource = self
        pageViewController.delegate = self

        addChild(pageViewController)
        pageViewController.view.backgroundColor = .clear
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageViewController.view)
        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pageViewController.didMove(toParent: self)

        if photos.indices.contains(currentIndex) {
            let initialVC = makePhotoPageVC(index: currentIndex)
            pageViewController.setViewControllers([initialVC], direction: .forward, animated: false)
        }

        // Pull-down-to-dismiss gesture
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        view.addGestureRecognizer(panGesture)
    }

    var currentPhotoVC: PhotoPageViewController? {
        return pageViewController.viewControllers?.first as? PhotoPageViewController
    }

    func goTo(index: Int, animated: Bool) {
        guard photos.indices.contains(index) else { return }
        if let current = currentPhotoVC, current.pageIndex == index {
            self.currentIndex = index
            return
        }
        let direction: UIPageViewController.NavigationDirection = index >= currentIndex ? .forward : .reverse
        currentIndex = index
        let vc = makePhotoPageVC(index: index)
        pageViewController.setViewControllers([vc], direction: direction, animated: animated)
    }

    private func makePhotoPageVC(index: Int) -> PhotoPageViewController {
        let vc = PhotoPageViewController(photoUrl: photos[index], pageIndex: index)
        vc.onSingleTap = { [weak self] in
            self?.onSingleTap?()
        }
        return vc
    }

    // MARK: - UIPageViewControllerDataSource

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let current = viewController as? PhotoPageViewController else { return nil }
        let targetIndex = current.pageIndex - 1
        guard targetIndex >= 0, targetIndex < photos.count else { return nil }
        return makePhotoPageVC(index: targetIndex)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let current = viewController as? PhotoPageViewController else { return nil }
        let targetIndex = current.pageIndex + 1
        guard targetIndex >= 0, targetIndex < photos.count else { return nil }
        return makePhotoPageVC(index: targetIndex)
    }

    // MARK: - UIPageViewControllerDelegate

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        if completed, let current = pageViewController.viewControllers?.first as? PhotoPageViewController {
            currentIndex = current.pageIndex
            onIndexChanged?(current.pageIndex)
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == panGesture {
            // Only pull-to-dismiss if the photo is NOT zoomed in
            guard let current = currentPhotoVC, !current.isZoomed else { return false }
            let velocity = panGesture.velocity(in: view)
            // Dominantly vertical downward gesture (at least 1.5x more vertical than horizontal)
            return velocity.y > 0 && abs(velocity.y) > abs(velocity.x) * 1.5
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    // MARK: - Pull Down to Dismiss Handler

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            onControlsVisibilityChange?(false)
        case .changed:
            if translation.y > 0 {
                let progress = min(translation.y / view.bounds.height, 1.0)
                let scale = max(0.82, 1.0 - progress * 0.22)
                pageViewController.view.transform = CGAffineTransform(translationX: translation.x * 0.15, y: translation.y)
                    .scaledBy(x: scale, y: scale)

                let alpha = max(0.0, 1.0 - Double(translation.y / 350.0))
                dimmingView.alpha = CGFloat(alpha)
            } else {
                pageViewController.view.transform = .identity
                dimmingView.alpha = 1.0
            }
        case .ended:
            if translation.y > 90 || velocity.y > 600 {
                // Smooth dismiss animation
                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                    self.pageViewController.view.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
                    self.dimmingView.alpha = 0
                } completion: { _ in
                    self.onDismiss?()
                }
            } else {
                // Elastic snap back
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5, options: []) {
                    self.pageViewController.view.transform = .identity
                    self.dimmingView.alpha = 1.0
                } completion: { _ in
                    self.onControlsVisibilityChange?(true)
                }
            }
        case .cancelled:
            UIView.animate(withDuration: 0.3) {
                self.pageViewController.view.transform = .identity
                self.dimmingView.alpha = 1.0
            }
            self.onControlsVisibilityChange?(true)
        default:
            break
        }
    }
}

// MARK: - Photo Page View Controller (Zoomable & Padded Edge-to-Edge)

private final class PhotoPageViewController: UIViewController, UIScrollViewDelegate {
    let photoUrl: String
    let pageIndex: Int
    var onSingleTap: (() -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private var loadTask: Task<Void, Never>?

    var isZoomed: Bool {
        return scrollView.zoomScale > 1.05
    }

    init(photoUrl: String, pageIndex: Int) {
        self.photoUrl = photoUrl
        self.pageIndex = pageIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        // True edge-to-edge full-screen scroll view
        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)

        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        setupGestures()
        loadImage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scrollView.zoomScale <= 1.01 {
            updateImageLayout()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if scrollView.zoomScale > 1.0 {
            scrollView.zoomScale = 1.0
            centerImage()
            scrollView.panGestureRecognizer.isEnabled = false
        }
    }

    deinit {
        loadTask?.cancel()
    }

    private func setupGestures() {
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)

        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(singleTap)
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > 1.05 {
            scrollView.setZoomScale(1.0, animated: true)
            scrollView.panGestureRecognizer.isEnabled = false
        } else {
            scrollView.panGestureRecognizer.isEnabled = true
            let touchPoint = gesture.location(in: imageView)
            let targetScale: CGFloat = 2.5
            let targetW = scrollView.bounds.width / targetScale
            let targetH = scrollView.bounds.height / targetScale
            let zoomRect = CGRect(
                x: touchPoint.x - targetW / 2,
                y: touchPoint.y - targetH / 2,
                width: targetW,
                height: targetH
            )
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }

    // MARK: - UIScrollViewDelegate

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        scrollView.panGestureRecognizer.isEnabled = true
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if scale <= 1.01 {
            scrollView.zoomScale = 1.0
            centerImage()
            scrollView.panGestureRecognizer.isEnabled = false
        } else {
            scrollView.panGestureRecognizer.isEnabled = true
        }
    }

    private func centerImage() {
        let boundsSize = scrollView.bounds.size
        var frameToCenter = imageView.frame

        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }

        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }

        imageView.frame = frameToCenter
    }

    private func updateImageLayout() {
        guard let image = imageView.image else { return }
        let boundsSize = view.bounds.size
        guard boundsSize.width > 0, boundsSize.height > 0 else { return }

        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }

        scrollView.zoomScale = 1.0
        let scale = min(boundsSize.width / imgSize.width, boundsSize.height / imgSize.height)
        let fitW = imgSize.width * scale
        let fitH = imgSize.height * scale

        imageView.frame = CGRect(x: 0, y: 0, width: fitW, height: fitH)
        scrollView.contentSize = CGSize(width: fitW, height: fitH)
        centerImage()
        scrollView.panGestureRecognizer.isEnabled = false
    }

    private func resolveEffectiveUrl(_ targetUrl: URL) -> URL {
        let str = targetUrl.absoluteString
        if str.contains("image.tmdb.org/t/p/") {
            let proxied = str.replacingOccurrences(of: "https://image.tmdb.org/t/p/", with: "https://api-sloosh.vercel.app/api/v1/images/tmdb/")
            return URL(string: proxied) ?? targetUrl
        }
        return targetUrl
    }

    private func loadImage() {
        guard let url = URL(string: photoUrl) else { return }
        let effectiveUrl = resolveEffectiveUrl(url)

        if let cached = ImageCache.shared.image(forKey: effectiveUrl.absoluteString) {
            imageView.image = cached
            updateImageLayout()
            return
        }

        var request = URLRequest(url: effectiveUrl, cachePolicy: .returnCacheDataElseLoad)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        if let cachedResponse = URLCache.shared.cachedResponse(for: request),
           let img = UIImage(data: cachedResponse.data) {
            ImageCache.shared.insertImage(img, forKey: effectiveUrl.absoluteString)
            imageView.image = img
            updateImageLayout()
            return
        }

        spinner.startAnimating()
        loadTask = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let img = UIImage(data: data) else {
                    await MainActor.run {
                        self?.spinner.stopAnimating()
                    }
                    return
                }
                ImageCache.shared.insertImage(img, forKey: effectiveUrl.absoluteString)
                await MainActor.run {
                    self?.spinner.stopAnimating()
                    self?.imageView.image = img
                    self?.updateImageLayout()
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self?.spinner.stopAnimating()
                    }
                }
            }
        }
    }
}

// MARK: - Filmography Section

private struct PersonFilmographySection: View {
    @ObservedObject var viewModel: PersonDetailViewModel
    let details: PersonDetailsDto
    let namespace: Namespace.ID

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with tabs
            VStack(alignment: .leading, spacing: 12) {
                Text("Фильмография")
                    .font(.system(size: 18, weight: .bold))

                HStack(spacing: 8) {
                    ForEach(PersonDetailViewModel.FilmographyTab.allCases) { tab in
                        let count: Int = {
                            switch tab {
                            case .all: return details.filmography?.count ?? 0
                            case .movies: return details.filmography?.filter { $0.type == "movie" }.count ?? 0
                            case .series: return details.filmography?.filter { $0.type == "tv" }.count ?? 0
                            }
                        }()

                        if count > 0 || tab == .all {
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.prepare()
                                generator.impactOccurred()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    viewModel.selectedFilmographyTab = tab
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(tab.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("\(count)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(viewModel.selectedFilmographyTab == tab ? Color.black.opacity(0.75) : Color.secondary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(viewModel.selectedFilmographyTab == tab ? Color.white : Color.clear)
                                )
                                .foregroundStyle(viewModel.selectedFilmographyTab == tab ? Color.black : Color.white)
                                .glassEffect(viewModel.selectedFilmographyTab == tab ? .regular : .regular.interactive(), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)

            // Grid
            let items = viewModel.filteredFilmography
            if items.isEmpty {
                Text("Нет доступных фильмов")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(items) { movie in
                        let transitionID = "filmography_\(movie.id)"
                        NavigationLink(
                            destination: DetailsView(
                                movieId: movie.id,
                                mediaType: movie.type,
                                navigationTransitionID: transitionID,
                                navigationTransitionNamespace: namespace
                            ).navigationBarBackButtonHidden(true)
                        ) {
                            MoviePosterCard(movie: movie)
                                .matchedTransitionSource(id: transitionID, in: namespace)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            NavigationLink(
                                destination: DetailsView(
                                    movieId: movie.id,
                                    mediaType: movie.type,
                                    navigationTransitionID: transitionID,
                                    navigationTransitionNamespace: namespace
                                ).navigationBarBackButtonHidden(true)
                            ) {
                                Label("Подробнее", systemImage: "info.circle")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Skeleton View

private struct PersonSkeletonView: View {
    var body: some View {
        VStack(spacing: 20) {
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(height: 380)
                .shimmer()

            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 200, height: 26)
                    .shimmer()

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 140, height: 16)
                    .shimmer()
            }

            RoundedRectangle(cornerRadius: 18)
                .fill(Color.gray.opacity(0.12))
                .frame(height: 120)
                .padding(.horizontal, 16)
                .shimmer()

            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 130, height: 20)
                    .shimmer()

                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.12))
                            .frame(height: 170)
                            .shimmer()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - View Model

@MainActor
final class PersonDetailViewModel: ObservableObject {
    @Published var details: PersonDetailsDto? = nil
    @Published var isLoading: Bool = true
    @Published var errorMessage: String? = nil
    @Published var selectedFilmographyTab: FilmographyTab = .all

    enum FilmographyTab: String, CaseIterable, Identifiable {
        case all = "Все"
        case movies = "Фильмы"
        case series = "Сериалы"

        var id: String { rawValue }
    }

    let personId: Int

    init(personId: Int) {
        self.personId = personId
    }

    func loadDetails(force: Bool = false) async {
        if !force && details != nil { return }
        isLoading = true
        errorMessage = nil
        do {
            let result = try await MoviesRepository.shared.getPersonDetails(id: personId)
            self.details = result
            self.isLoading = false
        } catch {
            self.errorMessage = "Не удалось загрузить данные об актёре"
            self.isLoading = false
        }
    }

    var filteredFilmography: [MediaDto] {
        guard let list = details?.filmography else { return [] }
        switch selectedFilmographyTab {
        case .all:
            return list
        case .movies:
            return list.filter { $0.type == "movie" }
        case .series:
            return list.filter { $0.type == "tv" }
        }
    }
}

// MARK: - Zoom Navigation Transition Modifier

private struct OptionalZoomTransitionModifier: ViewModifier {
    let sourceID: String?
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let sourceID, let namespace {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

private extension View {
    func optionalZoomTransition(sourceID: String?, in namespace: Namespace.ID?) -> some View {
        modifier(OptionalZoomTransitionModifier(sourceID: sourceID, namespace: namespace))
    }
}

