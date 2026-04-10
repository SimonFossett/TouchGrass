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
    // Not observed by any view — mark ignored so @Observable doesn't add
    // thread-safety checks or tracking overhead for this internal handle.
    @ObservationIgnored
    private var observerQuery: HKObserverQuery?
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
        if hasRequestedAccess {
            fetchSteps()
            setupObserverQuery()
        }
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
                self?.setupObserverQuery()
            }
        }
    }

    // MARK: - Background Observer

    /// Registers an HKObserverQuery for step count and enables HealthKit
    /// background delivery. iOS will wake the app whenever new step data
    /// arrives — even when the app is fully backgrounded — so the leaderboard
    /// stays current without the user needing to open the app.
    private func setupObserverQuery() {
        guard isAvailable else { return }
        let stepType = HKQuantityType(.stepCount)

        // .immediate = deliver updates as soon as they are written to Health,
        // rather than batching them hourly or daily.
        healthStore.enableBackgroundDelivery(for: stepType, frequency: .immediate) { _, error in
            if let error { print("[HealthKit] Background delivery failed: \(error)") }
        }

        if let existing = observerQuery { healthStore.stop(existing); observerQuery = nil }

        // Fires once immediately and then every time step data changes.
        // The completionHandler MUST be called to tell HealthKit we handled the update.
        // HKObserverQuery fires on a background thread — dispatch to main before
        // calling fetchSteps, which mutates @Observable properties (isFetching, dailySteps).
        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else { completionHandler(); return }
            DispatchQueue.main.async { self?.fetchSteps(backgroundCompletion: completionHandler) }
        }
        observerQuery = query
        healthStore.execute(query)
    }

    // MARK: - Step Fetching

    /// Fetches today's step count from HealthKit.
    /// `backgroundCompletion` is the handler provided by HKObserverQuery when
    /// the app is woken in the background — it MUST be called so HealthKit
    /// knows we have processed the delivery.
    func fetchSteps(backgroundCompletion: (() -> Void)? = nil) {
        guard isAvailable else { backgroundCompletion?(); return }
        isFetching = true
        let stepType   = HKQuantityType(.stepCount)
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
                defer { backgroundCompletion?() }   // always signal HealthKit
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
    func syncToLeaderboard() {
        guard isAvailable, dailySteps > 0 else { return }
        let effective = max(dailySteps, StepCounterManager.shared.dailySteps)
        StepCounterManager.shared.dailySteps = effective
        Task { await UserService.shared.updateDailySteps(effective) }
    }
}
