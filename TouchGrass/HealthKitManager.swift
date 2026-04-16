//
//  HealthKitManager.swift
//  TouchGrass
//

import Foundation
import HealthKit
import Observation

@Observable
class HealthKitManager {
    static let shared = HealthKitManager()

    /// Whether HealthKit is available on this device (not available on iPad without paired Watch, or simulator).
    let isAvailable = HKHealthStore.isHealthDataAvailable()

    /// Whether the user has already gone through the authorization prompt at least once.
    var hasRequestedAccess: Bool

    /// Steps fetched from Apple Health for today (includes Apple Watch data).
    var dailySteps: Int = 0

    var isFetching = false

    private let healthStore = HKHealthStore()
    private static let accessKey            = "healthkit_access_requested"
    // Persisted so the HealthKit step count survives app restarts.
    private static let persistedStepsKey    = "hk_daily_steps"
    private static let persistedStepsDate   = "hk_daily_steps_date"

    private init() {
        hasRequestedAccess = UserDefaults.standard.bool(forKey: Self.accessKey)
        // Restore today's previously-synced HealthKit value immediately so the
        // metric card has data before the async fetch completes.
        let restored = Self.todaysPersistedSteps
        if restored > 0 { dailySteps = restored }
        if hasRequestedAccess { fetchSteps() }
    }

    // MARK: - Persisted step count (shared with StepCounterManager)

    /// Returns the HealthKit step count that was saved during the last sync
    /// today, or 0 if no sync has happened today.
    static var todaysPersistedSteps: Int {
        guard let saved = UserDefaults.standard.object(forKey: persistedStepsDate) as? Date,
              Calendar.current.isDateInToday(saved) else { return 0 }
        return UserDefaults.standard.integer(forKey: persistedStepsKey)
    }

    // MARK: - Authorization

    // Prompts the user for HealthKit read access to step count and heart rate, then fetches today's steps.
    func requestAuthorization() {
        guard isAvailable else { return }
        let stepType = HKQuantityType(.stepCount)
        let heartRateType = HKQuantityType(.heartRate)
        let typesToRead: Set<HKQuantityType> = [stepType, heartRateType]
        healthStore.requestAuthorization(toShare: [], read: typesToRead) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.hasRequestedAccess = true
                UserDefaults.standard.set(true, forKey: Self.accessKey)
                self?.fetchSteps()
            }
        }
    }

    // MARK: - Step Fetching

    // Queries HealthKit for today's cumulative step count and persists the result to UserDefaults.
    func fetchSteps() {
        guard isAvailable else { return }
        isFetching = true
        let stepType  = HKQuantityType(.stepCount)
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate  = HKQuery.predicateForSamples(
            withStart: startOfDay, end: Date(), options: .strictStartDate
        )
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, _ in
            let steps = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            DispatchQueue.main.async {
                guard let self else { return }
                self.dailySteps = steps
                self.isFetching = false
                guard steps > 0 else { return }
                // Persist so the value survives the next app launch.
                UserDefaults.standard.set(steps, forKey: Self.persistedStepsKey)
                UserDefaults.standard.set(startOfDay, forKey: Self.persistedStepsDate)
                // Sync is called here — after the fetch completes — fixing the
                // race condition that existed when both were called back-to-back.
                self.syncToLeaderboard()
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Sync to leaderboard

    /// Takes the higher of HealthKit and CMPedometer steps, updates the local
    /// step counter, and pushes the value to Firebase so it shows on the leaderboard.
    // Takes the higher of HealthKit and CMPedometer step counts and pushes it to Firestore for the leaderboard.
    func syncToLeaderboard() {
        guard isAvailable, dailySteps > 0 else { return }
        let effective = max(dailySteps, StepCounterManager.shared.dailySteps)
        StepCounterManager.shared.dailySteps = effective
        Task { await UserService.shared.updateDailySteps(effective) }
    }
}
