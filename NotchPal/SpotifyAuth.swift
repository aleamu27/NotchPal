import Foundation
import AppKit
import CryptoKit

class SpotifyAuth: ObservableObject {
    static let shared = SpotifyAuth()

    private let clientId = "b0b70c89976c44309713ad547fb7b3a3"
    private let redirectUri = "http://127.0.0.1:8888/callback"
    private let scopes = "user-read-playback-state user-modify-playback-state user-read-currently-playing"

    @Published var isAuthenticated = false {
        didSet { print("🔐 isAuthenticated changed: \(isAuthenticated)") }
    }
    @Published var accessToken: String? {
        didSet { print("🔑 accessToken changed: \(accessToken != nil ? "SET" : "nil")") }
    }

    private var refreshToken: String?
    private var codeVerifier: String?
    private var tokenExpirationDate: Date?
    private var localServer: LocalAuthServer?

    private let tokenKey = "spotify_access_token"
    private let refreshTokenKey = "spotify_refresh_token"
    private let expirationKey = "spotify_token_expiration"

    private init() {
        print("🔐 SpotifyAuth initializing...")
        loadTokens()
        print("🔐 SpotifyAuth initialized - authenticated: \(isAuthenticated)")
    }

    // MARK: - Load saved tokens
    private func loadTokens() {
        print("📂 Loading saved tokens...")

        if let token = UserDefaults.standard.string(forKey: tokenKey) {
            print("   Found saved access token")
            accessToken = token
            refreshToken = UserDefaults.standard.string(forKey: refreshTokenKey)
            tokenExpirationDate = UserDefaults.standard.object(forKey: expirationKey) as? Date

            if let expiration = tokenExpirationDate {
                print("   Token expires: \(expiration)")
                if Date() > expiration {
                    print("   Token expired, refreshing...")
                    refreshAccessToken()
                } else {
                    isAuthenticated = true
                    print("   ✅ Token valid, authenticated!")
                }
            } else {
                isAuthenticated = true
            }
        } else {
            print("   No saved tokens found")
        }
    }

    // MARK: - Start Auth Flow
    func startAuth() {
        print("🎵 ========== STARTING SPOTIFY AUTH ==========")

        // Stop any existing server
        localServer?.stop()

        // Start local server
        localServer = LocalAuthServer { [weak self] code in
            print("🎵 Server received auth code!")
            guard let self = self, let verifier = self.codeVerifier else {
                print("❌ Missing self or verifier")
                return
            }
            self.exchangeCodeForToken(code: code, verifier: verifier)
            self.localServer?.stop()
        }
        localServer?.start()

        // Generate PKCE values
        codeVerifier = generateCodeVerifier()
        guard let verifier = codeVerifier else {
            print("❌ Failed to generate code verifier")
            return
        }

        let codeChallenge = generateCodeChallenge(from: verifier)

        // Build auth URL
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "show_dialog", value: "true")
        ]

        guard let url = components.url else {
            print("❌ Failed to create auth URL")
            return
        }

        print("🔗 Opening auth URL: \(url.absoluteString.prefix(80))...")
        NSWorkspace.shared.open(url)
    }

    func handleCallback(url: URL) {
        print("📥 Handling callback URL: \(url)")

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            print("❌ No code in callback URL")
            if let error = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "error" })?.value {
                print("❌ Auth error: \(error)")
            }
            return
        }

        guard let verifier = codeVerifier else {
            print("❌ No code verifier stored")
            return
        }

        print("✅ Got auth code, exchanging for token...")
        exchangeCodeForToken(code: code, verifier: verifier)
    }

    // MARK: - Token Exchange
    private func exchangeCodeForToken(code: String, verifier: String) {
        print("🔄 Exchanging code for token...")

        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri,
            "client_id": clientId,
            "code_verifier": verifier
        ]

        let bodyString = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")

        request.httpBody = bodyString.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("❌ Token request failed: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("❌ No data in token response")
                return
            }

            if let json = String(data: data, encoding: .utf8) {
                print("📄 Token response: \(json.prefix(200))")
            }

            self?.handleTokenResponse(data: data)
        }.resume()
    }

    private func handleTokenResponse(data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Failed to parse JSON")
                return
            }

            if let error = json["error"] as? String {
                print("❌ Token error: \(error)")
                if let desc = json["error_description"] as? String {
                    print("   Description: \(desc)")
                }
                return
            }

            guard let token = json["access_token"] as? String else {
                print("❌ No access_token in response")
                return
            }

            print("✅ Got access token!")

            // Save tokens
            UserDefaults.standard.set(token, forKey: tokenKey)

            if let refresh = json["refresh_token"] as? String {
                UserDefaults.standard.set(refresh, forKey: refreshTokenKey)
                self.refreshToken = refresh
            }

            if let expiresIn = json["expires_in"] as? Int {
                let expiration = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
                UserDefaults.standard.set(expiration, forKey: expirationKey)
                self.tokenExpirationDate = expiration
            }

            // Update state on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.accessToken = token
                self.isAuthenticated = true
                print("✅ Authentication complete!")
            }

        } catch {
            print("❌ JSON parsing error: \(error)")
        }
    }

    // MARK: - Refresh Token
    func refreshAccessToken() {
        guard let refreshToken = refreshToken else {
            print("❌ No refresh token, need to re-auth")
            DispatchQueue.main.async {
                self.isAuthenticated = false
            }
            return
        }

        print("🔄 Refreshing access token...")

        let url = URL(string: "https://accounts.spotify.com/api/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)&client_id=\(clientId)"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data else {
                print("❌ Refresh failed: \(error?.localizedDescription ?? "unknown")")
                return
            }
            self?.handleTokenResponse(data: data)
        }.resume()
    }

    // MARK: - Logout
    func logout() {
        print("🚪 Logging out...")
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: expirationKey)

        DispatchQueue.main.async {
            self.accessToken = nil
            self.refreshToken = nil
            self.isAuthenticated = false
        }
    }

    func ensureValidToken(completion: @escaping (String?) -> Void) {
        if let expiration = tokenExpirationDate, Date() > expiration {
            refreshAccessToken()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                completion(self.accessToken)
            }
        } else {
            completion(accessToken)
        }
    }

    // MARK: - PKCE Helpers
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64URLEncodedString()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
}

// MARK: - Local Auth Server
class LocalAuthServer {
    private var socket: Int32 = -1
    private let port: UInt16 = 8888
    private let onCode: (String) -> Void
    private var isRunning = false

    init(onCode: @escaping (String) -> Void) {
        self.onCode = onCode
    }

    func start() {
        print("🌐 Starting local auth server on port \(port)...")

        socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else {
            print("❌ Failed to create socket")
            return
        }

        var reuse: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindResult < 0 {
            print("❌ Failed to bind to port \(port)")
            return
        }

        if Darwin.listen(socket, 1) < 0 {
            print("❌ Failed to listen")
            return
        }

        isRunning = true
        print("✅ Server listening on http://127.0.0.1:\(port)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.acceptConnection()
        }
    }

    private func acceptConnection() {
        var clientAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)

        let client = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.accept(socket, $0, &len)
            }
        }

        guard client >= 0, isRunning else { return }

        print("📥 Client connected")

        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = Darwin.read(client, &buffer, buffer.count)

        if bytesRead > 0 {
            let request = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""

            // Extract code
            if let codeRange = request.range(of: "code="),
               let endRange = request[codeRange.upperBound...].firstIndex(where: { $0 == " " || $0 == "&" }) {
                let code = String(request[codeRange.upperBound..<endRange])
                print("✅ Extracted auth code")

                // Send success page
                let html = """
                <!DOCTYPE html><html><head><title>NotchPal</title>
                <style>body{font-family:system-ui;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#121212;color:white}
                .ok{text-align:center}h1{color:#1DB954}</style></head>
                <body><div class="ok"><h1>✓ Koblet til!</h1><p>Du kan lukke denne fanen.</p></div></body></html>
                """

                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"
                _ = response.withCString { Darwin.write(client, $0, Int(strlen($0))) }

                DispatchQueue.main.async {
                    self.onCode(code)
                }
            }
        }

        Darwin.close(client)
    }

    func stop() {
        print("🛑 Stopping server...")
        isRunning = false
        if socket >= 0 {
            Darwin.close(socket)
            socket = -1
        }
    }
}

// MARK: - Base64URL
extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
