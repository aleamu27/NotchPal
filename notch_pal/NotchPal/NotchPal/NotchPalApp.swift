import SwiftUI
import AppKit
import Combine

@main
struct NotchPalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent multiple instances
        let runningApps = NSWorkspace.shared.runningApplications
        let isAlreadyRunning = runningApps.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }.count > 0

        if isAlreadyRunning {
            print("⚠️ NotchPal is already running! Exiting duplicate instance.")
            NSApp.terminate(nil)
            return
        }

        print("🚀 NotchPal starting...")

        // Detect notch dimensions
        if let screen = NSScreen.main {
            let safeArea = screen.safeAreaInsets
            print("📐 Safe area insets - top: \(safeArea.top), left: \(safeArea.left), right: \(safeArea.right)")

            // Calculate notch width from safe areas
            let screenWidth = screen.frame.width
            let notchWidth = screenWidth - safeArea.left - safeArea.right
            print("📐 Detected notch area width: \(notchWidth)")
        }

        NSApp.setActivationPolicy(.accessory)

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        setupMenuBar()
        setupNotchWindow()
        setupMouseMonitoring()

        print("✅ NotchPal ready")
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "NotchPal")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Logg inn på Spotify", action: #selector(openSpotifyAuth), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Logg ut", action: #selector(logout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Avslutt", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc func openSpotifyAuth() {
        SpotifyAuth.shared.startAuth()
    }

    @objc func logout() {
        SpotifyAuth.shared.logout()
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }
        SpotifyAuth.shared.handleCallback(url: url)
    }

    func setupNotchWindow() {
        guard let screen = NSScreen.main else { return }

        let windowWidth: CGFloat = 1000
        let windowHeight: CGFloat = 220

        let screenFrame = screen.frame
        let xPosition = screenFrame.midX - windowWidth / 2
        let yPosition = screenFrame.maxY - windowHeight

        let window = PassthroughWindow(
            contentRect: NSRect(x: xPosition, y: yPosition, width: windowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        let hostingView = PassthroughHostingView(rootView: NotchView())
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        window.contentView = hostingView

        window.orderFrontRegardless()
        self.window = window
    }

    func setupMouseMonitoring() {
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.checkMousePosition()
        }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.checkMousePosition()
            return event
        }
    }

    func checkMousePosition() {
        guard let screen = NSScreen.main else { return }

        let mouse = NSEvent.mouseLocation
        let screenTop = screen.frame.maxY
        let screenCenterX = screen.frame.midX

        let distanceFromCenter = abs(mouse.x - screenCenterX)
        let distanceFromTop = screenTop - mouse.y

        let isExpanded = NotchViewModel.shared.isExpanded

        let isNear: Bool
        if isExpanded {
            isNear = distanceFromCenter < 490 && distanceFromTop >= 0 && distanceFromTop < 210
        } else {
            isNear = distanceFromCenter < 95 && distanceFromTop >= 0 && distanceFromTop < 35
        }

        DispatchQueue.main.async { [weak self] in
            NotchViewModel.shared.isMouseNear = isNear
            // Only capture mouse events when mouse is near/in the notch
            self?.window?.ignoresMouseEvents = !isNear
        }
    }
}

// MARK: - ViewModel
class NotchViewModel: ObservableObject {
    static let shared = NotchViewModel()

    @Published var isMouseNear = false {
        didSet { updateState() }
    }
    @Published var isExpanded = false
    @Published var lockOpen = false  // Prevents auto-close (e.g., when mirror is active)

    private var collapseWork: DispatchWorkItem?

    private init() {}

    private func updateState() {
        collapseWork?.cancel()

        if isMouseNear && !isExpanded {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded = true
            }
        } else if !isMouseNear && isExpanded && !lockOpen {
            // Close immediately when mouse leaves (unless locked open)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded = false
            }
        }
    }

    func keepOpen() {
        collapseWork?.cancel()
    }
}

// MARK: - Passthrough Window (allows clicks through transparent areas)
class PassthroughWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override var mouseDownCanMoveWindow: Bool {
        return false
    }
}
