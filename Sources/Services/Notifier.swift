import Foundation
import UserNotifications

/// macOS notifications. Permission is requested only when the person turns notifications on, never at launch;
/// without it, posting does nothing.
enum Notifier {
    /// Notification and hot key APIs need a real app bundle; tests and `swift run` don't have one.
    static var available: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    @discardableResult
    static func requestPermission() async -> Bool {
        guard available else { return false }
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func post(id: String, title: String, body: String, info: [String: String]) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = info
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
