import SwiftUI
import PhotosUI

public struct ChannelInfoView: View {
    public let channel: ChannelModel

    @ObservedObject private var authRepo = AuthRepository.shared
    @ObservedObject private var repo = MessengerRepository.shared
    @Environment(\.dismiss) private var dismiss

    @State private var currentChannel: ChannelModel
    @State private var isMuted: Bool = false
    @State private var showEditSheet: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showLeaveConfirm: Bool = false
    @State private var isActionLoading: Bool = false

    public init(channel: ChannelModel) {
        self.channel = channel
        self._currentChannel = State(initialValue: channel)
    }

    private var isOwner: Bool {
        guard let currentUserId = authRepo.currentUser?.id else { return false }
        return currentChannel.ownerId == currentUserId
    }

    private var isSubscribed: Bool {
        repo.isSubscribed(channelId: currentChannel.id)
    }

    private var subscriberCountText: String {
        let count = currentChannel.subscriberCount
        return "\(count) \(declensionSubscribers(count))"
    }

    public var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header Section (Avatar + Title + Tag + Subscribers)
                    headerSection
                        .padding(.top, 24)

                    // Description & Tag Card
                    infoCardSection

                    // Actions Section
                    actionsSection
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Информация")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showEditSheet = true
                    } label: {
                        Text("Изменить")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.slooshAccent)
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditChannelSheet(channel: currentChannel) { updated in
                self.currentChannel = updated
            }
        }
        .confirmationDialog(
            "Удалить канал «\(currentChannel.name)»?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Удалить канал", role: .destructive) {
                deleteChannelAction()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все посты и подписчики канала будут удалены без возможности восстановления.")
        }
        .confirmationDialog(
            "Покинуть канал «\(currentChannel.name)»?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Покинуть канал", role: .destructive) {
                leaveChannelAction()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            SlooshAvatarView(
                avatarSource: currentChannel.avatarUrl,
                fallbackText: currentChannel.name,
                size: 100,
                isChannel: true
            )

            VStack(spacing: 4) {
                Text(currentChannel.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                Text(currentChannel.displayTag)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.slooshAccent)

                Text(subscriberCountText)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Info Card

    private var infoCardSection: some View {
        VStack(spacing: 0) {
            // Tag row
            HStack(spacing: 14) {
                Image(systemName: "at")
                    .frame(width: 22)
                    .foregroundColor(Color.slooshAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Тег канала")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(currentChannel.displayTag)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Description row (if present)
            if !currentChannel.description.isEmpty {
                Divider()
                    .padding(.leading, 52)

                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "text.alignleft")
                        .frame(width: 22)
                        .foregroundColor(Color.slooshAccent)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Описание")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(currentChannel.description)
                            .font(.system(size: 15))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 0) {
            if isOwner {
                Button {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "trash.fill")
                            .frame(width: 22)
                            .foregroundColor(.red)
                        Text("Удалить канал")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(PeakPressButtonStyle())
            } else if isSubscribed {
                Button {
                    toggleMuteAction()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: isMuted ? "bell.fill" : "bell.slash.fill")
                            .frame(width: 22)
                            .foregroundColor(.primary)
                        Text(isMuted ? "Включить звук" : "Без звука")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(PeakPressButtonStyle())

                Divider()
                    .padding(.leading, 52)

                Button {
                    showLeaveConfirm = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .frame(width: 22)
                            .foregroundColor(.red)
                        Text("Покинуть канал")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(PeakPressButtonStyle())
            } else {
                Button {
                    subscribeAction()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "megaphone.fill")
                            .frame(width: 22)
                            .foregroundColor(Color.slooshAccent)
                        Text("Подписаться на канал")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.slooshAccent)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .buttonStyle(PeakPressButtonStyle())
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func deleteChannelAction() {
        isActionLoading = true
        Task {
            _ = await repo.deleteChannel(channelId: currentChannel.id)
            await MainActor.run {
                isActionLoading = false
                dismiss()
            }
        }
    }

    private func leaveChannelAction() {
        Task {
            _ = await repo.unsubscribeFromChannel(channelId: currentChannel.id)
            await MainActor.run {
                dismiss()
            }
        }
    }

    private func subscribeAction() {
        Task {
            _ = await repo.subscribeToChannel(channel: currentChannel)
        }
    }

    private func toggleMuteAction() {
        isMuted.toggle()
    }

    private func declensionSubscribers(_ count: Int) -> String {
        let remainder10 = count % 10
        let remainder100 = count % 100
        if remainder100 >= 11 && remainder100 <= 19 {
            return "подписчиков"
        }
        if remainder10 == 1 {
            return "подписчик"
        }
        if remainder10 >= 2 && remainder10 <= 4 {
            return "подписчика"
        }
        return "подписчиков"
    }
}

// MARK: - Edit Channel Sheet

public struct EditChannelSheet: View {
    public let channel: ChannelModel
    public let onSaved: (ChannelModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var repo = MessengerRepository.shared

    @State private var channelName: String
    @State private var channelTag: String
    @State private var channelDescription: String
    @State private var avatarDataString: String?
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    @State private var isCheckingTag: Bool = false
    @State private var tagStatusMessage: String? = nil
    @State private var isTagAvailable: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    public init(channel: ChannelModel, onSaved: @escaping (ChannelModel) -> Void) {
        self.channel = channel
        self.onSaved = onSaved
        self._channelName = State(initialValue: channel.name)
        self._channelTag = State(initialValue: channel.tag)
        self._channelDescription = State(initialValue: channel.description)
        self._avatarDataString = State(initialValue: channel.avatarUrl)
    }

    private var cleanTag: String {
        TagValidator.sanitize(channelTag)
    }

    private var isFormValid: Bool {
        guard !channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isSaving else { return false }
        if cleanTag != channel.tag {
            return isTagAvailable && !cleanTag.isEmpty
        }
        return true
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Avatar & Photo Picker
                    avatarSection
                        .padding(.top, 16)

                    // Form Fields
                    formFields

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    // Save Button
                    saveButton
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Настройки канала")
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

    private var avatarSection: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    SlooshAvatarView(
                        avatarSource: avatarDataString,
                        fallbackText: channelName.isEmpty ? "S" : channelName,
                        size: 96,
                        isChannel: true
                    )

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

    private var formFields: some View {
        VStack(spacing: 16) {
            // Name Field
            VStack(alignment: .leading, spacing: 6) {
                Text("НАЗВАНИЕ")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                TextField("Название канала", text: $channelName)
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

            // Tag Field
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

                TextField("Описание", text: $channelDescription, axis: .vertical)
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

    private var saveButton: some View {
        Button {
            saveChannelAction()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                    Text("Сохранить")
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

    private func checkTagRealtime(_ rawTag: String) {
        let clean = TagValidator.sanitize(rawTag)
        guard !clean.isEmpty else {
            tagStatusMessage = nil
            isTagAvailable = false
            return
        }

        if clean == channel.tag {
            tagStatusMessage = "Текущий тег канала"
            isTagAvailable = true
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
            let result = await repo.checkChannelTagAvailability(tag: clean, excludingChannelId: channel.id)
            await MainActor.run {
                self.isCheckingTag = false
                self.isTagAvailable = result.isAvailable
                self.tagStatusMessage = result.message
            }
        }
    }

    private func saveChannelAction() {
        guard isFormValid else { return }
        isSaving = true
        errorMessage = nil

        var updated = channel
        let oldTag = channel.tag
        updated.name = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.tag = cleanTag
        updated.description = channelDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.avatarUrl = avatarDataString

        Task {
            let success = await repo.updateChannelMetadata(channel: updated, oldTag: oldTag != updated.tag ? oldTag : nil)
            await MainActor.run {
                self.isSaving = false
                if success {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    dismiss()
                    onSaved(updated)
                } else {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    self.errorMessage = "Не удалось сохранить изменения."
                }
            }
        }
    }
}
