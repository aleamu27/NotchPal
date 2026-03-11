import Foundation
import AppKit

class SpotifyAPI: ObservableObject {
    static let shared = SpotifyAPI()

    private let baseURL = "https://api.spotify.com/v1"
    private var pollTimer: Timer?
    private var useAppleScript = false // Fallback to AppleScript if API fails

    @Published var currentTrack: SpotifyTrack? {
        didSet {
            if let track = currentTrack, oldValue?.id != track.id {
                print("🎵 Now playing: \(track.name) by \(track.artist)")
            }
        }
    }
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var artwork: NSImage?

    struct SpotifyTrack {
        let id: String
        let name: String
        let artist: String
        let album: String
        let artworkURL: String?
        let durationMs: Int
        var progressMs: Int
    }

    private init() {
        print("🎵 SpotifyAPI initialized")
    }

    // MARK: - AppleScript Fallback (works without Premium!)

    private func fetchViaAppleScript() {
        // Don't use System Events - it's blocked in sandbox
        // Just try to talk to Spotify directly
        let script = """
        try
            tell application "Spotify"
                if player state is stopped then
                    return "STOPPED"
                end if

                set trackId to id of current track
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDuration to duration of current track
                set trackPosition to player position
                set trackArtwork to artwork url of current track
                set isPlaying to (player state is playing)

                return trackId & "|||" & trackName & "|||" & trackArtist & "|||" & trackAlbum & "|||" & (trackDuration as string) & "|||" & (trackPosition as string) & "|||" & trackArtwork & "|||" & (isPlaying as string)
            end tell
        on error
            return "NOT_RUNNING"
        end try
        """

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let appleScript = NSAppleScript(source: script) else { return }

            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)

            if let error = error {
                print("❌ AppleScript error: \(error)")
                return
            }

            guard let output = result.stringValue else { return }

            if output == "NOT_RUNNING" {
                print("📭 Spotify not running")
                DispatchQueue.main.async {
                    self?.currentTrack = nil
                    self?.isPlaying = false
                }
                return
            }

            if output == "STOPPED" {
                print("⏹️ Spotify stopped")
                DispatchQueue.main.async {
                    self?.currentTrack = nil
                    self?.isPlaying = false
                }
                return
            }

            let parts = output.components(separatedBy: "|||")
            guard parts.count >= 8 else {
                print("❌ Invalid AppleScript response: \(output)")
                return
            }

            let trackId = parts[0]
            let trackName = parts[1]
            let trackArtist = parts[2]
            let trackAlbum = parts[3]

            // Duration comes in ms from Spotify
            let durationMs = Int(Double(parts[4].replacingOccurrences(of: ",", with: ".")) ?? 0)

            // Position comes in seconds, convert to ms
            let positionStr = parts[5].replacingOccurrences(of: ",", with: ".")
            let positionSec = Double(positionStr) ?? 0
            let positionMs = Int(positionSec * 1000)

            let artworkURL = parts[6]
            let playing = parts[7] == "true"

            print("🎵 Position: \(positionStr)s -> \(positionMs)ms, Duration: \(durationMs)ms")

            // Only log track changes, not every poll

            let track = SpotifyTrack(
                id: trackId,
                name: trackName,
                artist: trackArtist,
                album: trackAlbum,
                artworkURL: artworkURL.isEmpty ? nil : artworkURL,
                durationMs: durationMs,
                progressMs: positionMs
            )

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let trackChanged = self.currentTrack?.id != track.id

                self.currentTrack = track
                self.isPlaying = playing
                self.progress = durationMs > 0 ? Double(positionMs) / Double(durationMs) : 0

                if trackChanged, let url = track.artworkURL {
                    self.fetchArtwork(from: url)
                }
            }
        }
    }

    private func controlViaAppleScript(_ command: String) {
        let script = """
        tell application "Spotify"
            \(command)
        end tell
        """

        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let appleScript = NSAppleScript(source: script) else { return }
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)

            if let error = error {
                print("❌ AppleScript control error: \(error)")
            } else {
                print("✅ AppleScript command executed: \(command)")
            }

            // Refresh after command
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.fetchViaAppleScript()
            }
        }
    }

    func startPolling() {
        print("▶️ Starting Spotify polling (using AppleScript for local control)...")

        pollTimer?.invalidate()

        // Use AppleScript - works without Premium and for local Spotify
        useAppleScript = true

        DispatchQueue.main.async { [weak self] in
            // Fetch immediately
            self?.fetchViaAppleScript()

            // Poll every 1 second for smooth progress updates
            self?.pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.fetchViaAppleScript()
            }
            if let timer = self?.pollTimer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    func stopPolling() {
        print("⏹️ Stopping polling")
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func fetchCurrentlyPlaying() {
        print("🔍 Fetching currently playing...")

        guard let token = SpotifyAuth.shared.accessToken else {
            print("⚠️ No access token for API call")
            return
        }
        print("🔑 Using token: \(token.prefix(20))...")

        guard let url = URL(string: "\(baseURL)/me/player/currently-playing") else {
            print("❌ Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("❌ Network error: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ No HTTP response")
                return
            }

            print("📡 Currently playing response: \(httpResponse.statusCode)")

            switch httpResponse.statusCode {
            case 200:
                if let data = data {
                    if let json = String(data: data, encoding: .utf8) {
                        print("📦 Got track data: \(json.prefix(150))...")
                    }
                    self?.parseTrackData(data)
                }
            case 204:
                print("📭 No active playback (204)")
                DispatchQueue.main.async {
                    self?.currentTrack = nil
                    self?.isPlaying = false
                    self?.progress = 0
                }
            case 401:
                print("⚠️ Token expired (401), refreshing...")
                SpotifyAuth.shared.refreshAccessToken()
            default:
                if let data = data, let body = String(data: data, encoding: .utf8) {
                    print("⚠️ API error \(httpResponse.statusCode): \(body)")
                } else {
                    print("⚠️ API error \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }

    private func parseTrackData(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let playing = json["is_playing"] as? Bool ?? false
            let progressMs = json["progress_ms"] as? Int ?? 0

            guard let item = json["item"] as? [String: Any],
                  let id = item["id"] as? String,
                  let name = item["name"] as? String,
                  let durationMs = item["duration_ms"] as? Int,
                  let album = item["album"] as? [String: Any],
                  let albumName = album["name"] as? String,
                  let artists = item["artists"] as? [[String: Any]],
                  let artistName = artists.first?["name"] as? String else {
                return
            }

            var artworkURL: String?
            if let images = album["images"] as? [[String: Any]],
               let image = images.first(where: { ($0["height"] as? Int ?? 0) >= 200 }) ?? images.first,
               let url = image["url"] as? String {
                artworkURL = url
            }

            let track = SpotifyTrack(
                id: id,
                name: name,
                artist: artistName,
                album: albumName,
                artworkURL: artworkURL,
                durationMs: durationMs,
                progressMs: progressMs
            )

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                let trackChanged = self.currentTrack?.id != track.id

                self.currentTrack = track
                self.isPlaying = playing
                self.progress = durationMs > 0 ? Double(progressMs) / Double(durationMs) : 0

                if trackChanged, let artworkURL = artworkURL {
                    self.fetchArtwork(from: artworkURL)
                }
            }

        } catch {
            print("❌ Parse error: \(error)")
        }
    }

    private func fetchArtwork(from urlString: String) {
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            if let data = data, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    self?.artwork = image
                }
            }
        }.resume()
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        print("⏯️ Toggle play/pause")
        if useAppleScript {
            controlViaAppleScript("playpause")
        } else {
            if isPlaying { pause() } else { play() }
        }
    }

    func play() {
        print("▶️ Play")
        if useAppleScript {
            controlViaAppleScript("play")
        } else {
            sendCommand("/me/player/play", method: "PUT")
        }
    }

    func pause() {
        print("⏸️ Pause")
        if useAppleScript {
            controlViaAppleScript("pause")
        } else {
            sendCommand("/me/player/pause", method: "PUT")
        }
    }

    func nextTrack() {
        print("⏭️ Next")
        if useAppleScript {
            controlViaAppleScript("next track")
        } else {
            sendCommand("/me/player/next", method: "POST")
        }
    }

    func previousTrack() {
        print("⏮️ Previous")
        if useAppleScript {
            controlViaAppleScript("previous track")
        } else {
            sendCommand("/me/player/previous", method: "POST")
        }
    }

    private func sendCommand(_ endpoint: String, method: String) {
        guard let token = SpotifyAuth.shared.accessToken,
              let url = URL(string: "\(baseURL)\(endpoint)") else {
            print("⚠️ Cannot send command - no token")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let http = response as? HTTPURLResponse {
                print("🎮 Command response: \(http.statusCode)")

                if http.statusCode == 200 || http.statusCode == 204 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.fetchCurrentlyPlaying()
                    }
                } else if http.statusCode == 403 {
                    if let data = data, let body = String(data: data, encoding: .utf8) {
                        print("🚫 403 Forbidden: \(body)")
                    }
                    print("💡 Tips: Åpne Spotify og start avspilling på en enhet først!")
                } else if http.statusCode == 404 {
                    print("🚫 404: Ingen aktiv Spotify-enhet funnet")
                    print("💡 Tips: Åpne Spotify-appen og spill noe!")
                }
            }
        }.resume()
    }
}
