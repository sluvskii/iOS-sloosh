import SwiftUI

/// Выбор целевого тир-листа для действия «В тир-лист» на карточке фильма.
/// Чисто нативный List: мои черновики + опубликованные, «+» создаёт новый
/// с этим фильмом уже в пуле.
struct TierTargetPickerSheet: View {
    let item: TierListItem
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [TierList] = []
    @State private var mine: [TierList] = []
    @State private var isLoading = true
    @State private var newDraft: TierList?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        AsyncCachedImage(
                            url: item.posterUrl.flatMap { URL(string: $0) },
                            placeholder: { Rectangle().fill(Color(UIColor.tertiarySystemFill)) },
                            content: { image in
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            },
                            fallback: { Rectangle().fill(Color(UIColor.tertiarySystemFill)) }
                        )
                        .frame(width: 44, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Text("Добавится в «Не распределено»")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Мои тир-листы") {
                    if isLoading {
                        ProgressView()
                    } else if drafts.isEmpty && mine.isEmpty {
                        Text("Пока нет тир-листов — нажмите «+», чтобы создать")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(drafts) { draft in
                            targetRow(draft, badge: "Черновик")
                        }
                        ForEach(mine) { list in
                            targetRow(list, badge: nil)
                        }
                    }
                }
            }
            .navigationTitle("В тир-лист")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { onDismiss() }
                        .foregroundStyle(.primary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        var seeded = TierListsRepository.shared.makeDraft(title: "Новый тир-лист")
                        seeded.unranked.append(item)
                        newDraft = seeded
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .task {
            drafts = TierListsRepository.shared.loadDrafts()
            mine = await TierListsRepository.shared.fetchLists(forAuthorId: AuthRepository.shared.currentUser?.id ?? "")
            isLoading = false
        }
        .navigationDestination(item: $newDraft) { draft in
            TierListEditorView(
                draft: draft,
                onPublished: { _ in onDismiss() },
                onDismiss: { onDismiss() }
            )
        }
    }

    @ViewBuilder
    private func targetRow(_ list: TierList, badge: String?) -> some View {
        Button {
            Task {
                do {
                    try await TierListsRepository.shared.addItem(item, to: list)
                    ToastManager.shared.show(
                        title: badge == "Черновик" ? "Добавлено в черновик" : "Добавлено в тир-лист",
                        subtitle: list.title,
                        icon: "checkmark.circle.fill",
                        iconColor: Color.slooshAccent,
                        duration: 2.5
                    )
                    onDismiss()
                } catch {
                    ToastManager.shared.show(
                        title: "Не удалось добавить",
                        subtitle: error.localizedDescription,
                        icon: "xmark.octagon.fill",
                        iconColor: .red,
                        duration: 3
                    )
                }
            }
        } label: {
            HStack(spacing: 12) {
                if let first = list.allItems.compactMap(\.posterUrl).first {
                    AsyncCachedImage(
                        url: URL(string: first),
                        placeholder: { Rectangle().fill(Color(UIColor.tertiarySystemFill)) },
                        content: { image in
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        },
                        fallback: { Rectangle().fill(Color(UIColor.tertiarySystemFill)) }
                    )
                    .frame(width: 36, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(width: 36, height: 52)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(list.itemsCount) фильмов")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange, in: Capsule())
                }
            }
        }
    }
}
