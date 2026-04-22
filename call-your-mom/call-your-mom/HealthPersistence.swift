//
//  HealthPersistence.swift
//  call-your-mom
//
//  Created by Codex on 4/22/26.
//

import Foundation

enum HealthPersistence {
    private static let defaults = UserDefaults.standard
    private static let hasInitializedKey = "health.hasInitialized"
    private static let healthKey = "health.value"
    private static let updatedAtKey = "health.updatedAt"
    private static let callsLoggedKey = "health.callsLogged"

    static let defaultHealth = 100.0
    static let defaultCallsLogged = 1
    static let decayAmount = 3.0
    static let decayInterval: TimeInterval = 8.0
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

    static func decayedHealth(from health: Double, since updatedAt: Date, now: Date) -> Double {
        guard health.isFinite else { return defaultHealth }
        let elapsed = max(0, now.timeIntervalSince(updatedAt))
        let clampedHealth = min(max(health, 0), 100)
        return max(clampedHealth - elapsed * decayPerSecond, 0)
    }
}
