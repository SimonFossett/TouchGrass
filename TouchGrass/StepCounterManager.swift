//
//  StepCounterManager.swift
//  TouchGrass
//

import Foundation
import CoreMotion
import Observation

@Observable
class StepCounterManager {
    private let pedometer = CMPedometer()

    var steps: Int = 0

    init() {
        startTracking()
    }

    func startTracking() {
        guard CMPedometer.isStepCountingAvailable() else {
            print("Step counting not available")
            return
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())

        pedometer.startUpdates(from: startOfDay) { data, error in
            if let data = data {
                DispatchQueue.main.async {
                    self.steps = data.numberOfSteps.intValue
                }
            }
        }
    }

    func stopTracking() {
        pedometer.stopUpdates()
    }
}
