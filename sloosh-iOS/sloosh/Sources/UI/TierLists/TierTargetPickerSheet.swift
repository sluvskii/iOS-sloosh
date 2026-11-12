import SwiftUI

/// Компактный выбор целевого тир-листа для контекстного действия
/// «В тир-лист» на карточке фильма: мои черновики + опубликованные + новый.
struct TierTargetPickerSheet: View {
    let item: TierListItem
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [TierList] = []
    @State private var mine: [TierList] = []
    @State private var isLoading = true
    @State private var showEditor = false
    @State private var newDraft: TierList?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                itemPreview
                targetList
                Spacer(minLength: 20)
            }
            .navigationTitle("В тир-лист")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { onDismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        var seeded = TierListsRepository.shared.makeDraft(title: "Новый тир-лист")
                        seeded.unranked.append(item)
                        newDraft = seeded
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
    private var itemPreview: some View {
        HStack(spacing: 10) {
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
            .frame(width: 46, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("Добавится в «Не распределено» — расставите в редакторе")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var targetList: some View {
        if isLoading {
            ProgressView().tint(Color.slooshAccent).frame(maxWidth: .infinity, minHeight: 120)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    if drafts.isEmpty && mine.isEmpty {
                        Text("У вас пока нет тир-листов — создайте первый кнопкой «+»")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    ForEach(drafts) { draft in
                        targetRow(draft, badge: "Черновик")
                    }
                    ForEach(mine) { list in
                        targetRow(list, badge: nil)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
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
            HStack(spacing: 10) {
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
                    .frame(width: 38, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(UIColor.tertiarySystemFill))
                        .frame(width: 38, height: 54)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(list.itemsCount) фильмов")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange, in: Capsule())
                }
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.slooshAccent)
            }
            .padding(10)
            .background(Color(UIColor.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
