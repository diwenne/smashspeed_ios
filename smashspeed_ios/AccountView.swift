import SwiftUI
import FirebaseAuth
import Combine
import CryptoKit
import AuthenticationServices

// MARK: - Account Tab Main View
struct AccountView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemBackground).ignoresSafeArea()
                Circle().fill(Color.blue.opacity(0.8)).blur(radius: 150).offset(x: -150, y: -200)
                Circle().fill(Color.blue.opacity(0.5)).blur(radius: 180).offset(x: 150, y: 150)
                
                // Main content switcher
                switch viewModel.authState {
                case .unknown: ProgressView().scaleEffect(1.5)
                case .signedIn:
                    if let user = viewModel.user {
                        LoggedInView(user: user, signOutAction: { viewModel.signOut() }, deleteAccountAction: { viewModel.deleteAccount() })
                    }
                case .signedOut: AuthView()
                }
            }
            .navigationTitle(viewModel.authState == .signedIn ? "My Account" : "Welcome")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        if let url = URL(string: "https://smashspeed.ca/#contact") { Link(destination: url) { Label("Contact Us", systemImage: "person.fill.questionmark") } }
                        if let url = URL(string: "https://smashspeed.ca/#faq") { Link(destination: url) { Label("FAQ", systemImage: "questionmark.circle.fill") } }
                        Divider()
                        if let url = URL(string: "https://smashspeed.ca/terms-of-service") { Link(destination: url) { Label("Terms of Service", systemImage: "doc.text.fill") } }
                        if let url = URL(string: "https://smashspeed.ca/privacy-policy") { Link(destination: url) { Label("Privacy Policy", systemImage: "shield.lefthalf.filled") } }
                    } label: { Image(systemName: "gearshape.fill").font(.title3).foregroundColor(.secondary) }
                }
            }
        }
    }
}

// MARK: - Logged In View
struct LoggedInView: View {
    let user: User
    let signOutAction: () -> Void
    let deleteAccountAction: () -> Void

    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    @State private var showOnboarding = false
    @State private var showDeleteAlert = false
    @State private var showChangePasswordSheet = false
    @State private var showSignOutAlert = false // State for sign-out alert
    
    private var memberSince: String { user.metadata.creationDate?.formatted(date: .long, time: .omitted) ?? "N/A" }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // --- Profile Header ---
                VStack(spacing: 20) {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill.badge.checkmark").font(.system(size: 60)).foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text(user.email ?? "No email found").font(.headline).fontWeight(.semibold)
                            Text("Member since \(memberSince)").font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }.glassPanelStyle()

                // --- App Settings ---
                VStack(alignment: .leading, spacing: 15) {
                    Text("Settings").font(.title2.bold()).padding(.bottom, 5)
                    Picker("Appearance", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }.pickerStyle(.segmented)
                    Divider()
                    Button { showOnboarding = true } label: { Label("View Tutorial", systemImage: "questionmark.circle.fill") }
                }.glassPanelStyle()

                // --- Community & Support ---
                VStack(alignment: .leading, spacing: 15) {
                    Text("Community & Support").font(.title2.bold()).padding(.bottom, 5)
                    if let url = URL(string: "https://smashspeed.ca") { Link(destination: url) { Label("Official Website", systemImage: "globe") } }
                    Divider()
                    if let url = URL(string: "https://instagram.com/smashspeedai") { Link(destination: url) { Label("Follow on Instagram", systemImage: "camera.fill") } }
                    Divider()
                    if let url = URL(string: "mailto:smashspeedai@gmail.com") { Link(destination: url) { Label("Contact Support", systemImage: "envelope.fill") } }
                }.glassPanelStyle()
                
                // --- Account Actions ---
                VStack(alignment: .leading, spacing: 15) {
                    Text("Account Actions").font(.title2.bold()).padding(.bottom, 5)
                    Button("Change Password", action: { showChangePasswordSheet = true })
                    Divider()
                    Button("Sign Out", role: .destructive, action: { showSignOutAlert = true }) // Triggers alert
                    Divider()
                    Button("Delete Account", role: .destructive, action: { showDeleteAlert = true })
                }.glassPanelStyle()
            }
            .padding().padding(.top, 20)
        }
        .sheet(isPresented: $showOnboarding) { OnboardingView(onComplete: { showOnboarding = false }) }
        .sheet(isPresented: $showChangePasswordSheet) { ChangePasswordView() }
        .alert("Delete Account", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive, action: deleteAccountAction)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Are you sure you want to delete your account? This action is permanent and cannot be undone.") }
        .alert("Are you sure you want to sign out?", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive, action: signOutAction)
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Change Password View
struct ChangePasswordView: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var feedbackMessage: String?
    @State private var isSuccess = false
    
    private var canSubmit: Bool { !newPassword.isEmpty && newPassword == confirmPassword }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ModernTextField(title: "New Password", text: $newPassword, isSecure: true)
                ModernTextField(title: "Confirm New Password", text: $confirmPassword, isSecure: true)
                if let feedbackMessage = feedbackMessage { Text(feedbackMessage).font(.caption).foregroundColor(isSuccess ? .green : .red).multilineTextAlignment(.center) }
                Button("Update Password") {
                    guard newPassword == confirmPassword else {
                        isSuccess = false; feedbackMessage = "Passwords do not match."
                        return
                    }
                    viewModel.updatePassword(to: newPassword) { success, message in
                        self.isSuccess = success; self.feedbackMessage = message
                        if success { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { dismiss() } }
                    }
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!canSubmit)
                Spacer()
            }
            .padding(30)
            .navigationTitle("Change Password")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: { dismiss() }) } }
        }
    }
}

// Custom ViewModifier for consistent panel styling
struct GlassPanelModifier: ViewModifier {
    func body(content: Content) -> some View { content.padding(30).background(GlassPanel()).clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous)) }
}
extension View {
    func glassPanelStyle() -> some View { self.modifier(GlassPanelModifier()) }
}

// MARK: - Authentication Flow Views
struct AuthView: View {
    @State private var isSigningUp = false
    var body: some View {
        VStack(spacing: 20) {
            VStack {
                ZStack {
                    SignInForm(isSigningUp: $isSigningUp).offset(x: isSigningUp ? -UIScreen.main.bounds.width : 0).opacity(isSigningUp ? 0 : 1)
                    CreateAccountForm(isSigningUp: $isSigningUp).offset(x: isSigningUp ? 0 : UIScreen.main.bounds.width).opacity(isSigningUp ? 1 : 0)
                }.animation(.spring(response: 0.5, dampingFraction: 0.8), value: isSigningUp)
            }
            .padding(30).background(GlassPanel()).clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
            
            Text("Sign in to access more features, customize settings, and track your progress over time.")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 25)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }.padding().padding(.top, 40)
    }
}

struct SignInForm: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Binding var isSigningUp: Bool
    @State private var email = ""
    @State private var password = ""
    
    var body: some View {
        VStack(spacing: 15) {
            Text("Sign In").font(.title2).fontWeight(.bold)
            ModernTextField(title: "Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
            ModernTextField(title: "Password", text: $password, isSecure: true).textContentType(.password)
            
            HStack {
                Spacer()
                Button("Forgot Password?") { viewModel.sendPasswordReset(for: email) }.font(.footnote)
            }.padding(.bottom, -5)
            
            if let error = viewModel.errorMessage { Text(error).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
            } else if let info = viewModel.infoMessage { Text(info).font(.caption).foregroundColor(.green).multilineTextAlignment(.center) }
            
            Button { viewModel.signIn(email: email, password: password) } label: { Text("Sign In").fontWeight(.bold).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large)

            HStack {
                VStack { Divider() }
                Text("Or").font(.footnote).foregroundColor(.secondary)
                VStack { Divider() }
            }.padding(.vertical, 5)

            SignInWithAppleButton()
                .frame(height: 50)
                .onTapGesture { viewModel.signInWithApple() }

            SignInWithGoogleButtonView(action: {
                viewModel.signInWithGoogle()
            })

            Button("Don't have an account? Sign Up") { isSigningUp = true }.font(.footnote).tint(.accentColor).padding(.top)
        }
        .onChange(of: email) { _ in viewModel.errorMessage = nil; viewModel.infoMessage = nil }
        .onChange(of: password) { _ in viewModel.errorMessage = nil; viewModel.infoMessage = nil }
    }
}

struct CreateAccountForm: View {
    @EnvironmentObject var viewModel: AuthenticationViewModel
    @Binding var isSigningUp: Bool
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var hasAcceptedTerms = false
    private var isFormValid: Bool { !email.isEmpty && !password.isEmpty && password == confirmPassword && hasAcceptedTerms }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create an Account").font(.title2).fontWeight(.bold)
            ModernTextField(title: "Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
            ModernTextField(title: "Password", text: $password, isSecure: true).textContentType(.newPassword)
            ModernTextField(title: "Confirm Password", text: $confirmPassword, isSecure: true).textContentType(.newPassword)
            HStack(alignment: .top, spacing: 12) {
                Button(action: { hasAcceptedTerms.toggle() }) { Image(systemName: hasAcceptedTerms ? "checkmark.square.fill" : "square").font(.headline).foregroundColor(hasAcceptedTerms ? .accentColor : .secondary) }.buttonStyle(.plain)
                Text("I have read and agree to the [Terms of Service](https://smashspeed.ca/terms-of-service) and [Privacy Policy](https://smashspeed.ca/privacy-policy).").font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
            if let error = viewModel.errorMessage { Text(error).font(.caption).foregroundColor(.red).multilineTextAlignment(.center) }
            Button {
                guard password == confirmPassword else { viewModel.errorMessage = "Passwords do not match."; return }
                viewModel.signUp(email: email, password: password)
            } label: { Text("Create Account").fontWeight(.bold).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!isFormValid)
            Button("Already have an account? Sign In") { isSigningUp = false; viewModel.errorMessage = nil; viewModel.infoMessage = nil }.font(.footnote).tint(.accentColor).padding(.top)
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
    @State private var isPasswordVisible: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if isSecure {
                    if isPasswordVisible { TextField(title, text: $text) } else { SecureField(title, text: $text) }
                } else { TextField(title, text: $text) }
                if isSecure { Button(action: { isPasswordVisible.toggle() }) { Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill").foregroundColor(.secondary) }.buttonStyle(.plain) }
            }
            Divider()
        }.autocapitalization(.none)
    }
}

struct SignInWithAppleButton: UIViewRepresentable {
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton { ASAuthorizationAppleIDButton(type: .signIn, style: .black) }
    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}
}

struct SignInWithGoogleButtonView: View {
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image("google_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                Text("Sign in with Google")
                    .font(.body.weight(.medium))
                    .foregroundColor(Color.black.opacity(0.85))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
            )
        }
    }
}
