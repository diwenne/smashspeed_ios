//
//  AuthenticationViewModel.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-04.
//

import Foundation
import FirebaseAuth
import Combine

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
            
            self.user = user
            self.authState = (user == nil) ? .signedOut : .signedIn
        }
    }
    
    var isSignedIn: Bool { user != nil }

    func signIn(email: String, password: String) {
        errorMessage = nil
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] _, error in
            self?.errorMessage = error?.localizedDescription
        }
    }

    func signUp(email: String, password: String) {
        errorMessage = nil
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] _, error in
            self?.errorMessage = error?.localizedDescription
        }
    }

    func signOut() {
        self.authState = .signedOut
        try? Auth.auth().signOut()
    }
}
