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
    var phoneNumber: String?

    init(id: UUID = UUID(), name: String, phoneNumber: String? = nil) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
    }
}

enum CallReminderFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case everyOtherDay
    case weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily:
            return "Every day"
        case .everyOtherDay:
            return "Every other day"
        case .weekly:
            return "Once a week"
        }
    }
}

struct CallReminder: Codable, Identifiable, Equatable {
    let id: UUID
    var contactID: UUID
    var frequency: CallReminderFrequency
    var hour: Int
    var minute: Int
    var weekday: Int
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        contactID: UUID,
        frequency: CallReminderFrequency = .daily,
        hour: Int = 20,
        minute: Int = 0,
        weekday: Int = Calendar.current.component(.weekday, from: Date()),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.contactID = contactID
        self.frequency = frequency
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.weekday = min(max(weekday, 1), 7)
        self.isEnabled = isEnabled
    }
}

struct NotificationPreferences: Codable, Equatable {
    var dailyRemindersEnabled = true
    var reminderHour = 20
    var reminderMinute = 0
    var callReminders: [CallReminder] = []
    var lowHealthAlertsEnabled = true
    var streakAlertsEnabled = true
    var messageAlertsEnabled = true
    var weeklySummaryEnabled = true

    private enum CodingKeys: String, CodingKey {
        case dailyRemindersEnabled
        case reminderHour
        case reminderMinute
        case callReminders
        case lowHealthAlertsEnabled
        case streakAlertsEnabled
        case messageAlertsEnabled
        case weeklySummaryEnabled
    }

    init(
        dailyRemindersEnabled: Bool = true,
        reminderHour: Int = 20,
        reminderMinute: Int = 0,
        callReminders: [CallReminder] = [],
        lowHealthAlertsEnabled: Bool = true,
        streakAlertsEnabled: Bool = true,
        messageAlertsEnabled: Bool = true,
        weeklySummaryEnabled: Bool = true
    ) {
        self.dailyRemindersEnabled = dailyRemindersEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.callReminders = callReminders
        self.lowHealthAlertsEnabled = lowHealthAlertsEnabled
        self.streakAlertsEnabled = streakAlertsEnabled
        self.messageAlertsEnabled = messageAlertsEnabled
        self.weeklySummaryEnabled = weeklySummaryEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dailyRemindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .dailyRemindersEnabled) ?? true
        reminderHour = try container.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 20
        reminderMinute = try container.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        callReminders = try container.decodeIfPresent([CallReminder].self, forKey: .callReminders) ?? []
        lowHealthAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .lowHealthAlertsEnabled) ?? true
        streakAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .streakAlertsEnabled) ?? true
        messageAlertsEnabled = try container.decodeIfPresent(Bool.self, forKey: .messageAlertsEnabled) ?? true
        weeklySummaryEnabled = try container.decodeIfPresent(Bool.self, forKey: .weeklySummaryEnabled) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dailyRemindersEnabled, forKey: .dailyRemindersEnabled)
        try container.encode(reminderHour, forKey: .reminderHour)
        try container.encode(reminderMinute, forKey: .reminderMinute)
        try container.encode(callReminders, forKey: .callReminders)
        try container.encode(lowHealthAlertsEnabled, forKey: .lowHealthAlertsEnabled)
        try container.encode(streakAlertsEnabled, forKey: .streakAlertsEnabled)
        try container.encode(messageAlertsEnabled, forKey: .messageAlertsEnabled)
        try container.encode(weeklySummaryEnabled, forKey: .weeklySummaryEnabled)
    }
}

struct AppSettings: Codable, Equatable {
    var contacts: [AppContact]
    var preferredContactID: UUID?
    var spriteContactAssignments: [String: UUID]
    var defaultCallMinutes: Int
    var notificationPreferences: NotificationPreferences

    private enum CodingKeys: String, CodingKey {
        case contacts
        case preferredContactID
        case spriteContactAssignments
        case defaultCallMinutes
        case notificationPreferences
    }

    init(
        contacts: [AppContact],
        preferredContactID: UUID?,
        spriteContactAssignments: [String: UUID] = [:],
        defaultCallMinutes: Int,
        notificationPreferences: NotificationPreferences
    ) {
        self.contacts = contacts
        self.preferredContactID = preferredContactID
        self.spriteContactAssignments = spriteContactAssignments
        self.defaultCallMinutes = defaultCallMinutes
        self.notificationPreferences = notificationPreferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contacts = try container.decodeIfPresent([AppContact].self, forKey: .contacts) ?? []
        preferredContactID = try container.decodeIfPresent(UUID.self, forKey: .preferredContactID)
        spriteContactAssignments = try container.decodeIfPresent([String: UUID].self, forKey: .spriteContactAssignments) ?? [:]
        defaultCallMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultCallMinutes) ?? 0
        notificationPreferences = try container.decodeIfPresent(NotificationPreferences.self, forKey: .notificationPreferences) ?? NotificationPreferences()
    }
}

enum SettingsPersistence {
    private static let defaults = UserDefaults.standard
    private static let storageKey = "settings.appSettings"
    private static let defaultContactPromptKey = "settings.defaultContactPrompt.hasShown"

    static let defaultSettings = AppSettings(
        contacts: [],
        preferredContactID: nil,
        spriteContactAssignments: [:],
        defaultCallMinutes: 0,
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

        let contacts = removingUntouchedStarterContacts(from: decoded.contacts)
        let preferredContactID = contacts.contains(where: { $0.id == decoded.preferredContactID })
            ? decoded.preferredContactID
            : contacts.first?.id
        let contactIDs = Set(contacts.map(\.id))
        let spriteContactAssignments = migratedSpriteContactAssignments(decoded.spriteContactAssignments)
            .filter { contactIDs.contains($0.value) }
        let callReminders = decoded.notificationPreferences.callReminders
            .filter { contactIDs.contains($0.contactID) }
            .map(sanitizedReminder)
        let defaultCallMinutes = min(max(decoded.defaultCallMinutes, 0), 240)
        let reminderHour = min(max(decoded.notificationPreferences.reminderHour, 0), 23)
        let reminderMinute = min(max(decoded.notificationPreferences.reminderMinute, 0), 59)
        let migratedCallReminders = callReminders.isEmpty && decoded.notificationPreferences.dailyRemindersEnabled
            ? legacyReminder(contactID: preferredContactID, hour: reminderHour, minute: reminderMinute)
            : callReminders

        return AppSettings(
            contacts: contacts,
            preferredContactID: preferredContactID,
            spriteContactAssignments: spriteContactAssignments,
            defaultCallMinutes: defaultCallMinutes,
            notificationPreferences: NotificationPreferences(
                dailyRemindersEnabled: decoded.notificationPreferences.dailyRemindersEnabled,
                reminderHour: reminderHour,
                reminderMinute: reminderMinute,
                callReminders: migratedCallReminders,
                lowHealthAlertsEnabled: decoded.notificationPreferences.lowHealthAlertsEnabled,
                streakAlertsEnabled: decoded.notificationPreferences.streakAlertsEnabled,
                messageAlertsEnabled: decoded.notificationPreferences.messageAlertsEnabled,
                weeklySummaryEnabled: decoded.notificationPreferences.weeklySummaryEnabled
            )
        )
    }

    static func save(_ settings: AppSettings) {
        let contactIDs = Set(settings.contacts.map(\.id))
        let notificationPreferences = NotificationPreferences(
            dailyRemindersEnabled: settings.notificationPreferences.dailyRemindersEnabled,
            reminderHour: settings.notificationPreferences.reminderHour,
            reminderMinute: settings.notificationPreferences.reminderMinute,
            callReminders: settings.notificationPreferences.callReminders
                .filter { contactIDs.contains($0.contactID) }
                .map(sanitizedReminder),
            lowHealthAlertsEnabled: settings.notificationPreferences.lowHealthAlertsEnabled,
            streakAlertsEnabled: settings.notificationPreferences.streakAlertsEnabled,
            messageAlertsEnabled: settings.notificationPreferences.messageAlertsEnabled,
            weeklySummaryEnabled: settings.notificationPreferences.weeklySummaryEnabled
        )
        let sanitizedSettings = AppSettings(
            contacts: settings.contacts,
            preferredContactID: settings.preferredContactID,
            spriteContactAssignments: migratedSpriteContactAssignments(settings.spriteContactAssignments),
            defaultCallMinutes: settings.defaultCallMinutes,
            notificationPreferences: notificationPreferences
        )
        guard let encoded = try? JSONEncoder().encode(sanitizedSettings) else { return }
        defaults.set(encoded, forKey: storageKey)
    }

    static var hasPromptedForDefaultContact: Bool {
        defaults.bool(forKey: defaultContactPromptKey)
    }

    static func markPromptedForDefaultContact() {
        defaults.set(true, forKey: defaultContactPromptKey)
    }

    private static func migratedSpriteContactAssignments(_ assignments: [String: UUID]) -> [String: UUID] {
        var migrated = assignments
        for (legacyID, canonicalID) in ["t1": "slime", "t2": "cecil"] {
            if let legacyContactID = assignments[legacyID], assignments[canonicalID] == nil {
                migrated[canonicalID] = legacyContactID
            }
            migrated.removeValue(forKey: legacyID)
        }
        return migrated
    }

    private static func legacyReminder(contactID: UUID?, hour: Int, minute: Int) -> [CallReminder] {
        guard let contactID else { return [] }
        return [CallReminder(contactID: contactID, frequency: .daily, hour: hour, minute: minute)]
    }

    private static func sanitizedReminder(_ reminder: CallReminder) -> CallReminder {
        CallReminder(
            id: reminder.id,
            contactID: reminder.contactID,
            frequency: reminder.frequency,
            hour: reminder.hour,
            minute: reminder.minute,
            weekday: reminder.weekday,
            isEnabled: reminder.isEnabled
        )
    }

    private static func removingUntouchedStarterContacts(from contacts: [AppContact]) -> [AppContact] {
        guard contacts.count == 2 else { return contacts }

        let starterNames = Set(["Mom", "Dad"])
        let contactNames = Set(contacts.map(\.name))
        let allStarterContactsAreUntouched = contacts.allSatisfy { contact in
            contact.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }

        return contactNames == starterNames && allStarterContactsAreUntouched ? [] : contacts
    }
}
