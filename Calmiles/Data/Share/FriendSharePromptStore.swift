import Foundation
import SwiftUI

/// Soft “share with friends” prompt after a few days of meaningful use.
/// Prompt once; persist dismissed or shared. Also powers Settings Share.
@MainActor
final class FriendSharePromptStore: ObservableObject {
    static let shared = FriendSharePromptStore()

    private let defaults: UserDefaults

    private enum Keys {
        static let firstMeaningfulOpen = "calmiles.share.firstMeaningfulOpen"
        static let openDayKeys = "calmiles.share.openDayKeys"
        static let promptHandled = "calmiles.share.promptHandled" // dismissed or shared
        static let hasShared = "calmiles.share.hasShared"
    }

    @Published private(set) var shouldShowSoftPrompt = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Call when the user is in the main app (post-onboarding). Records today and evaluates prompt eligibility.
    func recordMeaningfulOpenIfNeeded() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITesting")
            || ProcessInfo.processInfo.arguments.contains("-UITestSkipOnboarding")
            || ProcessInfo.processInfo.arguments.contains("-UITestReset") {
            shouldShowSoftPrompt = false
            return
        }
        #endif

        let today = Self.dayKey(for: Date())
        var days = Set(defaults.stringArray(forKey: Keys.openDayKeys) ?? [])
        days.insert(today)
        defaults.set(Array(days).sorted(), forKey: Keys.openDayKeys)

        if defaults.object(forKey: Keys.firstMeaningfulOpen) == nil {
            defaults.set(Date(), forKey: Keys.firstMeaningfulOpen)
        }

        evaluatePromptEligibility()
    }

    func markShared() {
        defaults.set(true, forKey: Keys.hasShared)
        defaults.set(true, forKey: Keys.promptHandled)
        shouldShowSoftPrompt = false
    }

    func markDismissed() {
        defaults.set(true, forKey: Keys.promptHandled)
        shouldShowSoftPrompt = false
    }

    private func evaluatePromptEligibility() {
        guard defaults.bool(forKey: Keys.promptHandled) == false else {
            shouldShowSoftPrompt = false
            return
        }

        let days = defaults.stringArray(forKey: Keys.openDayKeys) ?? []
        let distinctDaysOK = days.count >= 3

        var calendarDaysOK = false
        if let first = defaults.object(forKey: Keys.firstMeaningfulOpen) as? Date {
            let start = Calendar.current.startOfDay(for: first)
            let today = Calendar.current.startOfDay(for: Date())
            let elapsed = Calendar.current.dateComponents([.day], from: start, to: today).day ?? 0
            calendarDaysOK = elapsed >= 3
        }

        shouldShowSoftPrompt = distinctDaysOK || calendarDaysOK
    }

    private static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
