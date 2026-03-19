//
//  FirebaseManager.swift
//  TouchGrass
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Observation

@Observable
class FirebaseManager {
    static let shared = FirebaseManager()

    var isAuthenticated = false
    var currentUID: String? { Auth.auth().currentUser?.uid }

    private var authListener: AuthStateDidChangeListenerHandle?

    private init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.isAuthenticated = user != nil
        }
    }

    func signUp(email: String, password: String, username: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        try await Firestore.firestore().collection("users").document(result.user.uid).setData([
            "uid": result.user.uid,
            "email": email,
            "username": username,
            "stepScore": 0,
            "createdAt": FieldValue.serverTimestamp()
        ])
    }

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }
}
