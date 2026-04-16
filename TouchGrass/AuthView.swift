//
//  AuthView.swift
//  TouchGrass
//

import SwiftUI

struct AuthView: View {
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var username = ""
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var showPasswordReset = false
    @State private var logoRotation: Double = 0
    @State private var resolvedFontName: String = "Billabong"
    @FocusState private var focusedField: AuthField?

    private enum AuthField { case username, email, password, confirmPassword }

    // Spins the app logo 360° with a short ease-in-out animation.
    private func spin() {
        withAnimation(.easeInOut(duration: 0.5)) { logoRotation += 360 }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo
            VStack(spacing: 12) {
                ZStack {
                    // Soft green glow ring
                    Circle()
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 118, height: 118)

                    // Background circle that adapts to light/dark mode
                    Circle()
                        .fill(Color(uiColor: .systemBackground))
                        .frame(width: 100, height: 100)
                        .shadow(color: Color.green.opacity(0.5), radius: 14, x: 0, y: 4)

                    // App icon — add image to Assets.xcassets as Image Set named "AppLogo"
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .rotationEffect(.degrees(logoRotation))
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                logoRotation += 360
                            }
                        }
                }
                Text("TouchGrass")
                    .font(.custom(resolvedFontName, size: 400))
                    .minimumScaleFactor(0.01)
                    .lineLimit(1)
                    .frame(width: 220)
            }

            Spacer()

            // Fields
            VStack(spacing: 14) {
                if isSignUp {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focusedField, equals: .username)
                        .padding()
                        .background(GlassBackground(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }

                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: .email)
                    .padding()
                    .background(GlassBackground(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                ZStack(alignment: .trailing) {
                    Group {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .focused($focusedField, equals: .password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding()
                    .padding(.trailing, 40)

                    Button(action: {
                        showPassword.toggle()
                        DispatchQueue.main.async { focusedField = .password }
                    }) {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .padding(.trailing, 12)
                }
                .background(GlassBackground(cornerRadius: 10))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                if isSignUp {
                    ZStack(alignment: .trailing) {
                        Group {
                            if showConfirmPassword {
                                TextField("Verify Password", text: $confirmPassword)
                            } else {
                                SecureField("Verify Password", text: $confirmPassword)
                            }
                        }
                        .focused($focusedField, equals: .confirmPassword)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding()
                        .padding(.trailing, 40)

                        Button(action: {
                            showConfirmPassword.toggle()
                            DispatchQueue.main.async { focusedField = .confirmPassword }
                        }) {
                            Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .padding(.trailing, 12)
                    }
                    .background(GlassBackground(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }

                if !isSignUp {
                    HStack {
                        Spacer()
                        Button("Forgot Password?") {
                            showPasswordReset = true
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                }
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
            Button(action: { spin(); submit() }) {
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
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color.green)
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                }
            )
            .foregroundColor(.white)
            .shadow(color: Color.green.opacity(0.4), radius: 8, y: 4)
            .disabled(isLoading)
            .padding(.horizontal, 24)

            // Toggle mode
            Button(action: {
                spin()
                isSignUp.toggle()
                errorMessage = ""
                confirmPassword = ""
                showPassword = false
                showConfirmPassword = false
            }) {
                Text(isSignUp
                     ? "Already have an account? Sign In"
                     : "Don't have an account? Sign Up")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }

            Spacer()
        }
        .onAppear {
            let candidates = ["Billabong", "Billabong-Regular", "BillabongRegular"]
            for candidate in candidates {
                if UIFont(name: candidate, size: 12) != nil {
                    resolvedFontName = candidate
                    break
                }
            }
        }
        .onChange(of: focusedField) { _, newField in
            if newField != nil { spin() }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetView(prefillEmail: email)
        }
    }

    // Validates the form fields then calls sign-up or sign-in via FirebaseManager.
    private func submit() {
        errorMessage = ""

        if isSignUp {
            let trimmed = username.trimmingCharacters(in: .whitespaces)
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
            guard password == confirmPassword else {
                errorMessage = "Passwords do not match."
                return
            }
        }

        isLoading = true
        Task {
            do {
                if isSignUp {
                    let trimmed = username.trimmingCharacters(in: .whitespaces)
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

// MARK: - Password Reset Sheet

struct PasswordResetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var isLoading = false
    @State private var didSend = false
    @State private var errorMessage = ""

    init(prefillEmail: String) {
        _email = State(initialValue: prefillEmail)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.rotation")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                VStack(spacing: 8) {
                    Text("Reset Password")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Enter your email and we'll send you a link to reset your password.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if didSend {
                    Label("Check your email for a reset link.", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.subheadline)
                        .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 14) {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding()
                            .background(GlassBackground(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }

                        Button(action: sendReset) {
                            Group {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Send Reset Email")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 12).fill(Color.green)
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                            }
                        )
                        .foregroundColor(.white)
                        .shadow(color: Color.green.opacity(0.4), radius: 8, y: 4)
                        .disabled(isLoading || email.isEmpty)
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // Sends a password-reset email and shows success or error feedback.
    private func sendReset() {
        errorMessage = ""
        isLoading = true
        Task {
            do {
                try await FirebaseManager.shared.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
                didSend = true
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
