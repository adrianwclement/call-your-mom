//
//  SettingsPersistence.swift
//  call-your-mom
//
//  Created by Ben Cerbin, Adrian Clement, and Dylan O'Connor on 4/21/26.
//

import Foundation

struct AppContact: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct NotificationPreferences: Codable, Equatable {
    var dailyRemindersEnabled = true
    var reminderHour = 20
    var lowHealthAlertsEnabled = true
    var streakAlertsEnabled = true
    var messageAlertsEnabled = true
    var weeklySummaryEnabled = true
}

struct AppSettings: Codable, Equatable {
    var contacts: [AppContact]
    var preferredContactID: UUID?
    var defaultCallMinutes: Int
    var notificationPreferences: NotificationPreferences
}

enum SettingsPersistence {
    private static let defaults = UserDefaults.standard
    private static let storageKey = "settings.appSettings"

    private static let fallbackContacts = [
        AppContact(name: "Mom"),
        AppContact(name: "Dad")
    ]

    static let defaultSettings = AppSettings(
        contacts: fallbackContacts,
        preferredContactID: fallbackContacts.first?.id,
        defaultCallMinutes: 15,
        notificationPreferences: NotificationPreferences()
    )

    static func load() -> AppSettings {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            save(defaultSettings)
            return defaultSettings
        }

        let contacts = decoded.contacts
        let preferredContactID = contacts.contains(where: { $0.id == decoded.preferredContactID })
            ? decoded.preferredContactID
            : contacts.first?.id
        let defaultCallMinutes = min(max(decoded.defaultCallMinutes, 1), 240)
        let reminderHour = min(max(decoded.notificationPreferences.reminderHour, 0), 23)

        return AppSettings(
            contacts: contacts,
            preferredContactID: preferredContactID,
            defaultCallMinutes: defaultCallMinutes,
            notificationPreferences: NotificationPreferences(
                dailyRemindersEnabled: decoded.notificationPreferences.dailyRemindersEnabled,
                reminderHour: reminderHour,
                lowHealthAlertsEnabled: decoded.notificationPreferences.lowHealthAlertsEnabled,
                streakAlertsEnabled: decoded.notificationPreferences.streakAlertsEnabled,
                messageAlertsEnabled: decoded.notificationPreferences.messageAlertsEnabled,
                weeklySummaryEnabled: decoded.notificationPreferences.weeklySummaryEnabled
            )
        )
    }

    static func save(_ settings: AppSettings) {
        guard let encoded = try? JSONEncoder().encode(settings) else { return }
        defaults.set(encoded, forKey: storageKey)
    }
}
