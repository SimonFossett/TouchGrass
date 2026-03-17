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
