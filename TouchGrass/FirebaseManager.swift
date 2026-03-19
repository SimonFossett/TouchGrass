//
//  FirebaseManager.swift
//  TouchGrass
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import Observation

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case usernameTaken
    case invalidUsername

    var errorDescription: String? {
        switch self {
        case .usernameTaken:
            return "That username is already taken. Please choose another."
        case .invalidUsername:
            return "Username must be 3–20 characters and can only contain letters, numbers, and underscores."
        }
    }
}

// MARK: - Validation

private let usernameRegex = /^[a-z0-9_]{3,20}$/

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
        // Validate format before touching the network
        guard username.wholeMatch(of: usernameRegex) != nil else {
            throw AuthError.invalidUsername
        }

        // Ensure the username is not already taken
        guard try await !UserService.shared.isUsernameTaken(username) else {
            throw AuthError.usernameTaken
        }

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

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }
}
