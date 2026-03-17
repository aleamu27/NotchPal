import Foundation
import EventKit
import AppKit

class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    private let eventStore = EKEventStore()
    @Published var events: [CalendarEvent] = []
    @Published var hasAccess = false
    @Published var selectedDate: Date = Date()

    struct CalendarEvent: Identifiable {
        let id = UUID()
        let title: String
        let startTime: Date
        let endTime: Date
        let isAllDay: Bool
        let color: String
    }

    private init() {
        checkAndRequestAccess()
    }

    func checkAndRequestAccess() {
        // Check current authorization status first
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .authorized, .fullAccess:
            // Already authorized - just fetch events
            DispatchQueue.main.async {
                self.hasAccess = true
                self.fetchEvents()
            }
        case .notDetermined:
            // Not yet determined - request access
            requestAccess()
        case .denied, .restricted:
            // Denied or restricted
            DispatchQueue.main.async {
                self.hasAccess = false
            }
        case .writeOnly:
            // Write only access - request full access
            requestAccess()
        @unknown default:
            requestAccess()
        }
    }

    private func requestAccess() {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.hasAccess = granted
                    if granted {
                        self?.fetchEvents()
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.hasAccess = granted
                    if granted {
                        self?.fetchEvents()
                    }
                }
            }
        }
    }

    func goToToday() {
        selectedDate = Date()
        fetchEvents()
    }

    func goToPreviousDay() {
        if let newDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) {
            selectedDate = newDate
            fetchEvents()
        }
    }

    func goToNextDay() {
        if let newDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) {
            selectedDate = newDate
            fetchEvents()
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        fetchEvents()
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    func fetchEvents() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let fetchedEvents = eventStore.events(matching: predicate)

        DispatchQueue.main.async { [weak self] in
            self?.events = fetchedEvents
                .sorted { $0.startDate < $1.startDate }
                .prefix(4)
                .map { event in
                    CalendarEvent(
                        title: event.title ?? "Ingen tittel",
                        startTime: event.startDate,
                        endTime: event.endDate,
                        isAllDay: event.isAllDay,
                        color: self?.colorHex(from: event.calendar?.color) ?? "007AFF"
                    )
                }
        }
    }

    // Legacy support
    var todayEvents: [CalendarEvent] {
        events
    }

    func fetchTodayEvents() {
        fetchEvents()
    }

    private func colorHex(from nsColor: NSColor?) -> String {
        guard let color = nsColor?.usingColorSpace(.deviceRGB) else { return "007AFF" }
        let r = Int(color.redComponent * 255)
        let g = Int(color.greenComponent * 255)
        let b = Int(color.blueComponent * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }

    func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
