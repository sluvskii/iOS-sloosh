import SwiftUI

struct QualitySelectionSheet: View {
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    
    @State private var selectedQuality: VideoQualityPreference = .auto
    @State private var rememberChoice: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    let onSelect: (VideoQualityPreference) -> Void
    
    private let availableQualities: [VideoQualityPreference] = [
        .auto,
        .q1080,
        .q720,
        .q480,
        .q360
    ]
    
    init(onSelect: @escaping (VideoQualityPreference) -> Void) {
        self.onSelect = onSelect
        let savedQualityRaw = UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? ""
        let savedQuality = VideoQualityPreference(rawValue: savedQualityRaw) ?? .auto
        let initialQuality = (savedQuality == .ask) ? .auto : savedQuality
        _selectedQuality = State(initialValue: initialQuality)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    qualitySection
                    
                    rememberChoiceSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .contentMargins(.top, 16, for: .scrollContent)
            .contentMargins(.bottom, 28, for: .scrollContent)
            .safeAreaInset(edge: .bottom) {
                bottomActionButton
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                headerBar
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .background(
                        VariableBlurView(tintColor: .clear, tintOpacity: 0.0)
                            .padding(.bottom, -30)
                            .ignoresSafeArea(edges: .top)
                    )
            }
            .background(Color.clear)
        }
        .presentationDetents([.fraction(0.48)])
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
    }
    
    private var headerBar: some View {
        ZStack {
            Text("Качество видео")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 220)
            
            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.glassPress)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Закрыть")
                
                Spacer()
                
                Color.clear
                    .frame(width: 44, height: 44)
            }
        }
    }
    
    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Качество")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            
            FlowLayout(spacing: 8) {
                ForEach(availableQualities) { quality in
                    WatchSelectorChip(
                        title: quality.title,
                        isSelected: selectedQuality == quality,
                        isAvailable: true,
                        badge: qualityBadge(for: quality)
                    ) {
                        selectedQuality = quality
                    }
                    .equatable()
                }
            }
        }
    }
    
    private func qualityBadge(for quality: VideoQualityPreference) -> String? {
        switch quality {
        case .auto:
            return "Реком."
        case .q1080:
            return "HD"
        default:
            return nil
        }
    }
    
    private var rememberChoiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $rememberChoice) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.slooshAccent)
                    Text("Запомнить выбор")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .tint(Color.slooshAccent)
            
            Text("Вы всегда можете изменить качество по умолчанию в настройках.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemFill).opacity(0.45))
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
    
    private var bottomActionButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if rememberChoice {
                preferredQuality = selectedQuality
                UserDefaults.standard.set(selectedQuality.rawValue, forKey: "preferredVideoQuality")
            }
            onSelect(selectedQuality)
            dismiss()
        }) {
            HStack(spacing: 8) {
                Text("Продолжить")
                    .font(.system(size: 19, weight: .heavy))
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 26)
            .frame(height: 50)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.94))
            )
            .glassEffect(.regular.interactive(), in: .capsule)
            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.glassPress)
        .padding(.bottom, 8)
    }
}
