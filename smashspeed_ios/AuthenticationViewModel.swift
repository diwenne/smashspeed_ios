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
import GoogleSignIn
import CryptoKit // Import CryptoKit for SHA256

@MainActor
class AuthenticationViewModel: NSObject, ObservableObject, ASAuthorizationControllerDelegate {
    
    // Enum to manage the different states of authentication.
    enum AuthState {
        case unknown, signedIn, signedOut
    }
    
    @Published var authState: AuthState = .unknown
    @Published var user: User?
    @Published var errorMessage: String?
    @Published var infoMessage: String?

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
        infoMessage = nil
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] _, error in
            self?.errorMessage = error?.localizedDescription
        }
    }

    func signUp(email: String, password: String) {
        errorMessage = nil
        infoMessage = nil
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] _, error in
            self?.errorMessage = error?.localizedDescription
        }
    }
    
    // MARK: - Apple Sign-In
    
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
                errorMessage = "Unable to fetch identity token from Apple."
                return
            }
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                errorMessage = "Unable to serialize Apple token string."
                return
            }

            let credential = OAuthProvider.appleCredential(withIDToken: idTokenString,
                                                         rawNonce: nonce,
                                                         fullName: appleIDCredential.fullName)
            
            Auth.auth().signIn(with: credential) { [weak self] (authResult, error) in
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        errorMessage = error.localizedDescription
    }

    // MARK: - Google Sign-In
    
    func signInWithGoogle() {
        errorMessage = nil
        infoMessage = nil
        
        guard let presentingViewController = UIApplication.shared.topViewController() else {
            errorMessage = "Could not find a view controller to present from."
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { [weak self] signInResult, error in
            guard let self = self else { return }
            guard error == nil else {
                self.errorMessage = error?.localizedDescription
                return
            }
            guard let user = signInResult?.user,
                  let idToken = user.idToken?.tokenString else {
                self.errorMessage = "Could not retrieve Google ID token."
                return
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                             accessToken: user.accessToken.tokenString)
            
            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - Account Management

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        self.authState = .signedOut
        try? Auth.auth().signOut()
    }

    func deleteAccount() {
        Auth.auth().currentUser?.delete { error in
            if let error = error {
                self.errorMessage = error.localizedDescription
                print("Error deleting account: \(error.localizedDescription)")
            } else {
                print("Account successfully deleted.")
            }
        }
    }
    
    func sendPasswordReset(for email: String) {
        errorMessage = nil
        infoMessage = nil
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
                    completion(false, error.localizedDescription)
                } else {
                    completion(true, "Password successfully updated!")
                }
            }
        }
    }
}

// Helper extension to find the top view controller.
extension UIApplication {
    func topViewController() -> UIViewController? {
        let keyWindow = connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows
            .filter({ $0.isKeyWindow }).first
        
        var topController = keyWindow?.rootViewController
        while let presentedViewController = topController?.presentedViewController {
            topController = presentedViewController
        }
        return topController
    }
}

// --- ADDED BACK TO FIX ERROR ---
// This extension provides the SHA256 hashing function required for Apple Sign-In's nonce.
extension String {
    func sha256() -> String {
        let inputData = Data(self.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
