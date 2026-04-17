//
//  StepCounterManager.swift
//  TouchGrass
//

import Foundation
import CoreMotion
import Observation

@Observable
class StepCounterManager {
    static let shared = StepCounterManager()

    /// Steps taken since midnight today.
    var dailySteps: Int = 0

    /// Running total of all steps ever recorded: baseScore + today's dailySteps.
    /// Always increases; never resets. Kept in sync with Firestore `stepScore`.
    var totalStepScore: Int = 0

    private let dailyPedometer = CMPedometer()

    // 24-slot cumulative snapshot: hourlyStepsSnapshot[h] = highest step count
    // recorded during hour h today. Written to Firestore so friends' charts can
    // plot real progression instead of a linear projection.
    @ObservationIgnored var hourlyStepsSnapshot: [Int] = Array(repeating: 0, count: 24)

    // MARK: - Base score (all completed days, persisted in UserDefaults)

    // The sum of every day's final step count up to (but not including) today.
    // Today's live contribution is always dailySteps, added on top at display time.
    private static let baseScoreKey = "stepScore_base"

    private var baseScore: Int {
        get { UserDefaults.standard.integer(forKey: Self.baseScoreKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.baseScoreKey)
            totalStepScore = newValue + dailySteps
        }
    }

    private init() {
        // Show the last-known total immediately before CMPedometer responds.
        totalStepScore = baseScore

        guard CMPedometer.isStepCountingAvailable() else {
            print("Step counting not available on this device")
            return
        }
        startDailyTracking()
        scheduleMidnightReset()
        // Pull the authoritative score from Firestore in case of reinstall or
        // first launch on a new device so no history is lost.
        Task { await syncScoreFromFirestore() }
    }

    // MARK: - Daily steps (live, resets at midnight)

    // Starts a live CMPedometer update stream from midnight that keeps dailySteps current.
    private func startDailyTracking() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        dailyPedometer.startUpdates(from: startOfDay) { [weak self] data, _ in
            guard let self, let steps = data?.numberOfSteps.intValue else { return }
            // Take the higher of CMPedometer and any HealthKit sync persisted today.
            let effective = max(steps, HealthKitManager.todaysPersistedSteps)
            let hour = Calendar.current.component(.hour, from: Date())
            DispatchQueue.main.async {
                self.dailySteps = effective
                self.totalStepScore = self.baseScore + effective
                self.hourlyStepsSnapshot[hour] = max(self.hourlyStepsSnapshot[hour], effective)
                let snapshot = self.hourlyStepsSnapshot
                let score   = self.totalStepScore
                Task {
                    await UserService.shared.updateDailySteps(effective, hourlySteps: snapshot)
                    await UserService.shared.updateStepScore(score)
                }
            }
        }
    }

    // Schedules a one-shot timer at the next local midnight to commit today's steps
    // into baseScore, persist to Firestore, and restart tracking for the new day.
    private func scheduleMidnightReset() {
        let calendar = Calendar.current
        guard let nextMidnight = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }

        let delay = nextMidnight.timeIntervalSinceNow
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }

            let finalDailySteps = self.dailySteps

            // Commit today into the base score BEFORE resetting dailySteps so
            // totalStepScore never dips — it transitions from
            // (oldBase + finalDaily) → (newBase + 0) = same value.
            let newBase = self.baseScore + finalDailySteps
            UserDefaults.standard.set(newBase, forKey: Self.baseScoreKey)

            // Persist today's final count to the local step grid.
            if finalDailySteps > 0 {
                StepGridManager.shared.saveSteps(finalDailySteps, for: Date())
            }

            self.dailyPedometer.stopUpdates()
            self.dailySteps = 0
            self.totalStepScore = newBase
            self.hourlyStepsSnapshot = Array(repeating: 0, count: 24)

            Task {
                // Archive the completed day's steps to Firestore step history.
                let yesterday = Calendar.current.date(
                    byAdding: .day, value: -1,
                    to: Calendar.current.startOfDay(for: Date())
                ) ?? Date()
                await UserService.shared.archiveDaySteps(finalDailySteps, for: yesterday)
                // Force-write the new committed base score to Firestore immediately.
                await UserService.shared.updateStepScore(newBase, force: true)
                await UserService.shared.updateStreakAtMidnight(myFinalSteps: finalDailySteps)
                await UserService.shared.resetDailySteps()
            }
            self.startDailyTracking()
            self.scheduleMidnightReset()
        }
    }

    // MARK: - Sync from Firestore on launch

    // Fetches the authoritative step score from Firestore and reconciles with the
    // local baseScore. Handles reinstalls or new devices where UserDefaults is empty.
    @MainActor
    private func syncScoreFromFirestore() async {
        guard let user = try? await UserService.shared.fetchCurrentUser() else { return }
        let firestoreTotal = user.stepScore
        let localTotal     = baseScore + dailySteps
        guard firestoreTotal > localTotal else { return }
        // Firestore is higher — attribute the difference to baseScore so today's
        // live dailySteps still adds correctly on top.
        let newBase = max(firestoreTotal - dailySteps, 0)
        UserDefaults.standard.set(newBase, forKey: Self.baseScoreKey)
        totalStepScore = newBase + dailySteps
    }

    // MARK: - Stop tracking

    // Stops the daily CMPedometer live-update stream.
    func stopTracking() {
        dailyPedometer.stopUpdates()
    }

    // MARK: - Hourly cumulative step data for today (used by the profile chart)

    /// Returns an array of (hour, cumulativeSteps) pairs from midnight up to and
    /// including the current hour. Each value is the total steps taken from
    /// midnight to the end of that hour, giving a monotonically increasing curve.
    func fetchHourlySteps() async -> [(hour: Int, steps: Int)] {
        guard CMPedometer.isStepCountingAvailable() else { return [] }
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let currentHour = calendar.component(.hour, from: now)
        let pedometer = CMPedometer()
        var results: [(hour: Int, steps: Int)] = []
        for hour in 0...currentHour {
            let periodEnd = min(
                calendar.date(byAdding: .hour, value: hour + 1, to: startOfDay) ?? now,
                now
            )
            let steps: Int = await withCheckedContinuation { continuation in
                pedometer.queryPedometerData(from: startOfDay, to: periodEnd) { data, _ in
                    continuation.resume(returning: data?.numberOfSteps.intValue ?? 0)
                }
            }
            results.append((hour: hour, steps: steps))
        }
        return results
    }

    // MARK: - Install date (retained for any legacy references)

    static var installDate: Date {
        let key = "app_install_date"
        if let stored = UserDefaults.standard.object(forKey: key) as? Date {
            return stored
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: key)
        return now
    }
}
