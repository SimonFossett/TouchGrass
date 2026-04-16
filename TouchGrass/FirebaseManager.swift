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
    case emailNotFound

    var errorDescription: String? {
        switch self {
        case .usernameTaken:
            return "That username is already taken. Please choose another."
        case .invalidUsername:
            return "Username must be 3–20 characters and can only contain letters, numbers, and underscores."
        case .emailNotFound:
            return "No account found with that email address. Please check and try again."
        }
    }
}

// MARK: - Validation

private let usernameRegex = /^[a-zA-Z0-9_]{3,20}$/

@Observable
class FirebaseManager {
    static let shared = FirebaseManager()

    var isAuthenticated = false
    var showAuthTransitionSplash = false
    var currentUID: String? { Auth.auth().currentUser?.uid }

    @ObservationIgnored private var authListener: AuthStateDidChangeListenerHandle?
    // Prevents the auth state listener from flipping isAuthenticated during
    // the sign-up flow, which creates and possibly deletes an account before
    // the username check completes.
    @ObservationIgnored private var suppressAuthStateChanges = false

    private init() {
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self, !self.suppressAuthStateChanges else { return }
            self.isAuthenticated = user != nil
        }
    }

    // Creates a new Firebase Auth account, verifies username availability, and writes the user document.
    @MainActor
    func signUp(email: String, password: String, username: String) async throws {
        // Validate format before touching the network
        guard username.wholeMatch(of: usernameRegex) != nil else {
            throw AuthError.invalidUsername
        }

        // Suppress the auth listener for the duration of sign-up. Without this,
        // createUser immediately fires isAuthenticated = true and ContentView
        // navigates away before the username check can show an error.
        suppressAuthStateChanges = true
        defer { suppressAuthStateChanges = false }

        // Create the Auth account first so the user is authenticated — Firestore
        // rules require auth for reads, so the username check must happen after this.
        let result = try await Auth.auth().createUser(withEmail: email, password: password)

        do {
            // Now authenticated — check username availability and write profile.
            guard try await !UserService.shared.isUsernameTaken(username) else {
                try await result.user.delete()
                throw AuthError.usernameTaken
            }

            try await Firestore.firestore().collection("users").document(result.user.uid).setData([
                "uid": result.user.uid,
                "email": email.lowercased(),
                "username": username,
                "usernameLower": username.lowercased(),
                "stepScore": 0,
                "createdAt": FieldValue.serverTimestamp()
            ])

            // Sign-up fully succeeded — show transition splash then navigate to the main app.
            showAuthTransitionSplash = true
            isAuthenticated = true
        } catch {
            // Clean up the auth account if anything after creation fails.
            try? await result.user.delete()
            throw error
        }
    }

    // Signs the user in with email and password, showing the transition splash on success.
    func signIn(email: String, password: String) async throws {
        showAuthTransitionSplash = true
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            showAuthTransitionSplash = false
            throw error
        }
    }

    // Verifies the email exists in Firestore then triggers a Firebase Auth password-reset email.
    func sendPasswordReset(email: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()

        // Verify the account exists before calling Firebase Auth, which silently
        // succeeds for any email when email-enumeration protection is enabled.
        let snapshot = try await Firestore.firestore()
            .collection("users")
            .whereField("email", isEqualTo: normalizedEmail)
            .limit(to: 1)
            .getDocuments()

        guard !snapshot.documents.isEmpty else {
            throw AuthError.emailNotFound
        }

        try await Auth.auth().sendPasswordReset(withEmail: normalizedEmail)
    }

    // Signs the current user out of Firebase Auth.
    func signOut() throws {
        try Auth.auth().signOut()
    }
}
