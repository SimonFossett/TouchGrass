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

    /// Cumulative steps since the app was first installed on this device.
    /// Continuously climbs every day and never resets.
    var totalStepScore: Int = 0

    private let dailyPedometer = CMPedometer()
    private let totalPedometer = CMPedometer()

    private init() {
        guard CMPedometer.isStepCountingAvailable() else {
            print("Step counting not available on this device")
            return
        }
        startDailyTracking()
        startTotalTracking()
        scheduleMidnightReset()
    }

    // MARK: - Daily steps (live, resets at midnight)

    private func startDailyTracking() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        dailyPedometer.startUpdates(from: startOfDay) { [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            // Take the higher of CMPedometer and any HealthKit sync persisted
            // today. Without this, a CMPedometer update would overwrite a
            // HealthKit value that was set after the user tapped Sync.
            let effective = max(steps, HealthKitManager.todaysPersistedSteps)
            DispatchQueue.main.async { self?.dailySteps = effective }
            Task { await UserService.shared.updateDailySteps(effective) }
        }
    }

    /// Schedules a one-shot timer that fires exactly at the next local midnight,
    /// resets dailySteps to 0, restarts the pedometer from the new day's start,
    /// and then schedules itself again for the following midnight.
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
            // Capture the final step count BEFORE resetting so streak logic
            // can compare against friends who haven't reached midnight yet.
            let finalSteps = self.dailySteps
            // Persist today's final count to the step grid before rolling over.
            if finalSteps > 0 {
                StepGridManager.shared.saveSteps(finalSteps, for: Date())
            }
            self.dailyPedometer.stopUpdates()
            self.dailySteps = 0
            Task {
                // Evaluate streak, archive yesterday's count, then reset to 0.
                await UserService.shared.updateStreakAtMidnight(myFinalSteps: finalSteps)
                await UserService.shared.resetDailySteps()
            }
            self.startDailyTracking()
            self.scheduleMidnightReset()
        }
    }

    // MARK: - Total step score (cumulative from install date, never decreases)

    private func startTotalTracking() {
        let origin = StepCounterManager.installDate

        // Immediate snapshot so the UI has data right away
        totalPedometer.queryPedometerData(from: origin, to: Date()) { [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            DispatchQueue.main.async { self?.totalStepScore = steps }
            Task { await UserService.shared.updateStepScore(steps) }
        }

        // Live updates keep the value climbing in real time
        totalPedometer.startUpdates(from: origin) { [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            DispatchQueue.main.async { self?.totalStepScore = steps }
            Task { await UserService.shared.updateStepScore(steps) }
        }
    }

    func stopTracking() {
        dailyPedometer.stopUpdates()
        totalPedometer.stopUpdates()
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

    // MARK: - Install date (set once, never changes)

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
