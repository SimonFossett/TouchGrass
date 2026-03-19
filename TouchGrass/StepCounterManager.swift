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
    }

    // MARK: - Daily steps (live, resets at midnight)

    private func startDailyTracking() {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        dailyPedometer.startUpdates(from: startOfDay) { [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            DispatchQueue.main.async { self?.dailySteps = steps }
            // Keep Firestore in sync so friends see today's steps on the leaderboard
            Task { await UserService.shared.updateDailySteps(steps) }
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
