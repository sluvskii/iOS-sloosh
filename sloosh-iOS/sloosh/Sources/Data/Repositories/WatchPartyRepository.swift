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
    @Published var activePartyPlayerConfig: PlayerConfig? = nil

    // Callback hooks for PlayerViewModel
    public var onRemotePlay: (() -> Void)?
    public var onRemotePause: (() -> Void)?
    public var onRemoteSeek: ((Double) -> Void)?
    public var onRemoteRateChange: ((Float) -> Void)?
    public var onRemoteEpisodeChange: ((Int, Int) -> Void)?
    public var onRemoteVoiceoverChange: ((String) -> Void)?
    public var onSessionEnded: (() -> Void)?
    public var localPlaybackTimeProvider: (() -> Double)?

    // MARK: - Private State

    private var pollingTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var isApplyingRemoteAction: Bool = false
    private var lastProcessedPlaybackUpdatedAtMs: Int64 = 0
    private var lastHardSeekTime: Date = .distantPast
    private var lastDriftEvaluationTime: Date = .distantPast
    private let databaseBaseURL = "https://sloosh-77434-default-rtdb.firebaseio.com"

    // MARK: - Server Clock Synchronization (NTP compensation)
    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        return formatter
    }()

    public private(set) var serverClockOffsetMs: Int64 = 0

    public func syncServerTime(from response: URLResponse?) {
        guard let httpResp = response as? HTTPURLResponse,
              let dateStr = (httpResp.allHeaderFields["Date"] ?? httpResp.allHeaderFields["date"]) as? String,
              let serverDate = Self.httpDateFormatter.date(from: dateStr) else {
            return
        }
        let serverMs = Int64(serverDate.timeIntervalSince1970 * 1000)
        let localMs = Int64(Date().timeIntervalSince1970 * 1000)
        let offset = serverMs - localMs
        if self.serverClockOffsetMs == 0 {
            self.serverClockOffsetMs = offset
        } else {
            self.serverClockOffsetMs = (self.serverClockOffsetMs * 3 + offset) / 4
        }
    }

    public var calibratedNowMs: Int64 {
        Int64(Date().timeIntervalSince1970 * 1000) + serverClockOffsetMs
    }

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
        let name = AuthRepository.shared.currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty { return name }
        let email = AuthRepository.shared.currentUser?.email?.components(separatedBy: "@").first
        if let email, !email.isEmpty { return email }
        return isHost ? "Хост" : "Друг"
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
        streamSource: String? = nil,
        currentPosition: Double,
        isPlaying: Bool,
        invitee: SlooshUser
    ) async -> WatchPartySession? {
        guard let user = AuthRepository.shared.currentUser else { return nil }

        let partyId = "wp_\(UUID().uuidString.prefix(10).lowercased())"
        let chatId = MessengerRepository.shared.getOrCreateChatId(peerUserId: invitee.id)
        let playback = WatchPartyPlayback(
            isPlaying: isPlaying,
            positionSec: currentPosition,
            updatedAtMs: calibratedNowMs,
            lastActionByUid: user.id,
            lastActionByName: user.displayName ?? "Хост",
            actionType: isPlaying ? .play : .pause,
            actionTargetTime: currentPosition
        )

        let session = WatchPartySession(
            id: partyId,
            chatId: chatId,
            hostUid: user.id,
            hostName: user.displayName ?? "Хост",
            hostAvatarUrl: user.photoURL,
            guestUid: nil,
            guestName: nil,
            guestAvatarUrl: nil,
            mediaId: mediaId,
            mediaType: mediaType,
            title: title,
            posterUrl: posterUrl,
            season: season,
            episode: episode,
            translationId: translationId,
            translationName: translationName,
            streamSource: streamSource,
            playback: playback,
            status: .active
        )

        // 1. Primary storage: chats/{chatId}/watch_party
        // In live Firebase RTDB rules, chats/{chatId} is guaranteed to allow read/write for both users.
        if let chatPartyUrl = URL(string: "\(databaseBaseURL)/chats/\(chatId)/watch_party.json\(authQueryParam)"),
           let encodedData = try? JSONEncoder().encode(session) {
            var req = URLRequest(url: chatPartyUrl)
            req.httpMethod = "PUT"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = encodedData
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    AppDiagnostics.shared.log("WatchPartyRepository: Failed to write to chats/\(chatId)/watch_party: \(http.statusCode)")
                }
            } catch {
                AppDiagnostics.shared.log("WatchPartyRepository: Error writing to chats/\(chatId)/watch_party: \(error)")
            }
        }

        // Mirror to /watch_parties/{partyId} (best-effort background task)
        if let rootUrl = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId).json\(authQueryParam)"),
           let encodedData = try? JSONEncoder().encode(session) {
            Task {
                var req = URLRequest(url: rootUrl)
                req.httpMethod = "PUT"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = encodedData
                _ = try? await URLSession.shared.data(for: req)
            }
        }

        // 2. Send invite into friend's private chat
        _ = await MessengerRepository.shared.sendWatchPartyInvite(toPeerUser: invitee, party: session)

        // 3. Set local state & start listening
        self.activeSession = session
        self.isHost = true
        self.peerUser = invitee
        self.isConnected = true
        self.lastProcessedPlaybackUpdatedAtMs = playback.updatedAtMs

        startObservingSession(chatId: chatId, partyId: partyId)
        showToast("Приглашение отправлено \(invitee.displayTitle)")

        return session
    }

    // MARK: - Join Session (Guest)

    public func joinSession(chatId: String? = nil, partyId: String) async -> WatchPartySession? {
        guard let user = AuthRepository.shared.currentUser else { return nil }

        // Candidate URLs: chats/{chatId}/watch_party first, then fallback to watch_parties/{partyId}
        var candidateUrls: [URL] = []
        if let cid = chatId, !cid.isEmpty,
           let url = URL(string: "\(databaseBaseURL)/chats/\(cid)/watch_party.json\(authQueryParam)") {
            candidateUrls.append(url)
        }
        if let rootUrl = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId).json\(authQueryParam)") {
            candidateUrls.append(rootUrl)
        }

        var fetchedSession: WatchPartySession?
        var activeTargetUrl: URL?

        for url in candidateUrls {
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                if data.isEmpty || String(data: data, encoding: .utf8) == "null" { continue }
                if let decoded = try? JSONDecoder().decode(WatchPartySession.self, from: data) {
                    fetchedSession = decoded
                    activeTargetUrl = url
                    break
                }
            } catch {
                continue
            }
        }

        guard var session = fetchedSession, let targetUrl = activeTargetUrl else {
            showToast("Не удалось подключиться к сессии")
            return nil
        }

        guard session.status == .active else {
            showToast("Совместный просмотр уже завершён")
            return nil
        }

        let resolvedChatId = session.chatId ?? chatId ?? MessengerRepository.shared.getOrCreateChatId(peerUserId: session.hostUid)
        session.chatId = resolvedChatId

        // Update guest info if missing
        if session.guestUid == nil || session.guestUid == user.id {
            session.guestUid = user.id
            session.guestName = user.displayName ?? "Гость"
            session.guestAvatarUrl = user.photoURL

            let patchDict: [String: Any] = [
                "guestUid": user.id,
                "guestName": user.displayName ?? "Гость",
                "guestAvatarUrl": user.photoURL as Any
            ]
            if let patchData = try? JSONSerialization.data(withJSONObject: patchDict) {
                var patchReq = URLRequest(url: targetUrl)
                patchReq.httpMethod = "PATCH"
                patchReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                patchReq.httpBody = patchData
                _ = try? await URLSession.shared.data(for: patchReq)
            }
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
        self.lastProcessedPlaybackUpdatedAtMs = session.playback.updatedAtMs

        startObservingSession(chatId: resolvedChatId, partyId: session.id)
        showToast("Вы подключились к просмотру с \(session.hostName)")

        return session
    }

    /// Fast one-tap join directly from an incoming invite or conversation in chat.
    public func acceptInviteFromChat(partyId: String, chatId: String) {
        incomingInvite = nil
        Task { @MainActor in
            if let joined = await joinSession(chatId: chatId, partyId: partyId) {
                if let config = await WatchPartyPlayerResolver.resolveConfig(for: joined) {
                    self.activePartyPlayerConfig = config
                }
            }
        }
    }

    public func acceptInviteFromChat(chatId: String) async {
        guard let url = URL(string: "\(databaseBaseURL)/chats/\(chatId)/watch_party.json\(authQueryParam)") else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            guard let session = try? JSONDecoder().decode(WatchPartySession.self, from: data), session.status == .active else { return }

            if let joined = await joinSession(chatId: chatId, partyId: session.id) {
                if let config = await WatchPartyPlayerResolver.resolveConfig(for: joined) {
                    self.activePartyPlayerConfig = config
                }
            }
        } catch {
            AppDiagnostics.shared.log("WatchPartyRepository: Failed to accept invite from chat: \(error)")
        }
    }

    // MARK: - Leave Session

    public func leaveSession(reason: WatchPartyActionType = .leave) {
        guard let session = activeSession else { return }
        let partyId = session.id
        let chatId = session.chatId
        let myId = currentUserId
        let myName = currentUserName

        pollingTask?.cancel()
        pollingTask = nil

        Task {
            let patchDict: [String: Any] = [
                "status": WatchPartyStatus.closed.rawValue,
                "updatedAtMs": calibratedNowMs,
                "playback/actionType": reason.rawValue,
                "playback/lastActionByUid": myId,
                "playback/lastActionByName": myName
            ]
            let patchData = try? JSONSerialization.data(withJSONObject: patchDict)

            if let cid = chatId,
               let url = URL(string: "\(databaseBaseURL)/chats/\(cid)/watch_party.json\(authQueryParam)") {
                var req = URLRequest(url: url)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = patchData
                _ = try? await URLSession.shared.data(for: req)
            }

            if let rootUrl = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId).json\(authQueryParam)") {
                var req = URLRequest(url: rootUrl)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = patchData
                _ = try? await URLSession.shared.data(for: req)
            }
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
        let chatId = session.chatId
        let myId = currentUserId
        let myName = currentUserName
        let nowMs = calibratedNowMs

        AppDiagnostics.shared.log("[WatchParty] sendPlaybackAction: action=\(action.rawValue), isPlaying=\(isPlaying), pos=\(positionSec)")

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
        self.lastProcessedPlaybackUpdatedAtMs = nowMs

        Task {
            let playbackData = try? JSONSerialization.data(withJSONObject: playbackDict)

            if let cid = chatId,
               let url = URL(string: "\(databaseBaseURL)/chats/\(cid)/watch_party/playback.json\(authQueryParam)") {
                var req = URLRequest(url: url)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = playbackData
                if let (_, resp) = try? await URLSession.shared.data(for: req) {
                    syncServerTime(from: resp)
                }
            }

            if let rootUrl = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId)/playback.json\(authQueryParam)") {
                var req = URLRequest(url: rootUrl)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = playbackData
                if let (_, resp) = try? await URLSession.shared.data(for: req) {
                    syncServerTime(from: resp)
                }
            }
        }
    }

    // MARK: - Send Episode Change

    public func sendEpisodeChange(season: Int, episode: Int) {
        guard let session = activeSession, isConnected else { return }
        guard !isApplyingRemoteAction else { return }

        let partyId = session.id
        let chatId = session.chatId
        let myId = currentUserId
        let myName = currentUserName
        let nowMs = calibratedNowMs

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
            let patchData = try? JSONSerialization.data(withJSONObject: patchDict)

            if let cid = chatId,
               let url = URL(string: "\(databaseBaseURL)/chats/\(cid)/watch_party.json\(authQueryParam)") {
                var req = URLRequest(url: url)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = patchData
                if let (_, resp) = try? await URLSession.shared.data(for: req) {
                    syncServerTime(from: resp)
                }
            }

            if let rootUrl = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId).json\(authQueryParam)") {
                var req = URLRequest(url: rootUrl)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = patchData
                if let (_, resp) = try? await URLSession.shared.data(for: req) {
                    syncServerTime(from: resp)
                }
            }
        }
    }

    // MARK: - Send Voiceover Change

    public func sendVoiceoverChange(translationName: String) {
        guard let session = activeSession, isConnected else { return }
        guard !isApplyingRemoteAction else { return }

        let partyId = session.id
        let chatId = session.chatId
        let nowMs = calibratedNowMs
        let myId = currentUserId
        let myName = currentUserName

        AppDiagnostics.shared.log("[WatchParty] sendVoiceoverChange: translationName=\(translationName)")
        self.activeSession?.translationName = translationName

        Task {
            let patchDict: [String: Any] = [
                "translationName": translationName,
                "updatedAtMs": nowMs,
                "playback/lastActionByUid": myId,
                "playback/lastActionByName": myName
            ]
            let patchData = try? JSONSerialization.data(withJSONObject: patchDict)

            if let cid = chatId,
               let url = URL(string: "\(databaseBaseURL)/chats/\(cid)/watch_party.json\(authQueryParam)") {
                var req = URLRequest(url: url)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = patchData
                if let (_, resp) = try? await URLSession.shared.data(for: req) {
                    syncServerTime(from: resp)
                }
            }

            if let rootUrl = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId).json\(authQueryParam)") {
                var req = URLRequest(url: rootUrl)
                req.httpMethod = "PATCH"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = patchData
                if let (_, resp) = try? await URLSession.shared.data(for: req) {
                    syncServerTime(from: resp)
                }
            }
        }
    }

    // MARK: - Polling & Real-time Observation

    private func startObservingSession(chatId: String, partyId: String) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollSessionState(chatId: chatId, partyId: partyId)
                // Poll cadence: 1.0 second during active session for smooth clock sync
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func pollSessionState(chatId: String, partyId: String) async {
        // Poll primary chat path first, fallback to watch_parties/{partyId}
        let primaryUrl = URL(string: "\(databaseBaseURL)/chats/\(chatId)/watch_party.json\(authQueryParam)")
        let fallbackUrl = URL(string: "\(databaseBaseURL)/watch_parties/\(partyId).json\(authQueryParam)")

        var fetchedData: Data?
        if let primaryUrl {
            do {
                let (data, resp) = try await URLSession.shared.data(from: primaryUrl)
                syncServerTime(from: resp)
                if let http = resp as? HTTPURLResponse {
                    if http.statusCode == 401 {
                        _ = await AuthRepository.shared.ensureFreshToken(force: true)
                        return
                    }
                    if (200...299).contains(http.statusCode) && !data.isEmpty && String(data: data, encoding: .utf8) != "null" {
                        fetchedData = data
                    }
                }
            } catch {}
        }
        if fetchedData == nil, let fallbackUrl {
            do {
                let (data, resp) = try await URLSession.shared.data(from: fallbackUrl)
                syncServerTime(from: resp)
                if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty && String(data: data, encoding: .utf8) != "null" {
                    fetchedData = data
                }
            } catch {}
        }

        guard let data = fetchedData, let remote = try? JSONDecoder().decode(WatchPartySession.self, from: data) else { return }

        await MainActor.run {
            self.processRemoteSessionUpdate(remote)
        }
    }

    private func processRemoteSessionUpdate(_ remote: WatchPartySession) {
        // 1. Check if session was terminated
        if remote.status == .closed {
            let friendName = peerUser?.displayTitle ?? "Друг"
            showToast("\(friendName) вышел из совместного просмотра")
            AppDiagnostics.shared.log("[WatchParty] Remote session closed by \(friendName)")
            self.activeSession = nil
            self.peerUser = nil
            self.isConnected = false
            pollingTask?.cancel()
            pollingTask = nil
            onSessionEnded?()
            return
        }

        // 2. Notify host when guest connects
        if isHost && activeSession?.guestUid == nil, let gUid = remote.guestUid, !gUid.isEmpty {
            let gName = remote.guestName ?? peerUser?.displayTitle ?? "Друг"
            showToast("\(gName) подключился к просмотру")
            AppDiagnostics.shared.log("[WatchParty] Guest connected: \(gName) (\(gUid))")
            self.activeSession?.guestUid = gUid
            self.activeSession?.guestName = gName
            self.activeSession?.guestAvatarUrl = remote.guestAvatarUrl
        }

        // 3. Ignore actions originated by current user
        let action = remote.playback
        if action.lastActionByUid == currentUserId {
            self.activeSession = remote
            return
        }

        isApplyingRemoteAction = true
        defer { isApplyingRemoteAction = false }

        // 4. Check for episode changes in serials
        if let newSeason = remote.season, let newEpisode = remote.episode {
            if let oldSeason = activeSession?.season, let oldEpisode = activeSession?.episode {
                if newSeason != oldSeason || newEpisode != oldEpisode {
                    activeSession?.season = newSeason
                    activeSession?.episode = newEpisode
                    lastProcessedPlaybackUpdatedAtMs = action.updatedAtMs
                    showToast("\(action.lastActionByName) переключил(а) на \(newEpisode) серию")
                    AppDiagnostics.shared.log("[WatchParty] Remote episode changed to S\(newSeason)E\(newEpisode)")
                    onRemoteEpisodeChange?(newSeason, newEpisode)
                    return
                }
            }
        }

        // 5. Check for voiceover changes
        if let newVoice = remote.translationName, !newVoice.isEmpty {
            let oldVoice = activeSession?.translationName
            if let oldVoice, oldVoice != newVoice {
                activeSession?.translationName = newVoice
                showToast("Озвучка изменена на: \(newVoice)")
                AppDiagnostics.shared.log("[WatchParty] Remote voiceover changed to \(newVoice)")
                onRemoteVoiceoverChange?(newVoice)
            } else if oldVoice == nil {
                activeSession?.translationName = newVoice
            }
        }

        // 6. Check if this playback action was ALREADY processed!
        // Prevents endless re-triggering of seek/play on every 1-second polling tick.
        guard action.updatedAtMs > lastProcessedPlaybackUpdatedAtMs else {
            self.activeSession = remote
            return
        }
        lastProcessedPlaybackUpdatedAtMs = action.updatedAtMs

        // 7. Handle Play / Pause / Seek events with buffer protection
        let nowMs = calibratedNowMs
        let targetPos = action.targetPosition(at: nowMs)
        let localTime = localPlaybackTimeProvider?() ?? 0

        AppDiagnostics.shared.log("[WatchParty] processRemoteAction: type=\(action.actionType.rawValue), isPlaying=\(action.isPlaying), remotePos=\(action.positionSec), targetPos=\(targetPos), localTime=\(localTime)")

        if action.actionType == .pause && action.isPlaying == false {
            showToast("\(action.lastActionByName) поставил(а) на паузу")
            onRemotePause?()
            // Always align to the exact paused frame if difference is noticeable (> 0.25s)
            if abs(localTime - action.positionSec) > 0.25 {
                AppDiagnostics.shared.log("[WatchParty] Aligning pause position from \(localTime) to \(action.positionSec)")
                onRemoteSeek?(action.positionSec)
            }
        } else if action.actionType == .play && action.isPlaying == true {
            showToast("\(action.lastActionByName) возобновил(а) просмотр")
            // Align play position if difference is significant (> 2.0s)
            if abs(localTime - targetPos) >= 2.0 {
                AppDiagnostics.shared.log("[WatchParty] Seeking on play from \(localTime) to \(targetPos)")
                onRemoteSeek?(targetPos)
            }
            onRemotePlay?()
        } else if action.actionType == .seek {
            let timeStr = formatSecondsToTime(targetPos)
            showToast("\(action.lastActionByName) перемотал(а) на \(timeStr)")
            // Explicit seek: jump to target and match play/pause state
            onRemoteSeek?(targetPos)
            if action.isPlaying {
                onRemotePlay?()
            } else {
                onRemotePause?()
            }
        }

        self.activeSession = remote
    }

    /// Evaluates clock drift and returns recommended playback rate or seek target.
    /// Safely throttled to avoid endless seek loops while buffering.
    public func evaluateDrift(
        localCurrentTime: Double,
        duration: Double = 0,
        localIsPlaying: Bool,
        isBuffering: Bool = false,
        isUserSeeking: Bool = false
    ) {
        guard let session = activeSession, isConnected else { return }
        guard !isApplyingRemoteAction else { return }
        guard !isBuffering && !isUserSeeking else { return }

        // Throttle drift checks to at most once every 1.5 seconds for snappy sync
        let now = Date()
        guard now.timeIntervalSince(lastDriftEvaluationTime) >= 1.5 else { return }
        lastDriftEvaluationTime = now

        let playback = session.playback

        // If remote is paused, ensure local is paused
        if !playback.isPlaying && localIsPlaying {
            onRemotePause?()
            return
        }

        // Only calibrate drift when BOTH are actively playing
        guard playback.isPlaying && localIsPlaying else {
            return
        }

        let nowMs = calibratedNowMs
        var targetPos = playback.targetPosition(at: nowMs)

        // Clamp target position to duration if known to avoid seeking past end of video
        if duration > 10.0 {
            if targetPos >= duration - 2.0 {
                return
            }
            targetPos = min(targetPos, duration - 2.0)
        }

        let drift = localCurrentTime - targetPos // positive = local ahead, negative = local behind
        let absDrift = abs(drift)

        if absDrift > 5.0 {
            // Massive drift (> 5 seconds): hard seek only with 10-second cooldown to avoid buffer thrashing
            if now.timeIntervalSince(lastHardSeekTime) >= 10.0 {
                lastHardSeekTime = now
                AppDiagnostics.shared.log("[WatchParty] Hard drift detected (\(drift)s), seeking to \(targetPos)s")
                isApplyingRemoteAction = true
                onRemoteSeek?(targetPos)
                onRemoteRateChange?(1.0)
                isApplyingRemoteAction = false
            }
        } else if absDrift > 0.15 {
            // Multi-tier proportional adaptive rate slew:
            // 0.15s - 0.6s:  1.025x / 0.975x (subtle, inaudible)
            // 0.6s  - 1.5s:  1.05x  / 0.95x  (fast sync: closes 1s in ~20s)
            // 1.5s  - 3.0s:  1.08x  / 0.92x  (rapid sync: closes 2s in ~25s)
            // 3.0s  - 5.0s:  1.12x  / 0.88x  (aggressive sync)
            let factor: Float
            if absDrift > 3.0 {
                factor = 0.12
            } else if absDrift > 1.5 {
                factor = 0.08
            } else if absDrift > 0.6 {
                factor = 0.05
            } else {
                factor = 0.025
            }
            let targetRate: Float = drift < 0 ? (1.0 + factor) : (1.0 - factor)
            onRemoteRateChange?(targetRate)
        } else {
            // In sync (<= 0.15s, within ~4 video frames): keep standard 1.0x
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
