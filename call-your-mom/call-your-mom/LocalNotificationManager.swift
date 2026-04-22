//
//  LocalNotificationManager.swift
//  call-your-mom
//
//  Created by Codex on 4/21/26.
//

import Foundation
import UserNotifications

final class LocalNotificationManager {
    static let shared = LocalNotificationManager()

    static let lowHealthThreshold = 25.0
    private let lowHealthIdentifier = "low-health-alert"

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
        }
    }

    func scheduleLowHealthNotification(after timeInterval: TimeInterval) {
        guard timeInterval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Health is getting low"
        content.body = "Log a call soon to recharge your Tamagotchi."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timeInterval), repeats: false)
        let request = UNNotificationRequest(
            identifier: lowHealthIdentifier,
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [lowHealthIdentifier])
        center.add(request)
    }

    func clearLowHealthNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [lowHealthIdentifier])
    }
}
