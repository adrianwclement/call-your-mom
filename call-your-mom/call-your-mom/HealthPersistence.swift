//
//  HealthPersistence.swift
//  call-your-mom
//
//  Created by Ben Cerbin, Adrian Clement, and Dylan O'Connor on 4/21/26.
//

import Foundation

enum HealthPersistence {
    private static let defaults = UserDefaults.standard
    private static let hasInitializedKey = "health.hasInitialized"
    private static let healthKey = "health.value"
    private static let updatedAtKey = "health.updatedAt"
    private static let callsLoggedKey = "health.callsLogged"
    private static let spriteHealthStatesKey = "health.spriteStates"

    static let defaultHealth = 100.0
    static let defaultCallsLogged = 0

    #if DEBUG
    static let decayAmount = 3.0
    static let decayInterval: TimeInterval = 8.0
    #else
    static let decayAmount = 100.0
    static let decayInterval: TimeInterval = 72 * 60 * 60
    #endif

    static let decayPerSecond = decayAmount / decayInterval

    static func load() -> (health: Double, updatedAt: Date, callsLogged: Int) {
        let now = Date()

        // First launch should start full and stamp a baseline persisted state.
        guard defaults.bool(forKey: hasInitializedKey) else {
            defaults.set(true, forKey: hasInitializedKey)
            defaults.set(defaultHealth, forKey: healthKey)
            defaults.set(now, forKey: updatedAtKey)
            defaults.set(defaultCallsLogged, forKey: callsLoggedKey)
            return (defaultHealth, now, defaultCallsLogged)
        }

        let rawHealth = defaults.object(forKey: healthKey) as? Double ?? defaultHealth
        let clampedHealth = rawHealth.isFinite ? min(max(rawHealth, 0), 100) : defaultHealth
        let rawUpdatedAt = defaults.object(forKey: updatedAtKey) as? Date ?? now
        let saneUpdatedAt = rawUpdatedAt > now ? now : rawUpdatedAt
        let storedCallsLogged = max(defaults.object(forKey: callsLoggedKey) as? Int ?? defaultCallsLogged, 0)
        return (clampedHealth, saneUpdatedAt, storedCallsLogged)
    }

    static func save(health: Double, updatedAt: Date, callsLogged: Int) {
        defaults.set(health, forKey: healthKey)
        defaults.set(updatedAt, forKey: updatedAtKey)
        defaults.set(callsLogged, forKey: callsLoggedKey)
    }

    static func loadCallsLogged() -> Int {
        let loaded = load()
        return loaded.callsLogged
    }

    static func saveCallsLogged(_ callsLogged: Int) {
        defaults.set(max(callsLogged, 0), forKey: callsLoggedKey)
    }

    static func loadSpriteState(for spriteID: String, now: Date = Date()) -> SpriteHealthState {
        let canonicalSpriteID = canonicalSpriteID(spriteID)
        return loadSpriteStates()[canonicalSpriteID] ?? SpriteHealthState(spriteID: canonicalSpriteID, updatedAt: now)
    }

    static func saveSpriteState(_ state: SpriteHealthState) {
        var states = loadSpriteStates()
        let canonicalSpriteID = canonicalSpriteID(state.spriteID)
        states[canonicalSpriteID] = SpriteHealthState(
            spriteID: canonicalSpriteID,
            health: state.health,
            updatedAt: state.updatedAt,
            isActivated: state.isActivated,
            isHibernating: state.isHibernating
        )

        saveSpriteStates(states)
    }

    static func decayedHealth(from health: Double, since updatedAt: Date, now: Date) -> Double {
        guard health.isFinite else { return defaultHealth }
        let elapsed = max(0, now.timeIntervalSince(updatedAt))
        let clampedHealth = min(max(health, 0), 100)
        return max(clampedHealth - elapsed * decayPerSecond, 0)
    }

    private static func loadSpriteStates() -> [String: SpriteHealthState] {
        guard
            let data = defaults.data(forKey: spriteHealthStatesKey),
            let states = try? JSONDecoder().decode([String: SpriteHealthState].self, from: data)
        else {
            return [:]
        }

        let migratedStates = migratedSpriteStates(states)
        if migratedStates != states {
            saveSpriteStates(migratedStates)
        }
        return migratedStates
    }

    private static func saveSpriteStates(_ states: [String: SpriteHealthState]) {
        guard let encoded = try? JSONEncoder().encode(states) else { return }
        defaults.set(encoded, forKey: spriteHealthStatesKey)
    }

    private static func canonicalSpriteID(_ spriteID: String) -> String {
        switch spriteID {
        case "t1":
            return "slime"
        case "t2":
            return "cecil"
        default:
            return spriteID
        }
    }

    private static func migratedSpriteStates(_ states: [String: SpriteHealthState]) -> [String: SpriteHealthState] {
        var migrated: [String: SpriteHealthState] = [:]
        for (spriteID, state) in states {
            let canonicalID = canonicalSpriteID(spriteID)
            let normalizedState = SpriteHealthState(
                spriteID: canonicalID,
                health: state.health,
                updatedAt: state.updatedAt,
                isActivated: state.isActivated,
                isHibernating: state.isHibernating
            )

            if migrated[canonicalID] == nil || canonicalID == spriteID {
                migrated[canonicalID] = normalizedState
            }
        }
        return migrated
    }
}

struct SpriteHealthState: Codable, Equatable {
    let spriteID: String
    var health: Double
    var updatedAt: Date
    var isActivated: Bool
    var isHibernating: Bool

    init(
        spriteID: String,
        health: Double = HealthPersistence.defaultHealth,
        updatedAt: Date = Date(),
        isActivated: Bool = false,
        isHibernating: Bool = false
    ) {
        self.spriteID = spriteID
        self.health = health.isFinite ? min(max(health, 0), 100) : HealthPersistence.defaultHealth
        self.updatedAt = updatedAt
        self.isActivated = isActivated
        self.isHibernating = isHibernating
    }
}
