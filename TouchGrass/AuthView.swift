//
//  AuthView.swift
//  TouchGrass
//

import SwiftUI

struct AuthView: View {
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var errorMessage = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo
            VStack(spacing: 8) {
                Image(systemName: "figure.walk.circle.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.green)
                Text("TouchGrass")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }

            Spacer()

            // Fields
            VStack(spacing: 14) {
                if isSignUp {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(10)
                }

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(10)

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(10)
            }
            .padding(.horizontal, 24)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Primary action
            Button(action: submit) {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(isSignUp ? "Create Account" : "Sign In")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(12)
            .disabled(isLoading)
            .padding(.horizontal, 24)

            // Toggle mode
            Button(action: {
                isSignUp.toggle()
                errorMessage = ""
            }) {
                Text(isSignUp
                     ? "Already have an account? Sign In"
                     : "Don't have an account? Sign Up")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }

            Spacer()
        }
    }

    private func submit() {
        errorMessage = ""

        if isSignUp {
            let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
            // Instant client-side checks before hitting the network
            guard trimmed.count >= 3 else {
                errorMessage = "Username must be at least 3 characters."
                return
            }
            guard trimmed.count <= 20 else {
                errorMessage = "Username must be 20 characters or fewer."
                return
            }
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
            guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
                errorMessage = "Username can only contain letters, numbers, and underscores."
                return
            }
            guard password.count >= 6 else {
                errorMessage = "Password must be at least 6 characters."
                return
            }
        }

        isLoading = true
        Task {
            do {
                if isSignUp {
                    let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
                    try await FirebaseManager.shared.signUp(
                        email: email, password: password, username: trimmed)
                } else {
                    try await FirebaseManager.shared.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    AuthView()
}
