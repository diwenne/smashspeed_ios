import SwiftUI
import FirebaseAuth
import Combine
import CryptoKit
import AuthenticationServices

// MARK: - Account Tab Main View

struct AccountView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    
    var body: some View {
        NavigationStack {
            // Use a ZStack to place the glassmorphism background.
            ZStack {
                // 1. A monochromatic blue aurora background to match the onboarding.
                Color(.systemBackground).ignoresSafeArea()
                
                Circle()
                    .fill(Color.blue.opacity(0.8))
                    .blur(radius: 150)
                    .offset(x: -150, y: -200)

                Circle()
                    .fill(Color.blue.opacity(0.5))
                    .blur(radius: 180)
                    .offset(x: 150, y: 150)
                
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
        ScrollView {
            VStack(spacing: 30) {
                // Profile Header Section on a Glass Panel
                VStack(spacing: 20) {
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
                    Divider()
                    Button("Sign Out", role: .destructive, action: signOutAction)
                }
                .padding(30)
                .background(GlassPanel())
                .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
            }
            .padding()
            .padding(.top, 20)
        }
    }
}


// MARK: - Authentication Flow Views

struct AuthView: View {
    @State private var isSigningUp = false

    var body: some View {
        VStack(spacing: 30) {
            // App Logo
            VStack {
                Image("AppIconPreview")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .shadow(color: .blue.opacity(0.4), radius: 10, y: 5)

                Text("Smashspeed")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }

            // Authentication Forms on a Glass Panel
            VStack {
                ZStack {
                    SignInForm(isSigningUp: $isSigningUp)
                        .offset(x: isSigningUp ? -UIScreen.main.bounds.width : 0)
                        .opacity(isSigningUp ? 0 : 1)

                    CreateAccountForm(isSigningUp: $isSigningUp)
                        .offset(x: isSigningUp ? 0 : UIScreen.main.bounds.width)
                        .opacity(isSigningUp ? 1 : 0)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isSigningUp)
            }
            .padding(30)
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
            
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
        VStack(spacing: 20) {
            Text("Sign In to Your Account")
                .font(.title3)
                .fontWeight(.bold)

            ModernTextField(title: "Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
            
            ModernTextField(title: "Password", text: $password, isSecure: true)
                .textContentType(.password)
            
            if let error = viewModel.errorMessage {
                Text(error).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
            }
            
            Button { viewModel.signIn(email: email, password: password) } label: {
                Text("Sign In").fontWeight(.bold).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            
            SignInWithAppleButton()
                .frame(height: 50)
                .onTapGesture {
                    viewModel.signInWithApple()
                }

            Button("Don't have an account? Sign Up") {
                isSigningUp = true
            }
            .font(.footnote)
            .tint(.accentColor)
            .padding(.top)
        }
    }
}

struct CreateAccountForm: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Binding var isSigningUp: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var hasAcceptedTerms = false

    private var isFormValid: Bool {
        !email.isEmpty && !password.isEmpty && password == confirmPassword && hasAcceptedTerms
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create a New Account")
                .font(.title3)
                .fontWeight(.bold)
                
            ModernTextField(title: "Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
            
            ModernTextField(title: "Password", text: $password, isSecure: true)
                .textContentType(.newPassword)
            
            ModernTextField(title: "Confirm Password", text: $confirmPassword, isSecure: true)
                .textContentType(.newPassword)

            // --- Start of Corrected Code ---
            HStack(alignment: .top, spacing: 12) { // 1. Use .top alignment
                Button(action: {
                    hasAcceptedTerms.toggle()
                }) {
                    Image(systemName: hasAcceptedTerms ? "checkmark.square.fill" : "square")
                        .font(.headline) // Matched size to be closer to text
                        .foregroundColor(hasAcceptedTerms ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)

                Text("I have read and agree to the [Terms of Service](https://smashspeed.ca/terms-of-service) and [Privacy Policy](https://smashspeed.ca/privacy-policy).")
                    .font(.footnote)
                    // 2. This modifier prevents the text from being cut off and allows it to wrap
                    .fixedSize(horizontal: false, vertical: true)
            }
            // --- End of Corrected Code ---
            
            if let error = viewModel.errorMessage {
                Text(error).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
            }
            
            Button {
                guard password == confirmPassword else {
                    viewModel.errorMessage = "Passwords do not match."
                    return
                }
                viewModel.signUp(email: email, password: password)
            } label: {
                Text("Create Account").fontWeight(.bold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isFormValid)
            
            Button("Already have an account? Sign In") {
                isSigningUp = false
                viewModel.errorMessage = nil
            }
            .font(.footnote)
            .tint(.accentColor)
            .padding(.top)
        }
        .onChange(of: email) { _ in viewModel.errorMessage = nil }
        .onChange(of: password) { _ in viewModel.errorMessage = nil }
        .onChange(of: confirmPassword) { _ in viewModel.errorMessage = nil }
    }
}


// MARK: - Reusable Components

struct ModernTextField: View {
    let title: String
    @Binding var text: String
    var isSecure: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isSecure {
                SecureField(title, text: $text)
            } else {
                TextField(title, text: $text)
            }
            Divider()
        }
        .autocapitalization(.none)
    }
}

// Helper extension for creating a SHA256 hash
extension String {
    func sha256() -> String {
        let inputData = Data(self.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            return String(format: "%02x", $0)
        }.joined()
        return hashString
    }
}

struct SignInWithAppleButton: UIViewRepresentable {
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        return ASAuthorizationAppleIDButton(type: .signIn, style: .black)
    }
    
    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}
}
