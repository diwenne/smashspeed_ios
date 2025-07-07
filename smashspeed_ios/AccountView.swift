//
//  AccountView.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-04.
//

import SwiftUI
import FirebaseAuth
import Combine

// MARK: - Account Tab Main View

struct AccountView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    
    var body: some View {
        NavigationStack {
            // Use a ZStack to place a background color
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                // Main content switcher
                switch viewModel.authState {
                case .unknown:
                    ProgressView().scaleEffect(1.5)
                case .signedIn:
                    if let user = viewModel.user {
                        LoggedInView(user: user) {
                            viewModel.signOut()
                        }
                    }
                case .signedOut:
                    // The new, cleaner authentication view
                    AuthView()
                }
            }
            .navigationTitle(viewModel.authState == .signedIn ? "My Account" : "Welcome")
        }
    }
}

// MARK: - Logged In View

struct LoggedInView: View {
    let user: User
    let signOutAction: () -> Void
    
    private var memberSince: String {
        user.metadata.creationDate?.formatted(date: .long, time: .omitted) ?? "N/A"
    }
    
    var body: some View {
        // Use a List for a clean, standard iOS look.
        List {
            // Profile Header Section
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill.badge.checkmark")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading) {
                        Text(user.email ?? "No email found")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("Member since \(memberSince)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Account Actions Section
            Section {
                Button("Sign Out", role: .destructive, action: signOutAction)
            }
        }
    }
}


// MARK: - Authentication Flow Views

struct AuthView: View {
    @State private var isSigningUp = false

    var body: some View {
        VStack {
            // App Logo
            VStack {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)
                Text("SmashSpeed")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            .padding(.vertical, 30)

            // --- FIX: Use a ZStack to contain both forms for a smooth animation ---
            ZStack {
                // Sign In Form
                SignInForm(isSigningUp: $isSigningUp)
                    // Move off-screen to the left when signing up
                    .offset(x: isSigningUp ? -UIScreen.main.bounds.width : 0)
                    .opacity(isSigningUp ? 0 : 1)

                // Create Account Form
                CreateAccountForm(isSigningUp: $isSigningUp)
                    // Start off-screen to the right and move in
                    .offset(x: isSigningUp ? 0 : UIScreen.main.bounds.width)
                    .opacity(isSigningUp ? 1 : 0)
            }
            // Apply a spring animation to the ZStack's contents when `isSigningUp` changes.
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isSigningUp)
            
            Spacer()
        }
        .padding()
    }
}

struct SignInForm: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Binding var isSigningUp: Bool
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Sign In to Your Account")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.bottom)

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
            
            SecureField("Password", text: $password)
                .textContentType(.password)
            
            if let error = viewModel.errorMessage {
                Text(error).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
            }
            
            Button { viewModel.signIn(email: email, password: password) } label: {
                Text("Sign In").fontWeight(.bold).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            
            Button("Don't have an account? Sign Up") {
                isSigningUp = true
            }
            .font(.footnote)
            .tint(.accentColor)
            .padding(.top)
        }
        .textFieldStyle(RoundedBorderTextFieldStyle())
    }
}

struct CreateAccountForm: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Binding var isSigningUp: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Create a New Account")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.bottom)
                
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
            
            SecureField("Password", text: $password)
                .textContentType(.newPassword)
            
            SecureField("Confirm Password", text: $confirmPassword)
                .textContentType(.newPassword)
            
            if let error = viewModel.errorMessage {
                Text(error).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
            }
            
            Button {
                if password == confirmPassword {
                    viewModel.signUp(email: email, password: password)
                } else {
                    viewModel.errorMessage = "Passwords do not match."
                }
            } label: {
                Text("Create Account").fontWeight(.bold).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            
            Button("Already have an account? Sign In") {
                isSigningUp = false
            }
            .font(.footnote)
            .tint(.accentColor)
            .padding(.top)
        }
        .textFieldStyle(RoundedBorderTextFieldStyle())
    }
}

