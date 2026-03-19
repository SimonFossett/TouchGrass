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
    var overallStreak: Int = 0
}

class UserService {
    static let shared = UserService()
    private let db = Firestore.firestore()

    private init() {}

    /// Search platform users whose username starts with `query` (case-insensitive).
    /// Excludes the currently signed-in user from results.
    func searchUsers(query: String) async throws -> [AppUser] {
        guard !query.isEmpty else { return [] }
        let lower = query.lowercased()

        let snapshot = try await db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: lower)
            .whereField("username", isLessThan: lower + "\u{f8ff}")
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
            dailyStreak: doc.data()?["dailyStreak"] as? Int ?? 0,
            overallStreak: doc.data()?["overallStreak"] as? Int ?? 0
        )
    }

    /// Pushes the user's latest step count up to Firestore so friends can see it.
    func updateStepScore(_ steps: Int) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).updateData(["stepScore": steps])
        } catch {
            print("[UserService] updateStepScore failed: \(error)")
        }
    }

    /// Pushes the user's daily step count to Firestore for leaderboard comparisons.
    func updateDailySteps(_ steps: Int) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(uid).updateData(["dailySteps": steps])
        } catch {
            print("[UserService] updateDailySteps failed: \(error)")
        }
    }

    /// Returns true if the given username is already in use by another account.
    func isUsernameTaken(_ username: String) async throws -> Bool {
        let snapshot = try await db.collection("users")
            .whereField("username", isEqualTo: username)
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
