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
    /// Writes are throttled to at most once every 30 seconds.
    func updateStepScore(_ steps: Int) async {
        guard Date().timeIntervalSince(lastStepScoreWrite) >= stepWriteInterval else { return }
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
    func updateDailySteps(_ steps: Int) async {
        guard Date().timeIntervalSince(lastDailyStepsWrite) >= stepWriteInterval else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).updateData([
                "dailySteps":     steps,
                "dailyStepsDate": Self.todayDateString()
            ])
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

    static func yesterdayDateString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return fmt.string(from: yesterday)
    }

    /// Called at midnight with the user's FINAL step count for the day.
    /// Archives that count, determines if the user won 1st place among their
    /// friend group, and updates their dailyStreak accordingly.
    func updateStreakAtMidnight(myFinalSteps: Int) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let friendUIDs = (try? await FriendService.shared.friendUIDs()) ?? []
        let today     = Self.todayDateString()
        let yesterday = Self.yesterdayDateString()

        // Archive this user's final step count so friends who fire midnight
        // later can still read it even after this device resets to 0.
        try? await db.collection("users").document(uid).updateData([
            "previousDaySteps": myFinalSteps,
            "previousDayDate":  yesterday
        ])

        // Determine the highest step count among friends for yesterday.
        var maxFriendSteps = 0
        for fUID in friendUIDs {
            guard let doc = try? await db.collection("users").document(fUID).getDocument() else { continue }
            let data = doc.data() ?? [:]
            let storedDate = data["dailyStepsDate"] as? String ?? ""
            let steps: Int
            if storedDate == today {
                // Friend already reset for today — use their archived previous-day count.
                let prevDate = data["previousDayDate"] as? String ?? ""
                steps = prevDate == yesterday ? (data["previousDaySteps"] as? Int ?? 0) : 0
            } else {
                // Friend hasn't reset yet — their current dailySteps IS yesterday's final count.
                steps = data["dailySteps"] as? Int ?? 0
            }
            maxFriendSteps = max(maxFriendSteps, steps)
        }

        // Win = strictly most steps AND walked at least 1 step.
        // On a tie nobody wins (both lose streak).
        let won: Bool
        if friendUIDs.isEmpty {
            won = myFinalSteps > 0   // solo: reward any walking
        } else {
            won = myFinalSteps > 0 && myFinalSteps > maxFriendSteps
        }

        guard let myDoc = try? await db.collection("users").document(uid).getDocument() else { return }
        let currentStreak = myDoc.data()?["dailyStreak"] as? Int ?? 0
        let newStreak = won ? currentStreak + 1 : 0
        try? await db.collection("users").document(uid).updateData(["dailyStreak": newStreak])
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
