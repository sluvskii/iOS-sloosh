import SwiftUI
import PhotosUI

public struct CreateChannelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authRepo = AuthRepository.shared
    @ObservedObject private var repo = MessengerRepository.shared

    public let onCreated: (ChannelModel) -> Void

    @State private var channelName: String = ""
    @State private var channelTag: String = ""
    @State private var channelDescription: String = ""
    @State private var avatarDataString: String? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    @State private var isCheckingTag: Bool = false
    @State private var tagStatusMessage: String? = nil
    @State private var isTagAvailable: Bool = false
    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil

    public init(onCreated: @escaping (ChannelModel) -> Void) {
        self.onCreated = onCreated
    }

    private var cleanTag: String {
        TagValidator.sanitize(channelTag)
    }

    private var isFormValid: Bool {
        !channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isTagAvailable &&
        !cleanTag.isEmpty &&
        !isCreating
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Avatar Section with Photo Picker
                    avatarPreviewSection
                        .padding(.top, 16)

                    // Form Fields Section
                    formFieldsSection

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    // Create Button (Liquid Glass Capsule)
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
            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    SlooshAvatarView(
                        avatarSource: avatarDataString,
                        fallbackText: channelName.isEmpty ? (cleanTag.isEmpty ? "S" : cleanTag) : channelName,
                        size: 96,
                        isChannel: true
                    )

                    // Camera / Add Photo Badge
                    Circle()
                        .fill(Color(UIColor.systemBackground))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Circle()
                                .fill(Color.slooshAccent)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.black)
                                )
                        )
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        if let compressedBase64 = AvatarImageProcessor.processAvatar(image: image) {
                            await MainActor.run {
                                self.avatarDataString = compressedBase64
                            }
                        }
                    }
                }
            }

            VStack(spacing: 4) {
                Text(channelName.isEmpty ? "Название канала" : channelName)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(channelName.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                if !cleanTag.isEmpty {
                    Text("@\(cleanTag)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.slooshAccent)
                }
            }

            if avatarDataString != nil {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    self.avatarDataString = nil
                    self.selectedPhotoItem = nil
                } label: {
                    Text("Удалить фото")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red)
                }
            }
        }
    }

    private var formFieldsSection: some View {
        VStack(spacing: 16) {
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

            // Channel Tag Field
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ТЕГ КАНАЛА")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    if isCheckingTag {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                .padding(.leading, 4)

                HStack(spacing: 4) {
                    Text("@")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.secondary)

                    TextField("cinema_club", text: $channelTag)
                        .font(.system(size: 16))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: channelTag) { _, newValue in
                            checkTagRealtime(newValue)
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            !cleanTag.isEmpty && !isTagAvailable
                                ? Color.red.opacity(0.5)
                                : Color.primary.opacity(0.1),
                            lineWidth: 1
                        )
                )

                if let msg = tagStatusMessage, !cleanTag.isEmpty {
                    Text(msg)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isTagAvailable ? .secondary : .red)
                        .padding(.leading, 4)
                }
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

    // MARK: - Actions

    private func checkTagRealtime(_ rawTag: String) {
        let clean = TagValidator.sanitize(rawTag)
        guard !clean.isEmpty else {
            tagStatusMessage = nil
            isTagAvailable = false
            return
        }

        let validation = TagValidator.validate(clean)
        guard validation.isValid else {
            tagStatusMessage = validation.message
            isTagAvailable = false
            return
        }

        isCheckingTag = true
        Task {
            let result = await repo.checkChannelTagAvailability(tag: clean)
            await MainActor.run {
                self.isCheckingTag = false
                self.isTagAvailable = result.isAvailable
                self.tagStatusMessage = result.message
            }
        }
    }

    private func createChannelAction() {
        guard isFormValid else { return }
        isCreating = true
        errorMessage = nil

        let name = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = channelDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = cleanTag
        let avatar = avatarDataString

        Task {
            if let newChannel = await repo.createChannel(
                name: name,
                description: desc,
                tag: tag,
                avatarUrl: avatar
            ) {
                await MainActor.run {
                    self.isCreating = false
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    dismiss()
                    onCreated(newChannel)
                }
            } else {
                await MainActor.run {
                    self.isCreating = false
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    self.errorMessage = "Не удалось создать канал. Проверьте соединение с сетью."
                }
            }
        }
    }
}
