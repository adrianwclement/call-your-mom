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

struct NotificationPreferences: Codable, Equatable {
    var dailyRemindersEnabled = true
    var reminderHour = 20
    var reminderMinute = 0
    var lowHealthAlertsEnabled = true
    var streakAlertsEnabled = true
    var messageAlertsEnabled = true
    var weeklySummaryEnabled = true

    private enum CodingKeys: String, CodingKey {
        case dailyRemindersEnabled
        case reminderHour
        case reminderMinute
        case lowHealthAlertsEnabled
        case streakAlertsEnabled
        case messageAlertsEnabled
        case weeklySummaryEnabled
    }

    init(
        dailyRemindersEnabled: Bool = true,
        reminderHour: Int = 20,
        reminderMinute: Int = 0,
        lowHealthAlertsEnabled: Bool = true,
        streakAlertsEnabled: Bool = true,
        messageAlertsEnabled: Bool = true,
        weeklySummaryEnabled: Bool = true
    ) {
        self.dailyRemindersEnabled = dailyRemindersEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
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
        defaultCallMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultCallMinutes) ?? 15
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

        let contacts = removingUntouchedStarterContacts(from: decoded.contacts)
        let preferredContactID = contacts.contains(where: { $0.id == decoded.preferredContactID })
            ? decoded.preferredContactID
            : contacts.first?.id
        let contactIDs = Set(contacts.map(\.id))
        let spriteContactAssignments = migratedSpriteContactAssignments(decoded.spriteContactAssignments)
            .filter { contactIDs.contains($0.value) }
        let defaultCallMinutes = min(max(decoded.defaultCallMinutes, 1), 240)
        let reminderHour = min(max(decoded.notificationPreferences.reminderHour, 0), 23)
        let reminderMinute = min(max(decoded.notificationPreferences.reminderMinute, 0), 59)

        return AppSettings(
            contacts: contacts,
            preferredContactID: preferredContactID,
            spriteContactAssignments: spriteContactAssignments,
            defaultCallMinutes: defaultCallMinutes,
            notificationPreferences: NotificationPreferences(
                dailyRemindersEnabled: decoded.notificationPreferences.dailyRemindersEnabled,
                reminderHour: reminderHour,
                reminderMinute: reminderMinute,
                lowHealthAlertsEnabled: decoded.notificationPreferences.lowHealthAlertsEnabled,
                streakAlertsEnabled: decoded.notificationPreferences.streakAlertsEnabled,
                messageAlertsEnabled: decoded.notificationPreferences.messageAlertsEnabled,
                weeklySummaryEnabled: decoded.notificationPreferences.weeklySummaryEnabled
            )
        )
    }

    static func save(_ settings: AppSettings) {
        let sanitizedSettings = AppSettings(
            contacts: settings.contacts,
            preferredContactID: settings.preferredContactID,
            spriteContactAssignments: migratedSpriteContactAssignments(settings.spriteContactAssignments),
            defaultCallMinutes: settings.defaultCallMinutes,
            notificationPreferences: settings.notificationPreferences
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
