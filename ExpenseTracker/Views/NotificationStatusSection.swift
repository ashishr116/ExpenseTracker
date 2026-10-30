//
//  NotificationStatusSection.swift
//  ExpenseTracker
//

import SwiftUI
import UserNotifications

/// What the app knows about reminders: whether they are allowed, how many are scheduled, and the next one.
@Observable
final class NotificationStatus {
    var status: UNAuthorizationStatus?
    var scheduledCount = 0
    var nextReminder: (title: String, date: Date)?

    func refresh() async {
        let center = UNUserNotificationCenter.current()
        status = await center.notificationSettings().authorizationStatus

        let requests = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("due-") }
        scheduledCount = requests.count
        nextReminder = requests
            .compactMap { request -> (title: String, date: Date)? in
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                      let date = trigger.nextTriggerDate() else { return nil }
                return (request.content.title, date)
            }
            .min { $0.date < $1.date }
    }

    func requestAccess() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refresh()
    }
}

extension View {
    /// Keeps `model` up to date while this screen is showing: when it opens, shortly after (reminders are
    /// scheduled just after the app opens), and each time you come back to the app, for example from Settings.
    func trackNotificationStatus(_ model: NotificationStatus) -> some View {
        modifier(NotificationStatusTracker(model: model))
    }
}

private struct NotificationStatusTracker: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let model: NotificationStatus

    func body(content: Content) -> some View {
        content
            .task {
                await model.refresh()
                try? await Task.sleep(for: .seconds(2))
                await model.refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refresh() } }
            }
    }
}

/// Tells you whether due-date reminders can reach you.
///
/// - Allowed: shows how many are scheduled and when the next one goes off.
/// - Refused: explains, with a button to Settings.
/// - Never asked: a button to turn them on.
///
/// The screen showing it must call `trackNotificationStatus(_:)` with the same model.
struct NotificationStatusSection: View {
    let model: NotificationStatus

    var body: some View {
        switch model.status {
        case .denied:
            Section {
                Label("Reminders are off", systemImage: "bell.slash.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Notifications are turned off for this app, so due-date reminders can't reach you. Turn them on in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        case .notDetermined:
            Section {
                Label("Get due-date reminders", systemImage: "bell.badge")
                    .font(.headline)
                Text("Allow notifications so the app can remind you before an EMI or premium is due.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Turn On Reminders", systemImage: "bell") {
                    Task { await model.requestAccess() }
                }
            }
        case .authorized, .provisional, .ephemeral:
            Section {
                Label(
                    model.scheduledCount == 0
                        ? "Reminders are on"
                        : "Reminders are on · \(model.scheduledCount) scheduled",
                    systemImage: "bell.fill"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
                if let next = model.nextReminder {
                    Text("Next: \(next.title) on \(next.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        default:
            EmptyView()
        }
    }
}
