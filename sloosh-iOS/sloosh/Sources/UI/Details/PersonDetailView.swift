import SwiftUI
import Photos

struct PersonDetailView: View {
    let personId: Int
    let initialName: String?

    @StateObject private var viewModel: PersonDetailViewModel
    @State private var dominantColor: UIColor? = nil
    @State private var isTitleAtTop: Bool = false
    @Environment(\.dismiss) private var dismiss

    init(personId: Int, initialName: String? = nil) {
        self.personId = personId
        self.initialName = initialName
        _viewModel = StateObject(wrappedValue: PersonDetailViewModel(personId: personId))
    }

    private var effectiveBackgroundColor: Color {
        if let dominant = dominantColor {
            return Color(uiColor: dominant).opacity(0.35)
        }
        return Color(red: 0.06, green: 0.06, blue: 0.08)
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

    private func sharePerson(details: PersonDetailsDto) {
        var items: [Any] = []
        let title = details.name
        items.append(title)

        if let photoStr = details.photo, let url = URL(string: photoStr),
           let data = URLCache.shared.cachedResponse(for: URLRequest(url: url))?.data,
           let img = UIImage(data: data) {
            items.append(img)
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
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                if isTitleAtTop {
                    Text(viewModel.details?.name ?? initialName ?? "")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 68)
                        .transition(.opacity)
                }

                HStack {
                    TelegramGlassIconButton(systemName: "chevron.left") {
                        dismiss()
                    }

                    Spacer()

                    if let details = viewModel.details {
                        TelegramGlassIconButton(systemName: "square.and.arrow.up") {
                            sharePerson(details: details)
                        }
                    }
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
            ZStack {
                Color.black.ignoresSafeArea()

                LinearGradient(
                    stops: [
                        .init(color: effectiveBackgroundColor, location: 0.0),
                        .init(color: effectiveBackgroundColor.opacity(0.5), location: 0.35),
                        .init(color: Color.black.opacity(0.95), location: 0.65),
                        .init(color: Color.black, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: dominantColor)
            }
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

        // Stretchy Parallax Hero Header
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
            .offset(y: offset)
        }
        .frame(height: baseHeight)

        // Information stack
        VStack(spacing: 20) {
            // Title & original name
            VStack(spacing: 6) {
                Text(details.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
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

                if let originalName = details.originalName, !originalName.isEmpty, originalName.lowercased() != details.name.lowercased() {
                    Text(originalName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                if let department = details.department ?? details.knownForDepartment, !department.isEmpty {
                    Text(department)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.slooshAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .padding(.top, 4)
                }
            }

            // Quick Stats / Metadata card
            PersonMetadataSection(details: details)

            // Biography
            if let bio = details.biography, !bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PersonBiographySection(biography: bio)
                    .padding(.horizontal, 16)
            }

            // Additional Photos (if present)
            if let photos = details.photos, photos.count > 1 {
                PersonPhotosSection(photos: photos)
            }

            // Filmography
            PersonFilmographySection(viewModel: viewModel, details: details)
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
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.4), location: 0.05),
                    .init(color: .black.opacity(0.85), location: 0.12),
                    .init(color: .black, location: 0.20),
                    .init(color: .black, location: 0.60),
                    .init(color: .black.opacity(0.85), location: 0.75),
                    .init(color: .black.opacity(0.40), location: 0.88),
                    .init(color: .black.opacity(0.12), location: 0.95),
                    .init(color: .clear, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Metadata Section

private struct PersonMetadataSection: View {
    let details: PersonDetailsDto

    var body: some View {
        VStack(spacing: 12) {
            if let birth = details.formattedBirthdayWithAge {
                infoRow(icon: "calendar", title: "Дата рождения", value: birth)
            }
            if let place = details.placeOfBirth, !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                infoRow(icon: "mappin.circle.fill", title: "Место рождения", value: place)
            }
            if let death = details.deathday, !death.isEmpty {
                infoRow(icon: "clock.badge.xmark.fill", title: "Дата смерти", value: death)
            }
            if let count = details.filmography?.count, count > 0 {
                infoRow(icon: "film.stack.fill", title: "Карьера", value: "\(count) \(declinedProjects(count))")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.slooshAccent)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
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

// MARK: - Photos Section

private struct PersonPhotosSection: View {
    let photos: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Фотографии")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(photos, id: \.self) { photoUrl in
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
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Filmography Section

private struct PersonFilmographySection: View {
    @ObservedObject var viewModel: PersonDetailViewModel
    let details: PersonDetailsDto

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
                        NavigationLink(
                            destination: DetailsView(
                                movieId: movie.id,
                                mediaType: movie.type,
                                navigationTransitionID: nil,
                                navigationTransitionNamespace: nil
                            ).navigationBarBackButtonHidden(true)
                        ) {
                            MoviePosterCard(movie: movie)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            NavigationLink(
                                destination: DetailsView(
                                    movieId: movie.id,
                                    mediaType: movie.type,
                                    navigationTransitionID: nil,
                                    navigationTransitionNamespace: nil
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
