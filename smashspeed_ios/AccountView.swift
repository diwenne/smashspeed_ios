//
//  AccountView.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-04.
//


import SwiftUI
import FirebaseAuth

// MARK: - Account Tab

struct AccountView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    
    var body: some View {
        NavigationStack {
            VStack {
                // The view now directly checks if a user exists.
                // The initial loading state is handled by ContentView.
                if let user = viewModel.user {
                    LoggedInView(user: user) {
                        viewModel.signOut()
                    }
                } else {
                    LoggedOutView()
                }
            }
            .navigationTitle("Account")
        }
    }
}

// A view to display when the user is logged in.
struct LoggedInView: View {
    let user: User
    let signOutAction: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "person.crop.circle.fill.badge.checkmark")
                .font(.system(size: 100))
                .foregroundColor(.green)
            
            Text("You are logged in as:")
                .font(.headline)
            
            Text(user.email ?? "No email found")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Sign Out", role: .destructive, action: signOutAction)
                .buttonStyle(.bordered)
                .padding()
        }
    }
}

// A view to display when the user is logged out.
struct LoggedOutView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "person.crop.circle.fill.badge.xmark")
                .font(.system(size: 100))
                .foregroundColor(.red)
            
            Text("Please sign in to continue")
                .font(.headline)
            
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .textFieldStyle(.roundedBorder)
            
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
            
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            
            VStack {
                Button("Sign In") {
                    viewModel.signIn(email: email, password: password)
                }
                .buttonStyle(.borderedProminent)
                
                Button("Create Account") {
                    viewModel.signUp(email: email, password: password)
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding()
    }
}

// This is the single source of truth for the AuthenticationViewModel.
@MainActor
class AuthenticationViewModel: ObservableObject {
    
    // Enum to manage the different states of authentication.
    enum AuthState {
        case unknown, signedIn, signedOut
    }
    
    @Published var authState: AuthState = .unknown
    @Published var user: User?
    @Published var errorMessage: String?
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        // Listen for changes to the user's login state.
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            
            // --- MODIFICATION: Add an artificial delay to see the loading screen ---
            // This Task ensures the loading screen is visible for at least 2 seconds.
            // This is for demonstration purposes and can be removed for production.
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                self.user = user
                // Update the authState after the delay.
                self.authState = (user == nil) ? .signedOut : .signedIn
            }
        }
    }
    
    var isSignedIn: Bool { user != nil }

    func signIn(email: String, password: String) {
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] _, error in
            self?.errorMessage = error?.localizedDescription
        }
    }

    func signUp(email: String, password: String) {
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] _, error in
            self?.errorMessage = error?.localizedDescription
        }
    }

    func signOut() {
        // When signing out, immediately go back to the signed-out state
        // without showing the loading screen again.
        self.authState = .signedOut
        try? Auth.auth().signOut()
    }
}
