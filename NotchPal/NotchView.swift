import SwiftUI
import AppKit
import AVFoundation
import AudioToolbox

struct NotchView: View {
    @ObservedObject private var vm = NotchViewModel.shared
    @ObservedObject private var spotify = SpotifyAPI.shared
    @ObservedObject private var cal = CalendarManager.shared
    @State private var selectedTab = 0

    private let notchW: CGFloat = 180
    private let notchH: CGFloat = 32
    private let expandedW: CGFloat = 980
    private let expandedH: CGFloat = 210

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(notchWidth: notchW, notchHeight: notchH, expanded: vm.isExpanded)
                    .fill(Color.black)

                if vm.isExpanded {
                    expandedContent
                } else {
                    collapsedContent
                }
            }
            .frame(width: vm.isExpanded ? expandedW : notchW + 72,
                   height: vm.isExpanded ? expandedH : notchH)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vm.isExpanded)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            spotify.startPolling()
            cal.fetchTodayEvents()
        }
    }

    // MARK: - Collapsed
    var collapsedContent: some View {
        HStack(spacing: 0) {
            HStack {
                if let img = spotify.artwork {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(width: 36)

            Spacer().frame(width: notchW)

            HStack {
                if spotify.isPlaying { AudioBars() }
            }
            .frame(width: 36)
        }
        .frame(width: notchW + 72, height: notchH)
    }

    // MARK: - Expanded
    var expandedContent: some View {
        VStack(spacing: 0) {
            // Top nav
            HStack {
                HStack(spacing: 2) {
                    NavIcon(icon: "house.fill", active: selectedTab == 0) { selectedTab = 0 }
                    NavIcon(icon: "cloud.fill", active: false) {}
                    NavIcon(icon: "gamecontroller.fill", active: false) {}
                    NavIcon(icon: "doc.text.fill", active: false) {}
                }

                Spacer()
                Color.clear.frame(width: notchW + 40)
                Spacer()

                HStack(spacing: 2) {
                    NavIcon(icon: "gearshape.fill", active: false) {}
                    NavIcon(icon: "xmark", active: false) {}
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            // Main content
            HStack(spacing: 0) {
                MusicPlayerCard(spotify: spotify)
                    .frame(width: 260, height: 140)
                    .clipped()

                VerticalDivider()

                CalendarCard(cal: cal)
                    .frame(width: 170, height: 140)

                VerticalDivider()

                ShortcutsGrid()
                    .frame(width: 100, height: 140)

                VerticalDivider()

                PomodoroCard()
                    .frame(width: 150, height: 140)

                VerticalDivider()

                MirrorCard()
                    .frame(width: 170, height: 140)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            Spacer()
        }
        .frame(width: expandedW, height: expandedH)
    }
}

// MARK: - Music Player Card
struct MusicPlayerCard: View {
    @ObservedObject var spotify: SpotifyAPI

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Album art with Spotify badge
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let img = spotify.artwork {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Rectangle().fill(Color(white: 0.15))
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                // Spotify badge
                Circle()
                    .fill(Color(red: 0.12, green: 0.84, blue: 0.38))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "airplayaudio")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.black)
                    )
                    .offset(x: -8, y: -8)
            }

            // Right side: info + controls
            VStack(alignment: .leading, spacing: 0) {
                // Song title
                Text(spotify.currentTrack?.name ?? "No Track")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.top, 4)

                // Artist
                Text(spotify.currentTrack?.artist ?? "Artist")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .padding(.top, 2)

                Spacer()

                // Progress bar
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.25))
                            .frame(height: 4)
                        Capsule()
                            .fill(Color.white)
                            .frame(width: max(0, g.size.width * progressRatio), height: 4)
                    }
                }
                .frame(height: 4)

                // Time labels
                HStack {
                    Text(formatMs(spotify.currentTrack?.progressMs ?? 0))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    Text(formatMs(spotify.currentTrack?.durationMs ?? 0))
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.top, 6)

                // Playback controls
                HStack(spacing: 24) {
                    Button {
                        triggerHaptic()
                        NotchViewModel.shared.keepOpen()
                        spotify.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(BounceButtonStyle())

                    Button {
                        triggerHaptic()
                        NotchViewModel.shared.keepOpen()
                        spotify.togglePlayPause()
                    } label: {
                        Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(BounceButtonStyle())

                    Button {
                        triggerHaptic()
                        NotchViewModel.shared.keepOpen()
                        spotify.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(BounceButtonStyle())
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
    }

    var progressRatio: Double {
        guard let track = spotify.currentTrack, track.durationMs > 0 else { return 0 }
        return Double(track.progressMs) / Double(track.durationMs)
    }

    func formatMs(_ ms: Int) -> String {
        let s = ms / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Calendar Card
struct CalendarCard: View {
    @ObservedObject var cal: CalendarManager

    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                // Header with navigation
                HStack {
                    Button {
                        triggerHaptic()
                        NotchViewModel.shared.keepOpen()
                        cal.goToPreviousDay()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(BounceButtonStyle())

                    Spacer()

                    VStack(spacing: 1) {
                        Text(monthName())
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text(dayLabel())
                            .font(.system(size: 9))
                            .foregroundColor(cal.isToday ? .green : .white.opacity(0.5))
                    }

                    Spacer()

                    Button {
                        triggerHaptic()
                        NotchViewModel.shared.keepOpen()
                        cal.goToNextDay()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(BounceButtonStyle())
                }

                Spacer().frame(height: 6)

                // Events (fixed height)
                VStack(alignment: .leading, spacing: 6) {
                    if cal.events.isEmpty {
                        EventItem(color: .gray, title: "Ingen hendelser", time: "")
                    } else {
                        ForEach(Array(cal.events.prefix(2).enumerated()), id: \.offset) { idx, ev in
                            EventItem(
                                color: idx == 0 ? .pink : Color(red: 0.5, green: 0.3, blue: 0.9),
                                title: ev.title,
                                time: formatEventTime(ev)
                            )
                        }
                    }
                }
                .frame(height: 58)

                Spacer()

                // Week strip - clickable days
                HStack(spacing: 0) {
                    ForEach(getWeekDays(), id: \.date) { d in
                        Button {
                            triggerHaptic()
                            NotchViewModel.shared.keepOpen()
                            cal.selectDate(d.date)
                        } label: {
                            VStack(spacing: 2) {
                                Text(d.dayName)
                                    .font(.system(size: 9))
                                    .foregroundColor(Color(white: 0.5))
                                Text("\(d.num)")
                                    .font(.system(size: 14, weight: d.isSelected ? .bold : .regular))
                                    .foregroundColor(d.isToday ? .green : .white)
                            }
                            .frame(width: 32, height: 36)
                            .background(d.isSelected ? Color(white: 0.2) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(BounceButtonStyle())
                    }
                }
            }
            .padding(8)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    func monthName() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: cal.selectedDate)
    }

    func dayLabel() -> String {
        if cal.isToday { return "I dag" }
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: cal.selectedDate)
    }

    func formatEventTime(_ event: CalendarManager.CalendarEvent) -> String {
        if event.isAllDay { return "Hele dagen" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: event.startTime)) - \(f.string(from: event.endTime))"
    }

    struct DayData: Hashable {
        let date: Date
        let dayName: String
        let num: Int
        let isToday: Bool
        let isSelected: Bool
    }

    func getWeekDays() -> [DayData] {
        let c = Calendar.current
        let today = Date()
        return (-2...2).map { offset in
            let date = c.date(byAdding: .day, value: offset, to: today)!
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return DayData(
                date: date,
                dayName: f.string(from: date),
                num: c.component(.day, from: date),
                isToday: offset == 0,
                isSelected: c.isDate(date, inSameDayAs: cal.selectedDate)
            )
        }
    }
}

struct EventItem: View {
    let color: Color
    let title: String
    let time: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 2, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if !time.isEmpty {
                    Text(time)
                        .font(.system(size: 9))
                        .foregroundColor(Color(white: 0.45))
                }
            }
        }
    }
}

// MARK: - Shortcuts Grid
class ShortcutsManager: ObservableObject {
    static let shared = ShortcutsManager()

    struct Shortcut: Identifiable, Codable {
        let id: UUID
        var url: String
        var icon: String
        var bgColor: String
        var iconColor: String

        init(url: String, icon: String = "link", bgColor: String = "1a1a1a", iconColor: String = "ffffff") {
            self.id = UUID()
            self.url = url
            self.icon = icon
            self.bgColor = bgColor
            self.iconColor = iconColor
        }
    }

    @Published var shortcuts: [Shortcut] = []
    @Published var favicons: [UUID: NSImage] = [:]

    private init() {
        loadShortcuts()
    }

    func addShortcut(url: String) {
        let shortcut = Shortcut(url: url)
        shortcuts.append(shortcut)
        saveShortcuts()
        fetchFavicon(for: shortcut)
    }

    func removeShortcut(_ shortcut: Shortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
        favicons.removeValue(forKey: shortcut.id)
        saveShortcuts()
    }

    func fetchFavicon(for shortcut: Shortcut) {
        guard let url = URL(string: shortcut.url),
              let host = url.host else { return }

        // Use Google's favicon service
        let faviconURL = "https://www.google.com/s2/favicons?domain=\(host)&sz=64"

        guard let iconURL = URL(string: faviconURL) else { return }

        URLSession.shared.dataTask(with: iconURL) { [weak self] data, _, _ in
            if let data = data, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    self?.favicons[shortcut.id] = image
                }
            }
        }.resume()
    }

    func loadAllFavicons() {
        for shortcut in shortcuts {
            if favicons[shortcut.id] == nil {
                fetchFavicon(for: shortcut)
            }
        }
    }

    private func saveShortcuts() {
        if let data = try? JSONEncoder().encode(shortcuts) {
            UserDefaults.standard.set(data, forKey: "notchpal_shortcuts")
        }
    }

    private func loadShortcuts() {
        if let data = UserDefaults.standard.data(forKey: "notchpal_shortcuts"),
           let saved = try? JSONDecoder().decode([Shortcut].self, from: data) {
            shortcuts = saved
            // Load favicons for existing shortcuts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.loadAllFavicons()
            }
        }
    }
}

struct ShortcutsGrid: View {
    @ObservedObject var manager = ShortcutsManager.shared
    @State private var showingAddSheet = false
    @State private var newURL = ""

    // Smaller cells to fit in 100px width
    private let cellSize: CGFloat = 32

    var body: some View {
        VStack(spacing: 3) {
            gridRow(indices: [0, 1])
            gridRow(indices: [2, 3])
            gridRow(indices: [4, 5])
        }
        .padding(4)
        .frame(width: 100, height: 140)
        .background(Color.black)
        .clipped()
        .sheet(isPresented: $showingAddSheet) {
            AddShortcutSheet(newURL: $newURL, isPresented: $showingAddSheet, manager: manager)
        }
    }

    func gridRow(indices: [Int]) -> some View {
        HStack(spacing: 3) {
            ForEach(indices, id: \.self) { idx in
                cellView(for: idx)
            }
        }
    }

    @ViewBuilder
    func cellView(for idx: Int) -> some View {
        if idx < manager.shortcuts.count {
            ShortcutCellButton(shortcut: manager.shortcuts[idx], size: cellSize)
        } else if idx == manager.shortcuts.count && manager.shortcuts.count < 6 {
            AddCellButton(size: cellSize, showingSheet: $showingAddSheet)
        } else {
            EmptyCell(size: cellSize)
        }
    }
}

// Add button with GREEN border so user can SEE where it is
struct AddCellButton: View {
    let size: CGFloat
    @Binding var showingSheet: Bool
    @ObservedObject var manager = ShortcutsManager.shared

    var body: some View {
        Button {
            print("➕ ADD BUTTON CLICKED!")
            if let url = URL(string: "https://youtube.com") {
                NSWorkspace.shared.open(url)
            }
            showingSheet = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.green.opacity(0.2))
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.green, lineWidth: 2)
                Image(systemName: "plus")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundColor(.green)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(BounceButtonStyle())
    }
}


struct EmptyCell: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.black)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

struct AddShortcutSheet: View {
    @Binding var newURL: String
    @Binding var isPresented: Bool
    var manager: ShortcutsManager

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Shortcut")
                .font(.headline)

            TextField("URL (e.g., https://google.com)", text: $newURL)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            HStack {
                Button("Cancel") {
                    isPresented = false
                    newURL = ""
                }

                Button("Add") {
                    if !newURL.isEmpty {
                        var urlToAdd = newURL
                        if !urlToAdd.hasPrefix("http://") && !urlToAdd.hasPrefix("https://") {
                            urlToAdd = "https://" + urlToAdd
                        }
                        manager.addShortcut(url: urlToAdd)
                        newURL = ""
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}

struct ShortcutCellButton: View {
    let shortcut: ShortcutsManager.Shortcut
    let size: CGFloat
    @ObservedObject var manager = ShortcutsManager.shared

    var body: some View {
        Button {
            print("🔗 Opening: \(shortcut.url)")
            // Force open with Safari to test if it's Arc-specific
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", "Safari", shortcut.url]
            try? process.run()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)

                if let favicon = manager.favicons[shortcut.id] {
                    Image(nsImage: favicon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: size * 0.6, height: size * 0.6)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "link")
                        .font(.system(size: size * 0.35, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(BounceButtonStyle())
    }
}

// MARK: - Quote Card
class PomodoroTimer: ObservableObject {
    static let shared = PomodoroTimer()

    @Published var timeRemaining: Int = 25 * 60  // 25 minutes
    @Published var isRunning = false
    @Published var currentSession = 1
    @Published var totalSessions = 4
    @Published var isBreak = false

    private var timer: Timer?

    let workDuration = 25 * 60
    let shortBreakDuration = 5 * 60
    let longBreakDuration = 15 * 60

    func toggle() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }

    func start() {
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                self.completeSession()
            }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        timeRemaining = isBreak ? shortBreakDuration : workDuration
    }

    func skip() {
        completeSession()
    }

    private func completeSession() {
        pause()
        if isBreak {
            isBreak = false
            timeRemaining = workDuration
        } else {
            currentSession += 1
            if currentSession > totalSessions {
                currentSession = 1
                timeRemaining = longBreakDuration
            } else {
                timeRemaining = shortBreakDuration
            }
            isBreak = true
        }
    }

    var timeString: String {
        let mins = timeRemaining / 60
        let secs = timeRemaining % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct PomodoroCard: View {
    @ObservedObject var timer = PomodoroTimer.shared

    var body: some View {
        VStack(spacing: 6) {
            // Header
            HStack {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text(timer.isBreak ? "Break" : "Focus")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                Text("(\(timer.currentSession)/\(timer.totalSessions))")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                Spacer()
            }

            // Timer display
            Text(timer.timeString)
                .font(.system(size: 36, weight: .medium, design: .rounded))
                .foregroundColor(timer.isBreak ? .green : .cyan)

            Spacer()

            // Controls
            HStack(spacing: 16) {
                Button {
                    triggerHaptic()
                    timer.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(BounceButtonStyle())

                Button {
                    triggerHaptic()
                    timer.toggle()
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(BounceButtonStyle())

                Button {
                    triggerHaptic()
                    timer.skip()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(BounceButtonStyle())
            }
        }
        .padding(10)
    }
}

// MARK: - Focus Timer Card
// Camera Mirror View
class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    @Published var isReady = false
    @Published var isShowing = false  // Track if mirror is currently displayed
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined

    private var captureSession: AVCaptureSession?

    override init() {
        super.init()
        checkAuthorization()
    }

    func checkAuthorization() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.authorizationStatus = granted ? .authorized : .denied
                completion(granted)
            }
        }
    }

    func startSession() {
        guard authorizationStatus == .authorized else {
            print("⚠️ Camera not authorized")
            return
        }

        // If session exists and is running, just mark ready
        if let session = captureSession, session.isRunning {
            DispatchQueue.main.async {
                self.isReady = true
            }
            return
        }

        // Create fresh session each time to avoid CMIO errors
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let session = AVCaptureSession()
            session.sessionPreset = .high

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                print("❌ No front camera found")
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
            } catch {
                print("❌ Camera input error: \(error)")
                return
            }

            session.startRunning()

            DispatchQueue.main.async {
                self?.captureSession = session
                self?.isReady = session.isRunning
                print("📷 Camera started: \(session.isRunning)")
            }
        }
    }

    func stopSession() {
        // Completely tear down session to avoid CMIO errors on restart
        if let session = captureSession {
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
                for input in session.inputs {
                    session.removeInput(input)
                }
            }
        }
        captureSession = nil
        isReady = false
        print("📷 Camera stopped and released")
    }

    var session: AVCaptureSession? {
        return captureSession
    }
}

// Custom NSView for camera preview
class CameraPreviewView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentSession: AVCaptureSession?

    override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
    }

    func setSession(_ session: AVCaptureSession) {
        // Don't recreate if same session
        if currentSession === session && previewLayer != nil {
            return
        }

        currentSession = session

        // Remove old preview layer
        previewLayer?.removeFromSuperlayer()

        // Create new preview layer
        let newLayer = AVCaptureVideoPreviewLayer(session: session)
        newLayer.videoGravity = .resizeAspectFill

        // Mirror horizontally for selfie effect
        newLayer.transform = CATransform3DMakeScale(-1, 1, 1)

        layer?.addSublayer(newLayer)
        previewLayer = newLayer

        // Force layout
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView(frame: NSRect(x: 0, y: 0, width: 170, height: 140))
        view.setSession(session)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {
        // Only update if session changed
        nsView.setSession(session)
    }
}

struct MirrorCard: View {
    @ObservedObject var camera = CameraManager.shared

    var body: some View {
        ZStack {
            if camera.isShowing {
                // Show camera preview or permission request
                ZStack {
                    switch camera.authorizationStatus {
                    case .authorized:
                        if camera.isReady, let session = camera.session {
                            CameraPreview(session: session)
                        } else {
                            Color(white: 0.1)
                            VStack {
                                ProgressView()
                                Text("Starting camera...")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                            .onAppear {
                                camera.startSession()
                            }
                        }

                    case .notDetermined:
                        Color(white: 0.1)
                        VStack(spacing: 10) {
                            Image(systemName: "camera")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.6))
                            Text("Camera access needed")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            Button("Allow") {
                                camera.requestAccess { granted in
                                    if granted {
                                        camera.startSession()
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                    case .denied, .restricted:
                        Color(white: 0.1)
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.red.opacity(0.6))
                            Text("Camera denied")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            Text("Enable in System Settings")
                                .font(.system(size: 9))
                                .foregroundColor(.gray.opacity(0.7))
                        }

                    @unknown default:
                        Color(white: 0.1)
                    }

                    // Close button
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                triggerHaptic()
                                camera.isShowing = false
                                camera.stopSession()
                                NotchViewModel.shared.lockOpen = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white.opacity(0.8))
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                            .buttonStyle(BounceButtonStyle())
                            .padding(6)
                        }
                        Spacer()
                    }
                }
            } else {
                // Show mirror button
                Button {
                    triggerHaptic()
                    camera.isShowing = true
                    NotchViewModel.shared.lockOpen = true
                    camera.checkAuthorization()
                    if camera.authorizationStatus == .authorized {
                        camera.startSession()
                    }
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 36))
                            .foregroundColor(.white.opacity(0.7))

                        Text("Mirror")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(BounceButtonStyle())
            }
        }
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Shared Components

struct VerticalDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 1, height: 100)
            .padding(.horizontal, 8)
    }
}

// MARK: - Responsive Button Style with Haptic Feedback

// Helper to trigger haptic feedback
struct HapticTrigger: ViewModifier {
    let isPressed: Bool
    let pattern: NSHapticFeedbackManager.FeedbackPattern

    @State private var lastState = false

    func body(content: Content) -> some View {
        content
            .background(
                HapticHelper(isPressed: isPressed, lastState: $lastState, pattern: pattern)
            )
    }
}

struct HapticHelper: View {
    let isPressed: Bool
    @Binding var lastState: Bool
    let pattern: NSHapticFeedbackManager.FeedbackPattern

    var body: some View {
        Color.clear
            .onAppear {
                lastState = isPressed
            }
            .onChange(of: isPressed) { newValue in
                if newValue && !lastState {
                    triggerHaptic(pattern)
                }
                lastState = newValue
            }
    }
}

// Global haptic helper function
func triggerHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .levelChange) {
    // Try haptic feedback
    NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    // Also play subtle system click sound as backup
    AudioServicesPlaySystemSound(1104) // Subtle tap sound
}

struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.5), value: configuration.isPressed)
            .modifier(HapticTrigger(isPressed: configuration.isPressed, pattern: .levelChange))
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .modifier(HapticTrigger(isPressed: configuration.isPressed, pattern: .generic))
    }
}

struct NavIcon: View {
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button {
            NotchViewModel.shared.keepOpen()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(active ? .white : .white.opacity(0.4))
                .frame(width: 28, height: 24)
                .background(active ? Color.white.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(SoftButtonStyle())
    }
}

struct CtrlBtn: View {
    let icon: String
    var size: CGFloat = 14
    let action: () -> Void

    var body: some View {
        Button {
            NotchViewModel.shared.keepOpen()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundColor(.white)
        }
        .buttonStyle(BounceButtonStyle())
    }
}

struct AudioBars: View {
    @State private var h: [CGFloat] = [3, 5, 4]

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(Color.green).frame(width: 2, height: h[i])
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.1)) {
                    h = [.random(in: 2...7), .random(in: 3...9), .random(in: 2...6)]
                }
            }
        }
    }
}

// MARK: - Notch Shape
struct NotchShape: Shape {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var expanded: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cr: CGFloat = expanded ? 20 : rect.height / 2
        let nr: CGFloat = 10

        p.move(to: .init(x: 0, y: 0))

        if expanded {
            let nL = rect.midX - notchWidth / 2
            let nR = rect.midX + notchWidth / 2
            p.addLine(to: .init(x: nL - nr, y: 0))
            p.addQuadCurve(to: .init(x: nL, y: nr), control: .init(x: nL, y: 0))
            p.addLine(to: .init(x: nL, y: notchHeight - nr))
            p.addQuadCurve(to: .init(x: nL + nr, y: notchHeight), control: .init(x: nL, y: notchHeight))
            p.addLine(to: .init(x: nR - nr, y: notchHeight))
            p.addQuadCurve(to: .init(x: nR, y: notchHeight - nr), control: .init(x: nR, y: notchHeight))
            p.addLine(to: .init(x: nR, y: nr))
            p.addQuadCurve(to: .init(x: nR + nr, y: 0), control: .init(x: nR, y: 0))
        }

        p.addLine(to: .init(x: rect.maxX, y: 0))
        p.addLine(to: .init(x: rect.maxX, y: rect.maxY - cr))
        p.addQuadCurve(to: .init(x: rect.maxX - cr, y: rect.maxY), control: .init(x: rect.maxX, y: rect.maxY))
        p.addLine(to: .init(x: cr, y: rect.maxY))
        p.addQuadCurve(to: .init(x: 0, y: rect.maxY - cr), control: .init(x: 0, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

extension Color {
    init(hex: String) {
        var n: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: .alphanumerics.inverted)).scanHexInt64(&n)
        self.init(.sRGB, red: Double((n >> 16) & 0xFF) / 255, green: Double((n >> 8) & 0xFF) / 255, blue: Double(n & 0xFF) / 255)
    }
}
