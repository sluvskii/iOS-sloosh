import SwiftUI

@available(iOS 26.0, *)
struct WatchSelectorOption: Identifiable, Hashable {
    let id: String
    let title: String
    var isSelected: Bool
    var isAvailable: Bool = true

    init(
        id: String? = nil,
        title: String,
        isSelected: Bool = false,
        isAvailable: Bool = true
    ) {
        self.id = id ?? title
        self.title = title
        self.isSelected = isSelected
        self.isAvailable = isAvailable
    }
}

@available(iOS 26.0, *)
struct NativeWatchSelectorSheet: View {
    let title: String
    let actionTitle: String
    let translationOptions: [WatchSelectorOption]
    let seasonOptions: [WatchSelectorOption]
    let episodeOptions: [WatchSelectorOption]
    let onTranslationTap: (WatchSelectorOption) -> Void
    let onSeasonTap: (WatchSelectorOption) -> Void
    let onEpisodeTap: (WatchSelectorOption) -> Void
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var hasPrimaryAction: Bool {
        translationOptions.contains(where: \.isSelected)
            || seasonOptions.contains(where: \.isSelected)
            || episodeOptions.contains(where: \.isSelected)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !translationOptions.isEmpty {
                        WatchSelectorSection(
                            title: "Озвучка",
                            options: translationOptions,
                            action: onTranslationTap
                        )
                    }

                    if !seasonOptions.isEmpty {
                        WatchSelectorSection(
                            title: "Сезон",
                            options: seasonOptions,
                            action: onSeasonTap
                        )
                    }

                    if !episodeOptions.isEmpty {
                        WatchSelectorSection(
                            title: "Серия",
                            options: episodeOptions,
                            action: onEpisodeTap
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .scrollIndicators(.hidden)
            .containerBackground(.clear, for: .navigation)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Закрыть")
                }

                ToolbarItem(placement: .bottomBar) {
                    Button(action: onConfirm) {
                        Label(actionTitle, systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(!hasPrimaryAction)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
    }
}

@available(iOS 26.0, *)
private struct WatchSelectorSection: View {
    let title: String
    let options: [WatchSelectorOption]
    let action: (WatchSelectorOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))

            GlassEffectContainer(spacing: 14) {
                WatchSelectorFlowLayout(spacing: 10) {
                    ForEach(options) { option in
                        WatchSelectorChip(option: option) {
                            action(option)
                        }
                    }
                }
            }
        }
    }
}

@available(iOS 26.0, *)
private struct WatchSelectorChip: View {
    let option: WatchSelectorOption
    let action: () -> Void

    var body: some View {
        Group {
            if option.isSelected {
                Button(action: action) {
                    Text(option.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.glassProminent)
            } else {
                Button(action: action) {
                    Text(option.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                .buttonStyle(.glass)
            }
        }
        .controlSize(.regular)
        .disabled(!option.isAvailable)
        .opacity(option.isAvailable ? 1.0 : 0.45)
    }
}

@available(iOS 26.0, *)
private struct WatchSelectorFlowLayout: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }

        return CGSize(
            width: proposal.width ?? currentX,
            height: currentY + rowHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
