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
    @Published public private(set) var isJoiningParty: Bool = false
    @Published public private(set) var lastStatusToast: String? = nil
    @Published public var incomingInvite: WatchPartyInvitePayload? = nil
    @Published var activePartyPlayerConfig: PlayerConfig? = nil

    // Callback hooks for PlayerViewModel
    public var onRemotePlay: (() -> Void)?
    public var onRemotePause: (() -> Void)?
    public var onRemoteSeek: ((Double) -> Void)?
    public var onRemoteRateChange: ((Float) -> Void)?
    public var onRemoteSpeedChange: ((Float) -> Void)?
    public var onRemoteEpisodeChange: ((Int, Int) -> Void)?
    public var onRemoteVoiceoverChange: ((String) -> Void)?
    public var onSessionEnded: (() -> Void)?
    public var localPlaybackTimeProvider: (() -> Double)?

    // MARK: - Private State

    private var realtimeStreamTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var isApplyingRemoteAction: Bool = false
    private var lastProcessedPlaybackUpdatedAtMs: Int64 = 0
    private var lastHardSeekTime: Date = .distantPast
    private var lastDriftEvaluationTime: Date = .distantPast
    private var smoothedDrift: Double = 0.0
    private var lastRateChangeTime: Date = .distantPast
    private var currentAppliedRate: Float = 1.0
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
        // Coarse correction: HTTP Date header has only 1-second resolution (no milliseconds).
        // Modern iOS devices are NTP-synchronized via Apple servers (< 15ms accuracy).
        // Only apply coarse correction if device clock is wildly off (> 2.0s) due to manual user clock settings.
        // Truncating milliseconds when device is already accurate would destroy sub-frame sync.
        if abs(offset) > 2000 {
            if self.serverClockOffsetMs == 0 {
                self.serverClockOffsetMs = offset
            } else {
                self.serverClockOffsetMs = (self.serverClockOffsetMs * 3 + offset) / 4
            }
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
        self.smoothedDrift = 0.0
        self.currentAppliedRate = 1.0
        self.lastDriftEvaluationTime = .distantPast
        self.lastRateChangeTime = .distantPast

        startObservingSession(chatId: resolvedChatId, partyId: session.id)
        showToast("Вы подключились к просмотру с \(session.hostName)")

        return session
    }

    /// Fast one-tap join directly from an incoming invite or conversation in chat.
    public func acceptInviteFromChat(partyId: String, chatId: String) {
        guard !isJoiningParty else { return }
        incomingInvite = nil
        isJoiningParty = true
        Task { @MainActor in
            defer { self.isJoiningParty = false }
            if let joined = await joinSession(chatId: chatId, partyId: partyId) {
                if let config = await WatchPartyPlayerResolver.resolveConfig(for: joined) {
                    self.activePartyPlayerConfig = config
                }
            }
        }
    }

    public func acceptInviteFromChat(chatId: String) async {
        guard !isJoiningParty else { return }
        await MainActor.run {
            self.isJoiningParty = true
        }
        defer {
            Task { @MainActor in
                self.isJoiningParty = false
            }
        }
        guard let url = URL(string: "\(databaseBaseURL)/chats/\(chatId)/watch_party.json\(authQueryParam)") else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            guard let session = try? JSONDecoder().decode(WatchPartySession.self, from: data), session.status == .active else { return }

            if let joined = await joinSession(chatId: chatId, partyId: session.id) {
                if let config = await WatchPartyPlayerResolver.resolveConfig(for: joined) {
                    await MainActor.run {
                        self.activePartyPlayerConfig = config
                    }
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

        realtimeStreamTask?.cancel()
        realtimeStreamTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        smoothedDrift = 0.0
        currentAppliedRate = 1.0

        Task {
            let patchDict: [String: Any] = [
                "status": WatchPartyStatus.closed.rawValue,
                "updatedAtMs": calibratedNowMs,
                "playback": [
                    "actionType": reason.rawValue,
                    "lastActionByUid": myId,
                    "lastActionByName": myName
                ]
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
        targetTime: Double? = nil,
        scheduledStartMs: Int64? = nil
    ) {
        guard let session = activeSession, isConnected else { return }
        guard !isApplyingRemoteAction else { return }

        let partyId = session.id
        let chatId = session.chatId
        let myId = currentUserId
        let myName = currentUserName
        let nowMs = calibratedNowMs

        let effectiveStartMs: Int64? = {
            if isPlaying && (action == .play || action == .seek) {
                return scheduledStartMs ?? (nowMs + 250)
            }
            return nil
        }()

        AppDiagnostics.shared.log("[WatchParty] sendPlaybackAction: action=\(action.rawValue), isPlaying=\(isPlaying), pos=\(positionSec), scheduledStartMs=\(String(describing: effectiveStartMs))")

        let activeSpeed = session.playback.speed > 0 ? session.playback.speed : 1.0

        var playbackDict: [String: Any] = [
            "isPlaying": isPlaying,
            "positionSec": positionSec,
            "updatedAtMs": effectiveStartMs ?? nowMs,
            "lastActionByUid": myId,
            "lastActionByName": myName,
            "actionType": action.rawValue,
            "actionTargetTime": targetTime ?? positionSec,
            "speed": activeSpeed
        ]
        if let effectiveStartMs {
            playbackDict["scheduledStartMs"] = effectiveStartMs
        }

        // Optimistically update local activeSession model
        self.activeSession?.playback = WatchPartyPlayback(
            isPlaying: isPlaying,
            positionSec: positionSec,
            updatedAtMs: effectiveStartMs ?? nowMs,
            lastActionByUid: myId,
            lastActionByName: myName,
            actionType: action,
            actionTargetTime: targetTime ?? positionSec,
            scheduledStartMs: effectiveStartMs,
            speed: activeSpeed
        )
        self.lastProcessedPlaybackUpdatedAtMs = effectiveStartMs ?? nowMs

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

    // MARK: - Send Speed Change

    public func sendSpeedChange(speed: Float) {
        guard let session = activeSession, isConnected else { return }
        guard !isApplyingRemoteAction else { return }

        let partyId = session.id
        let chatId = session.chatId
        let myId = currentUserId
        let myName = currentUserName
        let nowMs = calibratedNowMs
        let currentPos = localPlaybackTimeProvider?() ?? session.playback.positionSec

        AppDiagnostics.shared.log("[WatchParty] sendSpeedChange: speed=\(speed)x, pos=\(currentPos)")

        var newPlayback = session.playback
        newPlayback.speed = speed
        newPlayback.positionSec = currentPos
        newPlayback.updatedAtMs = nowMs
        newPlayback.lastActionByUid = myId
        newPlayback.lastActionByName = myName
        newPlayback.actionType = .changeSpeed
        newPlayback.actionTargetTime = currentPos

        self.activeSession?.playback = newPlayback
        self.lastProcessedPlaybackUpdatedAtMs = nowMs
        self.currentAppliedRate = speed

        let playbackDict: [String: Any] = [
            "isPlaying": newPlayback.isPlaying,
            "positionSec": currentPos,
            "updatedAtMs": nowMs,
            "lastActionByUid": myId,
            "lastActionByName": myName,
            "actionType": WatchPartyActionType.changeSpeed.rawValue,
            "actionTargetTime": currentPos,
            "speed": speed
        ]

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
        let currentSpeed = session.playback.speed > 0 ? session.playback.speed : 1.0

        AppDiagnostics.shared.log("[WatchParty] sendEpisodeChange: S\(season)E\(episode)")

        let playbackDict: [String: Any] = [
            "isPlaying": true,
            "positionSec": 0.0,
            "updatedAtMs": nowMs,
            "lastActionByUid": myId,
            "lastActionByName": myName,
            "actionType": WatchPartyActionType.changeEpisode.rawValue,
            "actionTargetTime": 0.0,
            "speed": currentSpeed
        ]

        let patchDict: [String: Any] = [
            "season": season,
            "episode": episode,
            "updatedAtMs": nowMs,
            "playback": playbackDict
        ]

        self.activeSession?.season = season
        self.activeSession?.episode = episode
        self.activeSession?.playback = WatchPartyPlayback(
            isPlaying: true,
            positionSec: 0.0,
            updatedAtMs: nowMs,
            lastActionByUid: myId,
            lastActionByName: myName,
            actionType: .changeEpisode,
            actionTargetTime: 0.0,
            speed: currentSpeed
        )
        self.lastProcessedPlaybackUpdatedAtMs = nowMs
        self.smoothedDrift = 0.0

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
            let playbackDict: [String: Any] = [
                "isPlaying": session.playback.isPlaying,
                "positionSec": session.playback.positionSec,
                "updatedAtMs": nowMs,
                "lastActionByUid": myId,
                "lastActionByName": myName,
                "actionType": session.playback.actionType.rawValue,
                "actionTargetTime": session.playback.actionTargetTime ?? session.playback.positionSec,
                "speed": session.playback.speed
            ]
            let patchDict: [String: Any] = [
                "translationName": translationName,
                "updatedAtMs": nowMs,
                "playback": playbackDict
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
        realtimeStreamTask?.cancel()
        pollingTask?.cancel()

        // 1. High-speed Real-Time SSE Stream (Sub-50ms latency)
        realtimeStreamTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let urlString = "\(self.databaseBaseURL)/chats/\(chatId)/watch_party.json\(self.authQueryParam)"
                guard let streamUrl = URL(string: urlString) else { break }

                var req = URLRequest(url: streamUrl)
                req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                req.timeoutInterval = 300

                do {
                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: req)
                    self.syncServerTime(from: response)

                    var currentEvent = ""
                    for try await line in asyncBytes.lines {
                        if Task.isCancelled { break }
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix("event: ") {
                            currentEvent = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                        } else if trimmed.hasPrefix("data: ") {
                            let dataStr = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            if currentEvent == "put" || currentEvent == "patch" {
                                await self.handleStreamPayload(dataStr, chatId: chatId, partyId: partyId)
                            }
                        }
                    }
                } catch {
                    // SSE connection reset or network switch
                }

                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }

        // 2. Fallback polling loop (every 3.0s) for redundancy and server clock calibration
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollSessionState(chatId: chatId, partyId: partyId)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func handleStreamPayload(_ jsonString: String, chatId: String, partyId: String) async {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json["path"] as? String else {
            return
        }

        let rawData = json["data"]

        if path == "/" {
            if let dict = rawData as? [String: Any],
               let encoded = try? JSONSerialization.data(withJSONObject: dict),
               let remote = try? JSONDecoder().decode(WatchPartySession.self, from: encoded) {
                await MainActor.run {
                    self.processRemoteSessionUpdate(remote)
                }
            } else if rawData is NSNull {
                await MainActor.run {
                    self.leaveSession()
                }
            }
        } else if path == "/playback" || path.hasPrefix("/playback") {
            if let dict = rawData as? [String: Any],
               let encoded = try? JSONSerialization.data(withJSONObject: dict),
               let playback = try? JSONDecoder().decode(WatchPartyPlayback.self, from: encoded) {
                await MainActor.run {
                    if var current = self.activeSession {
                        current.playback = playback
                        self.processRemoteSessionUpdate(current)
                    }
                }
            } else {
                await self.pollSessionState(chatId: chatId, partyId: partyId)
            }
        } else {
            await self.pollSessionState(chatId: chatId, partyId: partyId)
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
            let seasonChanged = (activeSession?.season == nil || newSeason != activeSession?.season)
            let episodeChanged = (activeSession?.episode == nil || newEpisode != activeSession?.episode)
            if seasonChanged || episodeChanged {
                activeSession?.season = newSeason
                activeSession?.episode = newEpisode
                lastProcessedPlaybackUpdatedAtMs = action.updatedAtMs
                showToast("\(action.lastActionByName) переключил(а) на \(newEpisode) серию")
                AppDiagnostics.shared.log("[WatchParty] Remote episode changed to S\(newSeason)E\(newEpisode)")
                onRemoteEpisodeChange?(newSeason, newEpisode)
                return
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

        // 5b. Check for playback speed changes
        let remoteSpeed = action.speed > 0 ? action.speed : 1.0
        let currentSpeed = activeSession?.playback.speed ?? 1.0
        if action.actionType == .changeSpeed || abs(remoteSpeed - currentSpeed) > 0.01 {
            activeSession?.playback.speed = remoteSpeed
            currentAppliedRate = remoteSpeed
            let speedText = (remoteSpeed == floor(remoteSpeed)) ? String(format: "%.1fx", remoteSpeed) : String(format: "%.2gx", remoteSpeed)
            showToast("\(action.lastActionByName) установил(а) скорость: \(speedText)")
            AppDiagnostics.shared.log("[WatchParty] Remote speed changed to \(remoteSpeed)x")
            onRemoteSpeedChange?(remoteSpeed)
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
            // Always align to the exact paused frame if difference is noticeable (> 0.05s)
            if abs(localTime - action.positionSec) > 0.05 {
                AppDiagnostics.shared.log("[WatchParty] Aligning pause position from \(localTime) to \(action.positionSec)")
                onRemoteSeek?(action.positionSec)
            }
        } else if action.actionType == .play && action.isPlaying == true {
            showToast("\(action.lastActionByName) возобновил(а) просмотр")
            // Align play position if difference is noticeable (> 0.08s)
            if abs(localTime - targetPos) > 0.08 {
                AppDiagnostics.shared.log("[WatchParty] Aligning play position from \(localTime) to \(targetPos)")
                onRemoteSeek?(targetPos)
            }
            if let scheduledStart = action.scheduledStartMs {
                let delayMs = max(0, scheduledStart - nowMs)
                let delaySec = Double(delayMs) / 1000.0
                DispatchQueue.main.asyncAfter(deadline: .now() + delaySec) { [weak self] in
                    self?.onRemotePlay?()
                }
            } else {
                onRemotePlay?()
            }
        } else if action.actionType == .seek {
            let timeStr = formatSecondsToTime(targetPos)
            showToast("\(action.lastActionByName) перемотал(а) на \(timeStr)")
            // Explicit seek: jump to target and match play/pause state
            onRemoteSeek?(targetPos)
            if action.isPlaying {
                if let scheduledStart = action.scheduledStartMs {
                    let delayMs = max(0, scheduledStart - nowMs)
                    let delaySec = Double(delayMs) / 1000.0
                    DispatchQueue.main.asyncAfter(deadline: .now() + delaySec) { [weak self] in
                        self?.onRemotePlay?()
                    }
                } else {
                    onRemotePlay?()
                }
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
        isUserSeeking: Bool = false,
        localSeason: Int? = nil,
        localEpisode: Int? = nil
    ) {
        guard let session = activeSession, isConnected else { return }
        guard !isApplyingRemoteAction else { return }
        guard !isBuffering && !isUserSeeking else { return }

        // If local episode differs from session episode, pause drift evaluation
        if let remSeason = session.season, let remEpisode = session.episode {
            if let locSeason = localSeason, let locEpisode = localEpisode {
                if remSeason != locSeason || remEpisode != locEpisode {
                    return
                }
            }
        }

        // Throttle drift checks to at most once every 1.0 second for snappy sub-frame sync
        let now = Date()
        guard now.timeIntervalSince(lastDriftEvaluationTime) >= 1.0 else { return }
        lastDriftEvaluationTime = now

        let playback = session.playback
        let baseSpeed = playback.speed > 0 ? playback.speed : 1.0

        // If remote is paused, ensure local is paused
        if !playback.isPlaying && localIsPlaying {
            onRemotePause?()
            return
        }

        // Only calibrate drift when BOTH are actively playing
        guard playback.isPlaying && localIsPlaying else {
            if currentAppliedRate != baseSpeed {
                currentAppliedRate = baseSpeed
                onRemoteRateChange?(baseSpeed)
            }
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

        let instantaneousDrift = localCurrentTime - targetPos // positive = local ahead, negative = local behind

        // Exponential Moving Average to smooth out timer and packet jitter
        if smoothedDrift == 0.0 {
            smoothedDrift = instantaneousDrift
        } else {
            smoothedDrift = (smoothedDrift * 0.60) + (instantaneousDrift * 0.40)
        }
        let absDrift = abs(smoothedDrift)

        // Sub-frame proportional rate controller:
        var desiredRate: Float = baseSpeed

        if absDrift <= 0.020 {
            // Tier 1: Sub-frame lockstep (<= 20ms = less than one video frame). In phase, zero echo.
            desiredRate = baseSpeed
        } else if absDrift <= 0.150 {
            // Tier 2: Micro-slew (20ms - 150ms).
            // Proportional controller: e = smoothedDrift (positive = local ahead).
            // Rate adjustment = -P * e.
            // Clamped to at most +/- 1.8% rate change.
            // Completely imperceptible pitch, seamless closure of phase gap within 3-5s.
            let pGain: Float = 0.15
            let delta = Float(-smoothedDrift) * pGain
            let clampedDelta = max(-0.018, min(0.018, delta))
            desiredRate = baseSpeed * (1.0 + clampedDelta)
        } else if absDrift <= 0.800 {
            // Tier 3: Catch-up zone (150ms - 800ms).
            // Smooth +/- 5% rate slew to close gap quickly without buffering or freezing.
            let adjustment: Float = 0.05
            desiredRate = smoothedDrift < 0 ? (baseSpeed * (1.0 + adjustment)) : (baseSpeed * (1.0 - adjustment))
        } else if absDrift <= 2.0 {
            // Tier 4: Fast slew zone (800ms - 2.0s).
            // +/- 10% rate adjustment.
            let adjustment: Float = 0.10
            desiredRate = smoothedDrift < 0 ? (baseSpeed * (1.0 + adjustment)) : (baseSpeed * (1.0 - adjustment))
        } else {
            // Tier 5: Frame-accurate seek (> 2.0s, e.g. after long stall or app backgrounding).
            AppDiagnostics.shared.log("[WatchParty] Drift > 2.0s (\(String(format: "%.2f", absDrift))s), resyncing seek to \(targetPos)")
            smoothedDrift = 0.0
            currentAppliedRate = baseSpeed
            onRemoteSeek?(targetPos)
            return
        }

        // Apply rate if changed by >= 0.3% or snapped back to baseSpeed
        if abs(desiredRate - currentAppliedRate) >= 0.003 || (desiredRate == baseSpeed && currentAppliedRate != baseSpeed) {
            let elapsedSinceRateChange = now.timeIntervalSince(lastRateChangeTime)
            if desiredRate == baseSpeed || elapsedSinceRateChange >= 1.5 {
                lastRateChangeTime = now
                currentAppliedRate = desiredRate
                AppDiagnostics.shared.log("[WatchParty] Precision P-controller slew: drift=\(String(format: "%.3f", smoothedDrift))s, rate=\(desiredRate)x, base=\(baseSpeed)x")
                onRemoteRateChange?(desiredRate)
            }
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
