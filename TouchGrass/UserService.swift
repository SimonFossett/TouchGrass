//
//  UserService.swift
//  TouchGrass
//

import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore

struct AppUser: Identifiable {
    let id: String      // Firebase UID
    let username: String
    var stepScore: Int
    var dailySteps: Int = 0
    var dailyStreak: Int = 0
}

class UserService {
    static let shared = UserService()
    private let db = Firestore.firestore()

    // Minimum interval between Firestore writes for step fields.
    // 5 s gives friends near-real-time visibility without hammering Firestore.
    private let stepWriteInterval: TimeInterval = 5
    private var lastStepScoreWrite: Date = .distantPast
    private var lastDailyStepsWrite: Date = .distantPast

    private init() {}

    /// Search platform users whose username starts with `query` (case-insensitive).
    /// Excludes the currently signed-in user from results.
    func searchUsers(query: String) async throws -> [AppUser] {
        guard !query.isEmpty else { return [] }
        let lower = query.lowercased()

        let snapshot = try await db.collection("users")
            .whereField("usernameLower", isGreaterThanOrEqualTo: lower)
            .whereField("usernameLower", isLessThan: lower + "\u{f8ff}")
            .order(by: "usernameLower")
            .limit(to: 20)
            .getDocuments()

        let currentUID = Auth.auth().currentUser?.uid
        return snapshot.documents.compactMap { doc -> AppUser? in
            guard doc.documentID != currentUID,
                  let username = doc.data()["username"] as? String else { return nil }
            return AppUser(
                id: doc.documentID,
                username: username,
                stepScore: doc.data()["stepScore"] as? Int ?? 0
            )
        }
    }

    /// Returns the currently signed-in user's profile data from Firestore.
    func fetchCurrentUser() async throws -> AppUser? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let doc = try await db.collection("users").document(uid).getDocument()
        guard let username = doc.data()?["username"] as? String else { return nil }
        return AppUser(
            id: uid,
            username: username,
            stepScore: doc.data()?["stepScore"] as? Int ?? 0,
            dailySteps: doc.data()?["dailySteps"] as? Int ?? 0,
            dailyStreak: doc.data()?["dailyStreak"] as? Int ?? 0
        )
    }

    /// Pushes the user's latest step count up to Firestore so friends can see it.
    /// Writes are throttled to at most once every 5 seconds unless `force` is true.
    func updateStepScore(_ steps: Int, force: Bool = false) async {
        guard force || Date().timeIntervalSince(lastStepScoreWrite) >= stepWriteInterval else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).updateData(["stepScore": steps])
            lastStepScoreWrite = Date()
        } catch {
            print("[UserService] updateStepScore failed: \(error)")
        }
    }

    /// Pushes the user's daily step count to Firestore for leaderboard comparisons.
    /// Also writes `dailyStepsDate` (yyyy-MM-dd in local time) so readers can
    /// detect stale values from a previous day and treat them as zero.
    /// Writes are throttled to at most once every 30 seconds.
    func updateDailySteps(_ steps: Int, hourlySteps: [Int] = []) async {
        guard Date().timeIntervalSince(lastDailyStepsWrite) >= stepWriteInterval else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let today = Self.todayDateString()
        var update: [String: Any] = [
            "dailySteps":     steps,
            "dailyStepsDate": today
        ]
        if !hourlySteps.isEmpty {
            update["hourlySteps"]     = hourlySteps
            update["hourlyStepsDate"] = today
        }
        do {
            try await db.collection("users").document(uid).updateData(update)
            lastDailyStepsWrite = Date()
        } catch {
            print("[UserService] updateDailySteps failed: \(error)")
        }
    }

    /// yyyy-MM-dd string in the device's local calendar — used to detect
    /// whether a Firestore dailySteps value belongs to the current day.
    static func todayDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    // Returns the previous calendar day as a yyyy-MM-dd string in the device's local time zone.
    static func yesterdayDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return fmt.string(from: yesterday)
    }

    /// Archives `steps` under the "yyyy-MM-dd" key for `date` in the user's
    /// `stepHistory` Firestore map. Only overwrites if the new value is higher,
    /// matching the behaviour of the local StepGridManager. Called once per day
    /// at midnight with the completed day's final step count.
    func archiveDaySteps(_ steps: Int, for date: Date) async {
        guard steps > 0 else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let key = fmt.string(from: date)
        let ref = db.collection("users").document(uid)
        do {
            _ = try await db.runTransaction { transaction, _ in
                let snap = try? transaction.getDocument(ref)
                let existing = (snap?.data()?["stepHistory"] as? [String: Int])?[key] ?? 0
                if steps > existing {
                    transaction.updateData(["stepHistory.\(key)": steps], forDocument: ref)
                }
                return nil
            }
        } catch {
            print("[UserService] archiveDaySteps failed: \(error)")
        }
    }

    /// Uploads all locally-stored step history to Firestore `stepHistory` once.
    /// This makes every historical day visible to friends viewing the monthly grid.
    /// Exits immediately on subsequent calls (flag persists in UserDefaults).
    /// Only the higher of local vs cloud is kept for each date, so it's safe to
    /// call even if the cloud already has partial data.
    func backfillStepHistoryIfNeeded() async {
        let flagKey = "stepHistory_backfilled_v1"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let localData = StepGridManager.shared.allStepData()
        guard !localData.isEmpty else {
            UserDefaults.standard.set(true, forKey: flagKey)
            return
        }

        let doc = try? await db.collection("users").document(uid).getDocument()
        let cloudHistory = doc?.data()?["stepHistory"] as? [String: Int] ?? [:]

        var updates: [String: Any] = [:]
        for (dateStr, localSteps) in localData where localSteps > (cloudHistory[dateStr] ?? 0) {
            updates["stepHistory.\(dateStr)"] = localSteps
        }

        if !updates.isEmpty {
            do {
                try await db.collection("users").document(uid).updateData(updates)
            } catch {
                print("[UserService] backfillStepHistoryIfNeeded failed: \(error)")
                return // don't mark done — retry next launch
            }
        }
        UserDefaults.standard.set(true, forKey: flagKey)
    }

    /// Resets the current user's daily steps to 0 in Firestore.
    /// Bypasses the normal write throttle — intended for use only at midnight.
    func resetDailySteps() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).updateData([
                "dailySteps":     0,
                "dailyStepsDate": Self.todayDateString()
            ])
            lastDailyStepsWrite = Date()
        } catch {
            print("[UserService] resetDailySteps failed: \(error)")
        }
    }

    /// Changes the current user's username if it isn't already taken.
    func changeUsername(to newUsername: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "UserService", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }
        let trimmed = newUsername.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            throw NSError(domain: "UserService", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Username must be at least 3 characters"])
        }
        let taken = try await isUsernameTaken(trimmed)
        guard !taken else {
            throw NSError(domain: "UserService", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Username is already taken"])
        }
        try await db.collection("users").document(uid).updateData([
            "username": trimmed,
            "usernameLower": trimmed.lowercased()
        ])
    }

    /// Returns true if the given username is already in use by another account.
    /// Comparison is case-insensitive via the usernameLower field.
    func isUsernameTaken(_ username: String) async throws -> Bool {
        let snapshot = try await db.collection("users")
            .whereField("usernameLower", isEqualTo: username.lowercased())
            .limit(to: 1)
            .getDocuments()
        return !snapshot.isEmpty
    }

    /// Writes the user's current GPS coordinates to Firestore so friends can see them on the map.
    func updateLocation(_ coordinate: CLLocationCoordinate2D) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).updateData([
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude
            ])
        } catch {
            print("[UserService] updateLocation failed: \(error)")
        }
    }
}
