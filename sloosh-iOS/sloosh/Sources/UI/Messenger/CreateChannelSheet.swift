import SwiftUI

public struct CreateChannelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authRepo = AuthRepository.shared
    @ObservedObject private var repo = MessengerRepository.shared

    public let onCreated: (ChannelModel) -> Void

    @State private var channelName: String = ""
    @State private var channelDescription: String = ""
    @State private var selectedEmoji: String = "📢"
    @State private var selectedColorHex: String = "#FF9F0A"
    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil

    private let emojiPresets = ["📢", "🎬", "🍿", "🚀", "🔥", "👑", "⚡️", "⭐️", "🎧", "🏆", "💎", "🔮"]
    private let colorPresets = [
        "#FF9F0A", // Orange
        "#FF453A", // Red
        "#30D158", // Green
        "#0A84FF", // Blue
        "#BF5AF2", // Purple
        "#64D2FF", // Cyan
        "#FFD60A", // Yellow
        "#B2FF00"  // Sloosh Neon
    ]

    public init(onCreated: @escaping (ChannelModel) -> Void) {
        self.onCreated = onCreated
    }

    private var selectedColor: Color {
        if let uiColor = UIColor(hex: selectedColorHex) {
            return Color(uiColor)
        }
        return .slooshAccent
    }

    private var isFormValid: Bool {
        !channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Avatar & Visual Identity Preview
                    avatarPreviewSection
                        .padding(.top, 16)

                    // Form Fields Section
                    formFieldsSection

                    // Emoji Preset Selector
                    emojiPickerSection

                    // Color Palette Selector
                    colorPickerSection

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    // Create Button
                    createButton
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Новый канал")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            Color.clear.glassEffect(in: .rect)
        }
    }

    // MARK: - Subviews

    private var avatarPreviewSection: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(selectedColor.opacity(0.2))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle()
                            .stroke(selectedColor.opacity(0.6), lineWidth: 2)
                    )
                    .overlay(
                        Text(selectedEmoji)
                            .font(.system(size: 48))
                    )
                    .shadow(color: selectedColor.opacity(0.3), radius: 12, x: 0, y: 4)

                // Channel Badge Indicator
                Circle()
                    .fill(Color(UIColor.systemBackground))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .fill(Color.slooshAccent)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "megaphone.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.black)
                            )
                    )
                    .offset(x: 2, y: 2)
            }

            Text(channelName.isEmpty ? "Название канала" : channelName)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(channelName.isEmpty ? .secondary : .primary)
                .lineLimit(1)
        }
    }

    private var formFieldsSection: some View {
        VStack(spacing: 14) {
            // Name Field
            VStack(alignment: .leading, spacing: 6) {
                Text("НАЗВАНИЕ")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                TextField("Например: КиноКлуб Sloosh", text: $channelName)
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }

            // Description Field
            VStack(alignment: .leading, spacing: 6) {
                Text("ОПИСАНИЕ")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                TextField("О чём этот канал? (необязательно)", text: $channelDescription, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
            }
        }
    }

    private var emojiPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ИКОНКА КАНАЛА")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(emojiPresets, id: \.self) { emoji in
                        Button {
                            selectedEmoji = emoji
                            let feedback = UISelectionFeedbackGenerator()
                            feedback.selectionChanged()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(selectedEmoji == emoji ? selectedColor.opacity(0.25) : Color.primary.opacity(0.06))
                                    .frame(width: 48, height: 48)

                                Text(emoji)
                                    .font(.system(size: 24))

                                if selectedEmoji == emoji {
                                    Circle()
                                        .stroke(selectedColor, lineWidth: 2)
                                        .frame(width: 48, height: 48)
                                }
                            }
                        }
                        .buttonStyle(PeakPressButtonStyle())
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("АКЦЕНТНЫЙ ЦВЕТ")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.leading, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(colorPresets, id: \.self) { hex in
                        let color = UIColor(hex: hex).map { Color($0) } ?? .slooshAccent
                        Button {
                            selectedColorHex = hex
                            let feedback = UISelectionFeedbackGenerator()
                            feedback.selectionChanged()
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(color)
                                    .frame(width: 40, height: 40)
                                    .shadow(color: color.opacity(selectedColorHex == hex ? 0.5 : 0.0), radius: 6, x: 0, y: 2)

                                if selectedColorHex == hex {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 3)
                                        .frame(width: 40, height: 40)

                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .black))
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .buttonStyle(PeakPressButtonStyle())
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    private var createButton: some View {
        Button {
            createChannelAction()
        } label: {
            HStack(spacing: 8) {
                if isCreating {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                    Text("Создать канал")
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule()
                    .fill(isFormValid ? Color.slooshAccent : Color.slooshAccent.opacity(0.4))
            )
            .glassEffect(in: Capsule())
        }
        .disabled(!isFormValid)
        .buttonStyle(PeakPressButtonStyle())
    }

    private func createChannelAction() {
        guard isFormValid else { return }
        isCreating = true
        errorMessage = nil

        let name = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = channelDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let emoji = selectedEmoji
        let hex = selectedColorHex

        Task {
            if let created = await repo.createChannel(
                name: name,
                description: desc,
                avatarEmoji: emoji,
                accentColorHex: hex
            ) {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                isCreating = false
                dismiss()
                onCreated(created)
            } else {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
                isCreating = false
                errorMessage = "Не удалось создать канал. Проверьте интернет-соединение или авторизацию."
            }
        }
    }
}
