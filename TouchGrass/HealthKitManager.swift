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
    private static let accessKey = "healthkit_access_requested"

    private init() {
        hasRequestedAccess = UserDefaults.standard.bool(forKey: Self.accessKey)
        if hasRequestedAccess {
            fetchSteps()
        }
    }

    // MARK: - Authorization

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

    func fetchSteps() {
        guard isAvailable else { return }
        isFetching = true
        let stepType = HKQuantityType(.stepCount)
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: .strictStartDate
        )
        let query = HKStatisticsQuery(
            quantityType: stepType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum
        ) { [weak self] _, result, _ in
            let steps = Int(result?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            DispatchQueue.main.async {
                self?.dailySteps = steps
                self?.isFetching = false
            }
        }
        healthStore.execute(query)
    }

    // MARK: - Sync to leaderboard

    /// Takes the higher of HealthKit and CMPedometer steps, updates the local
    /// step counter, and pushes the value to Firebase so it shows on the leaderboard.
    func syncToLeaderboard() {
        guard isAvailable, dailySteps > 0 else { return }
        let effectiveSteps = max(dailySteps, StepCounterManager.shared.dailySteps)
        StepCounterManager.shared.dailySteps = effectiveSteps
        Task { await UserService.shared.updateDailySteps(effectiveSteps) }
    }
}
