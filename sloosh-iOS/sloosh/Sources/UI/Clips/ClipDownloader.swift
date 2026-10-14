import Foundation
import AVFoundation
import Photos
import UIKit

/// Фоновый менеджер для скачивания и нарезки фрагментов моментов (MovieClip) в чистый MP4
@MainActor
public final class ClipDownloader: ObservableObject {
    public static let shared = ClipDownloader()

    @Published public var isDownloading: Bool = false
    @Published public var currentClipId: String? = nil

    private init() {}

    public func download(clip: MovieClip) {
        guard !isDownloading else {
            ToastManager.shared.show(
                title: "Загрузка уже выполняется",
                icon: "arrow.down.circle.fill",
                iconColor: .white
            )
            return
        }

        isDownloading = true
        currentClipId = clip.id
        ToastManager.shared.show(
            title: "Скачивание момента...",
            subtitle: clip.title,
            icon: "arrow.down.circle",
            iconColor: .white,
            duration: 6.0
        )
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                guard let playbackInfo = await ClipStreamResolver.shared.resolveClip(for: clip) else {
                    throw NSError(domain: "sloosh.clip", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось получить видеопоток"])
                }

                let asset = AVURLAsset(url: playbackInfo.url, options: ["AVURLAssetHTTPHeaderFieldsKey": playbackInfo.headers])
                let durationSec = max(1.0, clip.endTime - clip.startTime)
                let startCM = CMTime(seconds: clip.startTime, preferredTimescale: 600)
                let durCM = CMTime(seconds: durationSec, preferredTimescale: 600)
                let timeRange = CMTimeRange(start: startCM, duration: durCM)

                let fm = FileManager.default
                let cleanTitle = clip.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
                let fileName = "sloosh_\(cleanTitle)_\(clip.id).mp4"
                let outputUrl = fm.temporaryDirectory.appendingPathComponent(fileName)
                try? fm.removeItem(at: outputUrl)

                let presets = [
                    AVAssetExportPresetPassthrough,
                    AVAssetExportPresetHighestQuality,
                    AVAssetExportPreset1920x1080,
                    AVAssetExportPreset1280x720
                ]

                var exportSuccess = false
                for preset in presets {
                    if let session = AVAssetExportSession(asset: asset, presetName: preset) {
                        session.outputURL = outputUrl
                        session.outputFileType = .mp4
                        session.shouldOptimizeForNetworkUse = true
                        session.timeRange = timeRange
                        await session.export()

                        let size = ((try? fm.attributesOfItem(atPath: outputUrl.path))?[.size] as? Int64) ?? 0
                        if session.status == .completed && fm.fileExists(atPath: outputUrl.path) && size > 5000 {
                            exportSuccess = true
                            break
                        }
                    }
                    try? fm.removeItem(at: outputUrl)
                }

                guard exportSuccess else {
                    throw NSError(domain: "sloosh.clip", code: -2, userInfo: [NSLocalizedDescriptionKey: "Не удалось экспортировать фрагмент"])
                }

                // Сохранение в Фотоплёнку
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                if status == .authorized || status == .limited {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputUrl)
                    }
                    ToastManager.shared.show(
                        title: "Момент сохранён в «Фото»",
                        subtitle: clip.title,
                        icon: "checkmark.circle.fill",
                        iconColor: .green
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } else {
                    // Если нет доступа к галерее, открываем стандартный системный диалог для сохранения в Файлы
                    presentShareSheet(for: outputUrl)
                    ToastManager.shared.show(
                        title: "Момент готов",
                        subtitle: "Выберите «Сохранить в Файлы»",
                        icon: "square.and.arrow.up",
                        iconColor: .white
                    )
                }
            } catch {
                AppDiagnostics.shared.log("[ClipDownloader] Error: \(error.localizedDescription)")
                ToastManager.shared.show(
                    title: "Не удалось скачать момент",
                    subtitle: error.localizedDescription,
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .orange
                )
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }

            self.isDownloading = false
            self.currentClipId = nil
        }
    }

    private func presentShareSheet(for url: URL) {
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(av, animated: true)
        }
    }
}
