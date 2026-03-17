//
//  UserService.swift
//  TouchGrass
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

struct AppUser: Identifiable {
    let id: String   // Firebase UID
    let username: String
    var stepScore: Int
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

    /// Pushes the user's latest step count up to Firestore so friends can see it.
    func updateStepScore(_ steps: Int) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try? await db.collection("users").document(uid).updateData(["stepScore": steps])
    }
}
