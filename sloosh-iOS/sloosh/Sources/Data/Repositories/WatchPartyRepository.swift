import Foundation
import SwiftUI
import Combine
import AVFoundation

@MainActor
public final class WatchPartyRepository: ObservableObject {
    public static let shared = WatchPartyRepository()

    // MARK: - Published Properties

    @Published public private(set) var activeSession: WatchPartySession? = nil
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var peerUser: SlooshUser? = nil
    @Published public private(set) var isHost: Bool = false
    @Published public private(set) var lastStatusToast: String? = nil
    @Published public var incomingInvite: WatchPartyInvitePayload? = nil

    // Callback hooks for PlayerViewModel
    public var onRemotePlay: (() -> Void)?
    public var onRemotePause: (() -> Void)?
    public var onRemoteSeek: ((Double) -> Void)?
    public var onRemoteRateChange: ((Float) -> Void)?
    public var onRemoteEpisodeChange: ((Int, Int) -> Void)?
    public var onSessionEnded: (() -> Void)?

    // MARK: - Private State

    private var pollingTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var isApplyingRemoteAction: Bool = false
    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com"

    private init() {}

    // MARK: - Helpers

    private var authQueryParam: String {
        guard let token = AuthRepository.shared.currentUser?.idToken, !token.isEmpty else {
            return ""
        }
        return "?auth=\(token)"
    }

    private var currentUserId: String {
        AuthRepository.shared.currentUser?.id ?? "anonymous"
    }

    private var currentUserName: String {
        AuthRepository.shared.currentUser?.displayName ?? "Гость"
    }

    // MARK: - Toast Banner

    public func showToast(_ text: String) {
        toastDismissTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            self.lastStatusToast = text
        }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.lastStatusToast = nil
                }
            }
        }
    }

    // MARK: - Create Session (Host)

    public func createSession(
        mediaId: String,
        mediaType: String,
        title: String,
        posterUrl: String?,
        season: Int?,
        episode: Int?,
        translationId: Int?,
        translationName: String?,
        currentPosition: Double,
        isPlaying: Bool,
        invitee: SlooshUser
    ) async -> WatchPartySession? {
        guard let user = AuthRepository.shared.currentUser else { return nil }

        let partyId = "wp_\(UUID().uuidString.prefix(10).lowercased())"
        let playback = WatchPartyPlayback(
            isPlaying: isPlaying,
            positionSec: currentPosition,
            updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            lastActionByUid: user.id,
            lastActionByName: user.displayName ?? "Хост",
            actionType: isPlaying ? .play : .pause,
            actionTargetTime: currentPosition
        )

        let session = WatchPartySession(
            id: partyId,
            hostUid: user.id,
            hostName: user.displayName ?? "Хост",
            hostAvatarUrl: user.photoURL,
            guestUid: invitee.id,
            guestName: invitee.displayTitle,
            guestAvatarUrl: invitee.avatarUrl,
            mediaId: mediaId,
            mediaType: mediaType,
            title: title,
            posterUrl: posterUrl,
            season: season,
            episode: episode,
            translationId: translationId,
            translationName: translationName,
            playback: playback,
            status: .active
        )

        // 1. Upload to Firebase RTDB
        guard let url = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId).json\(authQueryParam)") else {
            return nil
        }

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            req.httpBody = try JSONEncoder().encode(session)
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
        } catch {
            AppDiagnostics.shared.log("WatchPartyRepository: Failed to create session: \(error)")
            return nil
        }

        // 2. Send invite into friend's private chat
        _ = await MessengerRepository.shared.sendWatchPartyInvite(toPeerUser: invitee, party: session)

        // 3. Set local state & start listening
        self.activeSession = session
        self.isHost = true
        self.peerUser = invitee
        self.isConnected = true

        startObservingSession(partyId: partyId)
        showToast("Приглашение отправлено \(invitee.displayTitle)")

        return session
    }

    // MARK: - Join Session (Guest)

    public func joinSession(partyId: String) async -> WatchPartySession? {
        guard let user = AuthRepository.shared.currentUser else { return nil }
        guard let url = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId).json\(authQueryParam)") else {
            return nil
        }

        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

            var session = try JSONDecoder().decode(WatchPartySession.self, from: data)
            guard session.status == .active else {
                showToast("Совместный просмотр уже завершён")
                return nil
            }

            // Update guest info if missing
            if session.guestUid == nil || session.guestUid == user.id {
                session.guestUid = user.id
                session.guestName = user.displayName ?? "Гость"
                session.guestAvatarUrl = user.photoURL
                
                var patchReq = URLRequest(url: url)
                patchReq.httpMethod = "PATCH"
                patchReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let patchDict: [String: Any] = [
                    "guestUid": user.id,
                    "guestName": user.displayName ?? "Гость",
                    "guestAvatarUrl": user.photoURL as Any
                ]
                patchReq.httpBody = try? JSONSerialization.data(withJSONObject: patchDict)
                _ = try? await URLSession.shared.data(for: patchReq)
            }

            // Host becomes peer for guest
            let hostPeer = SlooshUser(
                id: session.hostUid,
                displayName: session.hostName,
                tag: nil,
                avatarUrl: session.hostAvatarUrl
            )

            self.activeSession = session
            self.isHost = false
            self.peerUser = hostPeer
            self.isConnected = true

            startObservingSession(partyId: partyId)
            showToast("Вы подключились к просмотру с \(session.hostName)")

            return session
        } catch {
            AppDiagnostics.shared.log("WatchPartyRepository: Failed to join session: \(error)")
            return nil
        }
    }

    // MARK: - Leave Session

    public func leaveSession(reason: WatchPartyActionType = .leave) {
        guard let session = activeSession else { return }
        let partyId = session.id
        let myId = currentUserId
        let myName = currentUserName

        pollingTask?.cancel()
        pollingTask = nil

        Task {
            guard let url = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId).json\(authQueryParam)") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Mark session as closed so old invite cards in chat cannot be reused
            let patchDict: [String: Any] = [
                "status": WatchPartyStatus.closed.rawValue,
                "updatedAtMs": Int64(Date().timeIntervalSince1970 * 1000),
                "playback/actionType": reason.rawValue,
                "playback/lastActionByUid": myId,
                "playback/lastActionByName": myName
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: patchDict)
            _ = try? await URLSession.shared.data(for: req)
        }

        self.activeSession = nil
        self.peerUser = nil
        self.isHost = false
        self.isConnected = false
        onSessionEnded?()
    }

    // MARK: - Send Playback Action

    public func sendPlaybackAction(
        isPlaying: Bool,
        positionSec: Double,
        action: WatchPartyActionType,
        targetTime: Double? = nil
    ) {
        guard let session = activeSession, isConnected else { return }
        guard !isApplyingRemoteAction else { return }

        let partyId = session.id
        let myId = currentUserId
        let myName = currentUserName
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        let playbackDict: [String: Any] = [
            "isPlaying": isPlaying,
            "positionSec": positionSec,
            "updatedAtMs": nowMs,
            "lastActionByUid": myId,
            "lastActionByName": myName,
            "actionType": action.rawValue,
            "actionTargetTime": targetTime ?? positionSec
        ]

        // Optimistically update local activeSession model
        self.activeSession?.playback = WatchPartyPlayback(
            isPlaying: isPlaying,
            positionSec: positionSec,
            updatedAtMs: nowMs,
            lastActionByUid: myId,
            lastActionByName: myName,
            actionType: action,
            actionTargetTime: targetTime ?? positionSec
        )

        Task {
            guard let url = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId)/playback.json\(authQueryParam)") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: playbackDict)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    // MARK: - Send Episode Change

    public func sendEpisodeChange(season: Int, episode: Int) {
        guard let session = activeSession, isConnected else { return }
        guard !isApplyingRemoteAction else { return }

        let partyId = session.id
        let myId = currentUserId
        let myName = currentUserName
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        let patchDict: [String: Any] = [
            "season": season,
            "episode": episode,
            "updatedAtMs": nowMs,
            "playback/isPlaying": true,
            "playback/positionSec": 0.0,
            "playback/updatedAtMs": nowMs,
            "playback/lastActionByUid": myId,
            "playback/lastActionByName": myName,
            "playback/actionType": WatchPartyActionType.changeEpisode.rawValue,
            "playback/actionTargetTime": 0.0
        ]

        self.activeSession?.season = season
        self.activeSession?.episode = episode

        Task {
            guard let url = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId).json\(authQueryParam)") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: patchDict)
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    // MARK: - Polling & Real-time Observation

    private func startObservingSession(partyId: String) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollSessionState(partyId: partyId)
                // Poll cadence: 1.0 second during active session for smooth clock sync
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func pollSessionState(partyId: String) async {
        guard let url = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId).json\(authQueryParam)") else { return }

        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            guard let remote = try? JSONDecoder().decode(WatchPartySession.self, from: data) else { return }

            await MainActor.run {
                self.processRemoteSessionUpdate(remote)
            }
        } catch {
            // Transient network error
        }
    }

    private func processRemoteSessionUpdate(_ remote: WatchPartySession) {
        // 1. Check if session was terminated
        if remote.status == .closed {
            let friendName = peerUser?.displayTitle ?? "Друг"
            showToast("\(friendName) вышел из совместного просмотра")
            self.activeSession = nil
            self.peerUser = nil
            self.isConnected = false
            pollingTask?.cancel()
            pollingTask = nil
            onSessionEnded?()
            return
        }

        // 2. Ignore actions originated by current user
        let action = remote.playback
        if action.lastActionByUid == currentUserId {
            return
        }

        isApplyingRemoteAction = true
        defer { isApplyingRemoteAction = false }

        // 3. Check for episode changes in serials
        if let newSeason = remote.season, let newEpisode = remote.episode {
            if let oldSeason = activeSession?.season, let oldEpisode = activeSession?.episode {
                if newSeason != oldSeason || newEpisode != oldEpisode {
                    activeSession?.season = newSeason
                    activeSession?.episode = newEpisode
                    showToast("\(action.lastActionByName) переключил(а) на \(newEpisode) серию")
                    onRemoteEpisodeChange?(newSeason, newEpisode)
                    return
                }
            }
        }

        // 4. Handle Play / Pause / Seek events
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let targetPos = action.targetPosition(at: nowMs)

        if action.actionType == .pause && action.isPlaying == false {
            showToast("\(action.lastActionByName) поставил(а) на паузу")
            onRemotePause?()
            onRemoteSeek?(action.positionSec)
        } else if action.actionType == .play && action.isPlaying == true {
            showToast("\(action.lastActionByName) возобновил(а) просмотр")
            onRemoteSeek?(targetPos)
            onRemotePlay?()
        } else if action.actionType == .seek {
            let timeStr = formatSecondsToTime(targetPos)
            showToast("\(action.lastActionByName) перемотал(а) на \(timeStr)")
            onRemoteSeek?(targetPos)
        }

        self.activeSession = remote
    }

    /// Evaluates clock drift and returns recommended playback rate or seek target.
    public func evaluateDrift(localCurrentTime: Double, localIsPlaying: Bool) {
        guard let session = activeSession, isConnected else { return }
        guard !isApplyingRemoteAction else { return }
        let playback = session.playback

        // If remote is paused, ensure local is paused
        if !playback.isPlaying && localIsPlaying {
            onRemotePause?()
            return
        }

        guard playback.isPlaying && localIsPlaying else { return }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let targetPos = playback.targetPosition(at: nowMs)
        let drift = localCurrentTime - targetPos // positive = local ahead, negative = local behind

        if abs(drift) > 2.0 {
            // Hard drift: soft seek to catch up
            isApplyingRemoteAction = true
            onRemoteSeek?(targetPos)
            onRemoteRateChange?(1.0)
            isApplyingRemoteAction = false
        } else if abs(drift) > 0.35 {
            // Soft drift: micro-adjust playback rate to silently align audio/video buffers
            let targetRate: Float = drift < 0 ? 1.04 : 0.96
            onRemoteRateChange?(targetRate)
        } else {
            // Perfectly in sync: ensure rate is standard 1.0x
            onRemoteRateChange?(1.0)
        }
    }

    private func formatSecondsToTime(_ totalSec: Double) -> String {
        let sec = Int(max(0, totalSec))
        let h = sec / 3600
        let m = (sec % 3600) / 60
        let s = sec % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
