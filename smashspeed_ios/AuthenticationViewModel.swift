import Foundation
import FirebaseAuth
import Combine
import FirebaseStorage
import AuthenticationServices
import GoogleSignIn
import CryptoKit
import FirebaseFirestore

// --- THIS STRUCT IS MODIFIED ---
struct UserRecord: Equatable {
    var smashCount: Int
    var lastSmashMonth: String
}

@MainActor
class AuthenticationViewModel: NSObject, ObservableObject, ASAuthorizationControllerDelegate {
    
    enum AuthState {
        case unknown, signedIn, signedOut
    }
    
    @Published var authState: AuthState = .unknown
    @Published var user: User?
    @Published var userRecord: UserRecord?
    
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?
    private let db = Firestore.firestore()

    override init() {
        super.init()
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            
            self.user = user
            self.authState = (user == nil) ? .signedOut : .signedIn
            
            if let user = user {
                self.fetchUserRecord(for: user.uid)
            } else {
                self.userRecord = nil
            }
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
    
    // MARK: - Smash Count Logic
    
    func fetchUserRecord(for uid: String) {
        let userDocRef = db.collection("users").document(uid)
        
        userDocRef.getDocument { (document, error) in
            if let document = document, document.exists, let data = document.data() {
                let count = data["smashCount"] as? Int ?? -1
                let lastMonth = data["lastSmashMonth"] as? String ?? ""
                
                if count == -1 {
                    userDocRef.setData(["smashCount": 0, "lastSmashMonth": ""], merge: true)
                    self.userRecord = UserRecord(smashCount: 0, lastSmashMonth: "")
                } else {
                    self.userRecord = UserRecord(smashCount: count, lastSmashMonth: lastMonth)
                }
            } else {
                userDocRef.setData(["smashCount": 0, "lastSmashMonth": ""])
                self.userRecord = UserRecord(smashCount: 0, lastSmashMonth: "")
            }
        }
    }

    func incrementSmashCount() {
        guard var record = userRecord, let uid = user?.uid else { return }
        
        record.smashCount += 1
        self.userRecord = record
        
        let userDocRef = db.collection("users").document(uid)
        userDocRef.setData(["smashCount": record.smashCount], merge: true)
    }
    
    func checkAndResetMonthlyCount() {
        guard var record = userRecord, let uid = user?.uid else { return }
        
        let calendar = Calendar.current
        let currentMonthIdentifier = "month_\(calendar.component(.month, from: Date()))_year_\(calendar.component(.year, from: Date()))"
        
        if record.lastSmashMonth != currentMonthIdentifier {
            record.lastSmashMonth = currentMonthIdentifier
            record.smashCount = 0
            self.userRecord = record
            
            let userDocRef = db.collection("users").document(uid)
            userDocRef.setData([
                "smashCount": record.smashCount,
                "lastSmashMonth": record.lastSmashMonth
            ], merge: true)
        }
    }
    
    // MARK: - Account Management

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
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

extension String {
    func sha256() -> String {
        let inputData = Data(self.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
