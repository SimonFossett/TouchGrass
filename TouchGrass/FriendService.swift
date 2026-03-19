//
//  FriendService.swift
//  TouchGrass
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

class FriendService {
    static let shared = FriendService()
    private let db = Firestore.firestore()

    private init() {}

    /// Send a friend request from the current user to `toUID`.
    func sendRequest(to toUID: String) async throws {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        try await db.collection("friendRequests")
            .document("\(myUID)_\(toUID)")
            .setData([
                "fromUID": myUID,
                "toUID": toUID,
                "status": "pending",
                "createdAt": FieldValue.serverTimestamp()
            ])
    }

    /// Returns the current relationship status between the signed-in user and `userUID`.
    func status(for userUID: String) async -> FriendRequestStatus {
        guard let myUID = Auth.auth().currentUser?.uid else { return .none }

        // Outgoing request (I sent to them)
        if let outgoing = try? await db.collection("friendRequests")
            .document("\(myUID)_\(userUID)")
            .getDocument(),
           let status = outgoing.data()?["status"] as? String {
            return status == "accepted" ? .friends : .requested
        }

        // Incoming request (they sent to me)
        if let incoming = try? await db.collection("friendRequests")
            .document("\(userUID)_\(myUID)")
            .getDocument(),
           let status = incoming.data()?["status"] as? String {
            return status == "accepted" ? .friends : .requested
        }

        return .none
    }

    // MARK: - Incoming friend requests

    /// Fetch all users who have sent the current user a pending friend request.
    func incomingRequests() async throws -> [AppUser] {
        guard let myUID = Auth.auth().currentUser?.uid else { return [] }

        let snapshot = try await db.collection("friendRequests")
            .whereField("toUID", isEqualTo: myUID)
            .whereField("status", isEqualTo: "pending")
            .getDocuments()

        var users: [AppUser] = []
        for doc in snapshot.documents {
            guard let fromUID = doc.data()["fromUID"] as? String else { continue }
            if let user = try? await fetchUser(uid: fromUID) {
                users.append(user)
            }
        }
        return users
    }

    /// Accept a pending incoming friend request from `fromUID`.
    func acceptRequest(from fromUID: String) async throws {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        try await db.collection("friendRequests")
            .document("\(fromUID)_\(myUID)")
            .updateData(["status": "accepted"])
    }

    /// Decline a pending incoming friend request from `fromUID`.
    func denyRequest(from fromUID: String) async throws {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        try await db.collection("friendRequests")
            .document("\(fromUID)_\(myUID)")
            .updateData(["status": "declined"])
    }

    private func fetchUser(uid: String) async throws -> AppUser {
        let doc = try await db.collection("users").document(uid).getDocument()
        let username = doc.data()?["username"] as? String ?? "Unknown"
        let stepScore = doc.data()?["stepScore"] as? Int ?? 0
        return AppUser(id: uid, username: username, stepScore: stepScore)
    }

    /// Removes an accepted friendship. Deletes whichever friendRequests document
    /// links the two users (either direction). Both users' real-time listeners
    /// will fire, removing the friend from each other's list automatically.
    func removeFriend(_ friendUID: String) async throws {
        guard let myUID = Auth.auth().currentUser?.uid else { return }
        // The document could be stored in either direction — delete both and ignore
        // the "not found" error from whichever direction doesn't exist.
        async let a: Void = db.collection("friendRequests")
            .document("\(myUID)_\(friendUID)").delete()
        async let b: Void = db.collection("friendRequests")
            .document("\(friendUID)_\(myUID)").delete()
        _ = try await (a, b)
    }

    /// Returns UIDs of all confirmed friends of the current user.
    func friendUIDs() async throws -> [String] {
        guard let myUID = Auth.auth().currentUser?.uid else { return [] }

        let sent = try await db.collection("friendRequests")
            .whereField("fromUID", isEqualTo: myUID)
            .whereField("status", isEqualTo: "accepted")
            .getDocuments()

        let received = try await db.collection("friendRequests")
            .whereField("toUID", isEqualTo: myUID)
            .whereField("status", isEqualTo: "accepted")
            .getDocuments()

        return sent.documents.compactMap { $0.data()["toUID"] as? String }
             + received.documents.compactMap { $0.data()["fromUID"] as? String }
    }
}
