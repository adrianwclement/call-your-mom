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
    private let callReminderIdentifierPrefix = "call-reminder-"
    private let postCallLogIdentifier = "post-call-log-reminder"

    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
        }
    }

    func scheduleLowHealthNotification(after timeInterval: TimeInterval) {
        guard timeInterval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Health is getting low"
        content.body = "Feed your Tamagotchi soon to recharge its health."
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

    func scheduleDailyReminder(hour: Int, minute: Int = 0, contactName: String) {
        var components = DateComponents()
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)

        let content = UNMutableNotificationContent()
        content.title = "Daily call reminder"
        content.body = "Check in with \(contactName) today."
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

    func scheduleCallReminders(_ reminders: [CallReminder], contacts: [AppContact]) {
        clearCallReminderNotifications {
            let contactsByID = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0) })
            for reminder in reminders where reminder.isEnabled {
                guard let contact = contactsByID[reminder.contactID] else { continue }
                self.scheduleCallReminder(reminder, contactName: contact.name)
            }
        }
    }

    func clearCallReminderNotifications(completion: (() -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { [dailyReminderIdentifier, callReminderIdentifierPrefix] requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0 == dailyReminderIdentifier || $0.hasPrefix(callReminderIdentifierPrefix) }

            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            completion?()
        }
    }

    private func scheduleCallReminder(_ reminder: CallReminder, contactName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Call \(contactName)?"
        content.body = "Check in with \(contactName) when you have a minute."
        content.sound = .default

        let trigger: UNNotificationTrigger
        switch reminder.frequency {
        case .daily:
            var components = DateComponents()
            components.hour = reminder.hour
            components.minute = reminder.minute
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .weekly:
            var components = DateComponents()
            components.weekday = reminder.weekday
            components.hour = reminder.hour
            components.minute = reminder.minute
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .everyOtherDay:
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: nextEveryOtherDayInterval(hour: reminder.hour, minute: reminder.minute),
                repeats: true
            )
        }

        let request = UNNotificationRequest(
            identifier: "\(callReminderIdentifierPrefix)\(reminder.id.uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func nextEveryOtherDayInterval(hour: Int, minute: Int, now: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.second = 0

        let todayAtTime = calendar.date(from: components) ?? now
        let nextFire = todayAtTime > now
            ? todayAtTime
            : calendar.date(byAdding: .day, value: 1, to: todayAtTime) ?? now.addingTimeInterval(24 * 60 * 60)
        return max(60, nextFire.timeIntervalSince(now))
    }

    func schedulePostCallLogReminder(contactName: String, after timeInterval: TimeInterval) {
        guard timeInterval > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Log your call?"
        content.body = "Add your call with \(contactName) to keep your Tamagotchi healthy."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timeInterval), repeats: false)
        let request = UNNotificationRequest(
            identifier: postCallLogIdentifier,
            content: content,
            trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [postCallLogIdentifier])
        center.add(request)
    }

    func clearPostCallLogReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [postCallLogIdentifier])
    }
}
