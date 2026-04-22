//
//  LocalNotificationManager.swift
//  call-your-mom
//
//  Created by Ben Cerbin, Adrian Clement, and Dylan O'Connor on 4/21/26.
//

import Foundation
import UserNotifications

final class LocalNotificationManager {
    static let shared = LocalNotificationManager()

    static let lowHealthThreshold = 25.0
    private let lowHealthIdentifier = "low-health-alert"
    private let dailyReminderIdentifier = "daily-call-reminder"

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

    func scheduleDailyReminder(hour: Int, minute: Int = 0, contactName: String, minutes: Int) {
        var components = DateComponents()
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)

        let content = UNMutableNotificationContent()
        content.title = "Daily call reminder"
        content.body = "Check in with \(contactName) for about \(minutes) minute\(minutes == 1 ? "" : "s")."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: dailyReminderIdentifier,
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
        center.add(request)
    }

    func clearDailyReminderNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [dailyReminderIdentifier])
    }
}
