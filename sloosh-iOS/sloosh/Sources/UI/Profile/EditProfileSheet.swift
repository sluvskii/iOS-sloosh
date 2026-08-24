import SwiftUI
import PhotosUI

public struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authRepo = AuthRepository.shared
    @ObservedObject private var messengerRepo = MessengerRepository.shared

    @State private var displayName: String = ""
    @State private var tag: String = ""
    @State private var avatarDataString: String? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    @State private var isCheckingTag: Bool = false
    @State private var tagStatusMessage: String? = nil
    @State private var isTagAvailable: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    public init() {}

    private var currentTagClean: String {
        TagValidator.sanitize(authRepo.currentUser?.tag ?? "")
    }

    private var inputTagClean: String {
        TagValidator.sanitize(tag)
    }

    private var isFormValid: Bool {
        guard !isSaving else { return false }
        if !inputTagClean.isEmpty && inputTagClean != currentTagClean {
            return isTagAvailable && TagValidator.validate(inputTagClean).isValid
        }
        return true
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Avatar Picker Section
                    avatarPickerSection
                        .padding(.top, 16)

                    // Profile Details Form
                    formFieldsSection

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
            .navigationTitle("Редактировать профиль")
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
        .onAppear {
            let user = authRepo.currentUser
            self.displayName = user?.displayName ?? ""
            self.tag = user?.tag ?? ""
            self.avatarDataString = user?.photoURL
        }
    }

    // MARK: - Subviews

    private var avatarPickerSection: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                ZStack(alignment: .bottomTrailing) {
                    SlooshAvatarView(
                        avatarSource: avatarDataString,
                        fallbackText: displayName.isEmpty ? (tag.isEmpty ? "S" : tag) : displayName,
                        size: 96,
                        accentColor: Color.slooshAccent
                    )

                    // Camera Badge
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

    private var formFieldsSection: some View {
        VStack(spacing: 18) {
            // Display Name
            VStack(alignment: .leading, spacing: 6) {
                Text("ИМЯ")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)

                TextField("Ваше имя", text: $displayName)
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

            // Tag Handle
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("УНИКАЛЬНЫЙ ТЕГ")
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

                    TextField("username", text: $tag)
                        .font(.system(size: 16))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: tag) { _, newValue in
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
                            !inputTagClean.isEmpty && !isTagAvailable
                                ? Color.red.opacity(0.5)
                                : Color.primary.opacity(0.1),
                            lineWidth: 1
                        )
                )

                if let msg = tagStatusMessage, !inputTagClean.isEmpty {
                    Text(msg)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isTagAvailable ? .secondary : .red)
                        .padding(.leading, 4)
                }
            }
        }
    }

    private var saveButton: some View {
        Button {
            saveProfileAction()
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

    // MARK: - Actions

    private func checkTagRealtime(_ rawTag: String) {
        let clean = TagValidator.sanitize(rawTag)
        guard !clean.isEmpty else {
            tagStatusMessage = nil
            isTagAvailable = true
            return
        }

        if clean == currentTagClean {
            tagStatusMessage = "Ваш текущий тег"
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
            let result = await messengerRepo.checkUserTagAvailability(tag: clean)
            await MainActor.run {
                self.isCheckingTag = false
                self.isTagAvailable = result.isAvailable
                self.tagStatusMessage = result.message
            }
        }
    }

    private func saveProfileAction() {
        guard isFormValid else { return }
        isSaving = true
        errorMessage = nil

        let nameToSave = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let tagToSave = inputTagClean
        let photoToSave = avatarDataString

        Task {
            let res = await authRepo.updateUserProfile(
                displayName: nameToSave.isEmpty ? nil : nameToSave,
                tag: tagToSave.isEmpty ? nil : tagToSave,
                photoURL: photoToSave
            )

            await MainActor.run {
                self.isSaving = false
                if res.success {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    ToastManager.shared.show(title: "Профиль обновлен", icon: "checkmark.circle.fill")
                    dismiss()
                } else {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    self.errorMessage = res.message
                }
            }
        }
    }
}
