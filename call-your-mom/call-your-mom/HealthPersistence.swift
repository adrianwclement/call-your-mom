//
//  HealthPersistence.swift
//  call-your-mom
//
//  Created by Codex on 4/22/26.
//

import Foundation

enum HealthPersistence {
    private static let defaults = UserDefaults.standard
    private static let healthKey = "health.value"
    private static let updatedAtKey = "health.updatedAt"
    private static let callsLoggedKey = "health.callsLogged"

    static let defaultHealth = 68.0
    static let defaultCallsLogged = 1
    static let decayAmount = 3.0
    static let decayInterval: TimeInterval = 8.0
    static let decayPerSecond = decayAmount / decayInterval

    static func load() -> (health: Double, updatedAt: Date, callsLogged: Int) {
        let storedHealth = defaults.object(forKey: healthKey) as? Double ?? defaultHealth
        let storedUpdatedAt = defaults.object(forKey: updatedAtKey) as? Date ?? Date()
        let storedCallsLogged = defaults.object(forKey: callsLoggedKey) as? Int ?? defaultCallsLogged
        return (storedHealth, storedUpdatedAt, storedCallsLogged)
    }

    static func save(health: Double, updatedAt: Date, callsLogged: Int) {
        defaults.set(health, forKey: healthKey)
        defaults.set(updatedAt, forKey: updatedAtKey)
        defaults.set(callsLogged, forKey: callsLoggedKey)
    }

    static func decayedHealth(from health: Double, since updatedAt: Date, now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(updatedAt))
        return max(health - elapsed * decayPerSecond, 0)
    }
}
