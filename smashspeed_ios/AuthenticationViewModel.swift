//
//  AuthenticationViewModel.swift
//  smashspeed_ios
//
//  Created by Diwen Huang on 2025-07-04.
//

import Foundation
import FirebaseAuth
import Combine
import FirebaseStorage
import AuthenticationServices

@MainActor
class AuthenticationViewModel: NSObject, ObservableObject, ASAuthorizationControllerDelegate {
    
    // Enum to manage the different states of authentication.
    enum AuthState {
        case unknown, signedIn, signedOut
    }
    
    @Published var authState: AuthState = .unknown
    @Published var user: User?
    @Published var errorMessage: String?
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    override init() {
        super.init()
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
    
    func signInWithApple() {
        let nonce = UUID().uuidString
        currentNonce = nonce
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce.sha256()
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let nonce = currentNonce else {
                fatalError("Invalid state: A login callback was received, but no login request was sent.")
            }
            guard let appleIDToken = appleIDCredential.identityToken else {
                print("Unable to fetch identity token")
                return
            }
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                print("Unable to serialize token string from data: \(appleIDToken.debugDescription)")
                return
            }

            let credential = OAuthProvider.appleCredential(withIDToken: idTokenString,
                                                         rawNonce: nonce,
                                                         fullName: appleIDCredential.fullName)
            
            Auth.auth().signIn(with: credential) { [weak self] (authResult, error) in
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                // User is signed in
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        errorMessage = error.localizedDescription
    }


    func signOut() {
        self.authState = .signedOut
        try? Auth.auth().signOut()
    }


    func deleteAccount() {
        Auth.auth().currentUser?.delete { error in
            if let error = error {
                // Handle the error (e.g., user needs to re-authenticate)
                self.errorMessage = error.localizedDescription
                print("Error deleting account: \(error.localizedDescription)")
            } else {
                // The account was deleted successfully. The authState will update automatically.
                print("Account successfully deleted.")
            }
        }
    }

    @Published var infoMessage: String?
    
    func sendPasswordReset(for email: String) {
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.infoMessage = "If an account exists for this email, a reset link has been sent."
                }
            }
        }
    }
    
    func updatePassword(to newPassword: String, completion: @escaping (Bool, String) -> Void) {
        Auth.auth().currentUser?.updatePassword(to: newPassword) { error in
            DispatchQueue.main.async {
                if let error = error {
                    // Handle errors, like needing a recent sign-in
                    completion(false, error.localizedDescription)
                } else {
                    completion(true, "Password successfully updated!")
                }
            }
        }
    }

}

