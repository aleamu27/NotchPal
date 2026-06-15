import Foundation
import AppKit
import Combine

class SpotifyAPI: ObservableObject {
    static let shared = SpotifyAPI()

    private let baseURL = "https://api.spotify.com/v1"
    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Published state
    @Published var currentTrack: SpotifyTrack?
    @Published var lastPlayedTrack: SpotifyTrack?
    @Published var isPlaying = false
    @Published var artwork: NSImage?
    @Published var connectionState: ConnectionState = .checking

    enum ConnectionState: Equatable {
        case checking
        case notConnected
        case connected
        case noActiveDevice
        case error(String)
    }

    struct SpotifyTrack: Codable {
        let id: String
        let name: String
        let artist: String
        let album: String
        let artworkURL: String?
        let durationMs: Int
        var progressMs: Int

        static func from(json: [String: Any], progressMs: Int) -> SpotifyTrack? {
            guard let id = json["id"] as? String,
                  let name = json["name"] as? String,
                  let durationMs = json["duration_ms"] as? Int,
                  let album = json["album"] as? [String: Any],
                  let albumName = album["name"] as? String,
                  let artists = json["artists"] as? [[String: Any]],
                  let artistName = artists.first?["name"] as? String else {
                return nil
            }

            var artworkURL: String?
            if let images = album["images"] as? [[String: Any]],
               let image = images.first(where: { ($0["height"] as? Int ?? 0) >= 200 }) ?? images.first,
               let url = image["url"] as? String {
                artworkURL = url
            }

            return SpotifyTrack(
                id: id,
                name: name,
                artist: artistName,
                album: albumName,
                artworkURL: artworkURL,
                durationMs: durationMs,
                progressMs: progressMs
            )
        }
    }

    private var authCheckTimer: Timer?

    private init() {
        loadLastPlayedTrack()
        setupAuthObserver()
        checkInitialState()
        startAuthCheck()
    }

    private func setupAuthObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(authStatusChanged),
            name: NSNotification.Name("SpotifyAuthChanged"),
            object: nil
        )
    }

    private func startAuthCheck() {
        // Check auth status every 5 seconds
        authCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkAuthStatus()
        }
        if let timer = authCheckTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func checkAuthStatus() {
        let wasConnected = connectionState != .notConnected
        let isNowAuthenticated = SpotifyAuth.shared.isAuthenticated

        if !wasConnected && isNowAuthenticated {
            print("🔄 Auth check: User is now authenticated")
            connectionState = .checking
            fetchRecentlyPlayedInitial()
            startPolling()
        } else if wasConnected && !isNowAuthenticated {
            print("🔄 Auth check: User logged out")
            connectionState = .notConnected
            stopPolling()
        }
    }

    private func checkInitialState() {
        if SpotifyAuth.shared.isAuthenticated {
            connectionState = .checking
            fetchRecentlyPlayedInitial()
            startPolling()
        } else {
            connectionState = .notConnected
        }
    }

    private func fetchRecentlyPlayedInitial() {
        SpotifyAuth.shared.ensureValidToken { [weak self] token in
            guard let token = token else { return }
            self?.fetchRecentlyPlayed(token: token)
        }
    }

    @objc private func authStatusChanged() {
        DispatchQueue.main.async { [weak self] in
            if SpotifyAuth.shared.isAuthenticated {
                self?.connectionState = .checking
                self?.startPolling()
            } else {
                self?.connectionState = .notConnected
                self?.stopPolling()
            }
        }
    }

    // MARK: - Persistence

    private func loadLastPlayedTrack() {
        if let data = UserDefaults.standard.data(forKey: "spotify_last_track"),
           let track = try? JSONDecoder().decode(SpotifyTrack.self, from: data) {
            lastPlayedTrack = track
            loadCachedArtwork()
        }
    }

    private func saveLastPlayedTrack(_ track: SpotifyTrack) {
        lastPlayedTrack = track
        if let data = try? JSONEncoder().encode(track) {
            UserDefaults.standard.set(data, forKey: "spotify_last_track")
        }
    }

    private func loadCachedArtwork() {
        if let data = UserDefaults.standard.data(forKey: "spotify_last_artwork"),
           let image = NSImage(data: data) {
            artwork = image
        }
    }

    private func cacheArtwork(_ image: NSImage) {
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            UserDefaults.standard.set(jpegData, forKey: "spotify_last_artwork")
        }
    }

    // MARK: - Polling

    func startPolling() {
        pollTimer?.invalidate()

        guard SpotifyAuth.shared.isAuthenticated else {
            connectionState = .notConnected
            return
        }

        print("🔄 [SpotifyAPI] Starter polling")
        fetchCurrentlyPlaying()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            print("🔄 [SpotifyAPI] Poller Spotify for status")
            self?.fetchCurrentlyPlaying()
        }
        if let timer = pollTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stopPolling() {
        print("🛑 [SpotifyAPI] Stopper polling")
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Fetch Currently Playing

    private func fetchCurrentlyPlaying() {
        print("🎧 [SpotifyAPI] Henter nåværende sang fra Spotify")
        SpotifyAuth.shared.ensureValidToken { [weak self] token in
            guard let token = token else {
                DispatchQueue.main.async {
                    self?.connectionState = .notConnected
                }
                return
            }
            self?.fetchWithToken(token)
        }
    }

    private func fetchWithToken(_ token: String) {
        guard let url = URL(string: "\(baseURL)/me/player/currently-playing") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.connectionState = .error(error.localizedDescription)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else { return }

                switch httpResponse.statusCode {
                case 200:
                    self?.connectionState = .connected
                    if let data = data {
                        self?.parseTrackData(data)
                    }
                case 204:
                    // No active playback - fetch recently played
                    self?.currentTrack = nil
                    self?.isPlaying = false
                    self?.fetchRecentlyPlayed(token: token)
                case 401:
                    SpotifyAuth.shared.refreshAccessToken()
                case 403:
                    self?.connectionState = .error("Ingen tilgang")
                case 429:
                    // Rate limited - slow down polling
                    self?.stopPolling()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                        self?.startPolling()
                    }
                default:
                    if httpResponse.statusCode >= 500 {
                        // Server error - don't show to user
                    } else {
                        self?.connectionState = .error("Feil: \(httpResponse.statusCode)")
                    }
                }
            }
        }.resume()
    }

    private func parseTrackData(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let item = json["item"] as? [String: Any] else {
                return
            }

            let playing = json["is_playing"] as? Bool ?? false
            let progressMs = json["progress_ms"] as? Int ?? 0

            guard let track = SpotifyTrack.from(json: item, progressMs: progressMs) else {
                return
            }

            let trackChanged = currentTrack?.id != track.id

            currentTrack = track
            isPlaying = playing

            // Save as last played
            saveLastPlayedTrack(track)

            if trackChanged, let artworkURL = track.artworkURL {
                fetchArtwork(from: artworkURL)
            }

        } catch {
            print("❌ Parse error: \(error)")
        }
    }

    private func fetchRecentlyPlayed(token: String) {
        guard let url = URL(string: "\(baseURL)/me/player/recently-played?limit=1") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                DispatchQueue.main.async {
                    self?.connectionState = .noActiveDevice
                }
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]],
                   let firstItem = items.first,
                   let trackData = firstItem["track"] as? [String: Any],
                   let track = SpotifyTrack.from(json: trackData, progressMs: 0) {

                    DispatchQueue.main.async {
                        self?.lastPlayedTrack = track
                        self?.connectionState = .noActiveDevice
                        self?.saveLastPlayedTrack(track)

                        // Fetch artwork if needed
                        if let artworkURL = track.artworkURL, self?.artwork == nil {
                            self?.fetchArtwork(from: artworkURL)
                        }
                    }
                }
            } catch {
                print("❌ Recently played parse error: \(error)")
            }
        }.resume()
    }

    private func fetchArtwork(from urlString: String) {
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            if let data = data, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    self?.artwork = image
                    self?.cacheArtwork(image)
                }
            }
        }.resume()
    }

    // MARK: - Display Track (current or last played)

    var displayTrack: SpotifyTrack? {
        currentTrack ?? lastPlayedTrack
    }

    var statusText: String {
        switch connectionState {
        case .checking:
            return "Kobler til..."
        case .notConnected:
            return "Ikke koblet til"
        case .connected:
            return isPlaying ? "Spiller nå" : "Pauset"
        case .noActiveDevice:
            return "Sist spilt"
        case .error(let msg):
            return msg
        }
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        SpotifyAuth.shared.ensureValidToken { [weak self] token in
            guard let self = self, let token = token else { return }
            self.smartPlay(token: token)
        }
    }

    private func smartPlay(token: String) {
        // First, check if we have an active device
        getActiveDevice(token: token) { [weak self] deviceId in
            guard let self = self else { return }

            if let deviceId = deviceId {
                // We have a device, try to play
                self.tryPlay(deviceId: deviceId, token: token)
            } else {
                // No active device, find one and transfer
                self.findAndTransferToDevice(token: token) { success in
                    if success {
                        self.getActiveDevice(token: token) { newDeviceId in
                            if let newDeviceId = newDeviceId {
                                self.tryPlay(deviceId: newDeviceId, token: token)
                            }
                        }
                    }
                }
            }
        }
    }

    private func getActiveDevice(token: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)/me/player/devices") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let devices = json["devices"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Find active device or first available
            let activeDevice = devices.first { $0["is_active"] as? Bool == true }
            let deviceId = (activeDevice ?? devices.first)?["id"] as? String

            DispatchQueue.main.async { completion(deviceId) }
        }.resume()
    }

    private func tryPlay(deviceId: String, token: String) {
        guard let url = URL(string: "\(baseURL)/me/player/play?device_id=\(deviceId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let http = response as? HTTPURLResponse else { return }

            DispatchQueue.main.async {
                if http.statusCode == 204 || http.statusCode == 200 {
                    self?.connectionState = .connected
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self?.fetchCurrentlyPlaying()
                    }
                } else if http.statusCode == 403 {
                    self?.playFromLibrary(deviceId: deviceId, token: token)
                } else if http.statusCode == 404 {
                    self?.connectionState = .noActiveDevice
                }
            }
        }.resume()
    }

    private func playFromLibrary(deviceId: String, token: String) {
        if let lastTrack = lastPlayedTrack {
            let uri = "spotify:track:\(lastTrack.id)"
            playUri(uri, deviceId: deviceId, token: token)
            return
        }

        fetchTrackUri(from: "/me/player/recently-played?limit=1", key: "items", trackPath: ["track", "uri"], token: token) { [weak self] uri in
            if let uri = uri {
                self?.playUri(uri, deviceId: deviceId, token: token)
            } else {
                self?.fetchTrackUri(from: "/me/tracks?limit=1", key: "items", trackPath: ["track", "uri"], token: token) { uri in
                    if let uri = uri {
                        self?.playUri(uri, deviceId: deviceId, token: token)
                    } else {
                        self?.fetchTrackUri(from: "/me/top/tracks?limit=1", key: "items", trackPath: ["uri"], token: token) { uri in
                            if let uri = uri {
                                self?.playUri(uri, deviceId: deviceId, token: token)
                            } else {
                                DispatchQueue.main.async {
                                    self?.connectionState = .error("Åpne Spotify først")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func fetchTrackUri(from endpoint: String, key: String, trackPath: [String], token: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data = data,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json[key] as? [[String: Any]],
                  let firstItem = items.first else {
                completion(nil)
                return
            }

            var current: Any = firstItem
            for pathKey in trackPath {
                if let dict = current as? [String: Any], let next = dict[pathKey] {
                    current = next
                } else {
                    completion(nil)
                    return
                }
            }

            if let uri = current as? String {
                completion(uri)
            } else {
                completion(nil)
            }
        }.resume()
    }

    private func playUri(_ uri: String, deviceId: String, token: String) {
        guard let url = URL(string: "\(baseURL)/me/player/play?device_id=\(deviceId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["uris": [uri]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            guard let http = response as? HTTPURLResponse else { return }

            DispatchQueue.main.async {
                if http.statusCode == 204 || http.statusCode == 200 {
                    self?.connectionState = .connected
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.fetchCurrentlyPlaying()
                    }
                } else if http.statusCode == 403 {
                    self?.connectionState = .error("Krever Premium")
                }
            }
        }.resume()
    }

    private func findAndTransferToDevice(token: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/me/player/devices") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let devices = json["devices"] as? [[String: Any]],
                  let firstDevice = devices.first,
                  let deviceId = firstDevice["id"] as? String else {
                DispatchQueue.main.async {
                    self?.connectionState = .error("Ingen enheter funnet")
                    completion(false)
                }
                return
            }

            self.transferPlayback(to: deviceId, token: token, completion: completion)
        }.resume()
    }

    private func transferPlayback(to deviceId: String, token: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(baseURL)/me/player") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["device_ids": [deviceId]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            if let http = response as? HTTPURLResponse {
                DispatchQueue.main.async {
                    let success = http.statusCode == 204 || http.statusCode == 200
                    if success {
                        self?.connectionState = .connected
                    }
                    completion(success)
                }
            } else {
                DispatchQueue.main.async { completion(false) }
            }
        }.resume()
    }

    func pause() {
        sendCommand("/me/player/pause", method: "PUT")
    }

    func nextTrack() {
        sendCommand("/me/player/next", method: "POST")
    }

    func previousTrack() {
        sendCommand("/me/player/previous", method: "POST")
    }

    private func sendCommand(_ endpoint: String, method: String) {
        SpotifyAuth.shared.ensureValidToken { [weak self] token in
            guard let self = self,
                  let token = token,
                  let url = URL(string: "\(self.baseURL)\(endpoint)") else {
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
                if let http = response as? HTTPURLResponse {
                    DispatchQueue.main.async {
                        switch http.statusCode {
                        case 200, 204:
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self?.fetchCurrentlyPlaying()
                            }
                        case 403:
                            self?.connectionState = .error("Krever Premium")
                        case 404:
                            if endpoint.contains("play") {
                                self?.play()
                            } else {
                                self?.connectionState = .noActiveDevice
                            }
                        case 429:
                            break
                        default:
                            break
                        }
                    }
                }
            }.resume()
        }
    }
}

