import SwiftUI
import Supabase
import Auth

// MARK: - Country Code Data
struct CountryCode: Identifiable {
    let id = UUID()
    let name: String
    let code: String
    let minDigits: Int
    let maxDigits: Int
}

let countryCodes: [CountryCode] = [
    CountryCode(name: "Singapore",      code: "+65",  minDigits: 8,  maxDigits: 8),
    CountryCode(name: "United States",  code: "+1",   minDigits: 10, maxDigits: 10),
    CountryCode(name: "United Kingdom", code: "+44",  minDigits: 10, maxDigits: 10),
    CountryCode(name: "Australia",      code: "+61",  minDigits: 9,  maxDigits: 9),
    CountryCode(name: "India",          code: "+91",  minDigits: 10, maxDigits: 10),
    CountryCode(name: "China",          code: "+86",  minDigits: 11, maxDigits: 11),
    CountryCode(name: "Japan",          code: "+81",  minDigits: 10, maxDigits: 11),
    CountryCode(name: "South Korea",    code: "+82",  minDigits: 9,  maxDigits: 10),
    CountryCode(name: "Germany",        code: "+49",  minDigits: 10, maxDigits: 11),
    CountryCode(name: "France",         code: "+33",  minDigits: 9,  maxDigits: 9),
    CountryCode(name: "Canada",         code: "+1",   minDigits: 10, maxDigits: 10),
    CountryCode(name: "Brazil",         code: "+55",  minDigits: 10, maxDigits: 11),
    CountryCode(name: "South Africa",   code: "+27",  minDigits: 9,  maxDigits: 9),
    CountryCode(name: "UAE",            code: "+971", minDigits: 9,  maxDigits: 9),
    CountryCode(name: "Malaysia",       code: "+60",  minDigits: 9,  maxDigits: 10),
    CountryCode(name: "Philippines",    code: "+63",  minDigits: 10, maxDigits: 10),
    CountryCode(name: "Indonesia",      code: "+62",  minDigits: 9,  maxDigits: 12),
    CountryCode(name: "Thailand",       code: "+66",  minDigits: 9,  maxDigits: 9),
    CountryCode(name: "New Zealand",    code: "+64",  minDigits: 8,  maxDigits: 9),
]

// MARK: - Login View
struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var isLoading       = false
    @State private var errorMessage    : String? = nil
    @State private var usePhone        = false
    @State private var selectedCountry = countryCodes[0]
    @State private var showCountryPicker = false
    @State private var showPassword    = false
    @State private var showForgotSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                Spacer()

                // Welcome Header
                Text("Welcome to Knot")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.black)

                Spacer().frame(height: 8)

                // Social Login Buttons
                VStack(spacing: 12) {
                    SocialLoginButton(label: "Continue with Google", iconText: "G") {
                        Task { await authManager.signInWithGoogle() }
                    }
                    SocialLoginButton(label: "Continue with Apple", icon: "apple.logo") {
                        Task { await authManager.signInWithApple() }
                    }
                }
                if let err = authManager.socialAuthError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                // Divider
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 1)
                    Text("or")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 1)
                }
                .padding(.vertical, 4)

                // Email or Phone Input
                VStack(alignment: .leading, spacing: 6) {
                    if usePhone {
                        // Phone Number Field with Country Code
                        HStack(spacing: 0) {
                            // Country Code Button
                            Button(action: { showCountryPicker = true }) {
                                HStack(spacing: 4) {
                                    Text(selectedCountry.code)
                                        .font(.subheadline)
                                        .foregroundColor(.black)
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                                .background(Color(.systemGray5))
                                .cornerRadius(12, corners: [.topLeft, .bottomLeft])
                            }

                            // Phone Number TextField
                            TextField("Enter phone number", text: $phone)
                                .keyboardType(.phonePad)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12, corners: [.topRight, .bottomRight])
                        }

                        // Toggle back to email
                        Button(action: { usePhone = false }) {
                            Text("Enter email instead")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                    } else {
                        // Email TextField
                        TextField("Enter email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)

                        // Toggle to phone
                        Button(action: { usePhone = true }) {
                            Text("Enter phone number instead")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }

                // Password Field
                HStack {
                    if showPassword {
                        TextField("Password", text: $password)
                            .autocapitalization(.none)
                    } else {
                        SecureField("Password", text: $password)
                    }
                    Button(action: { showPassword.toggle() }) {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Login Button
                Button(action: { Task { await login() } }) {
                    if isLoading {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    } else {
                        Text("Login")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(Color.black)
                .cornerRadius(12)
                .disabled(isLoading)

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                // Forgot Password + Sign Up
                HStack(spacing: 24) {
                    Button(action: { showForgotSheet = true }) {
                        Text("Forgot Password?")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    NavigationLink(destination: SignUpView()) {
                        Text("Sign Up")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .background(Color.white.ignoresSafeArea())
            // Forgot Password Sheet
            .sheet(isPresented: $showForgotSheet) {
                ForgotPasswordView(onDone: { showForgotSheet = false })
            }
            // Country Picker Sheet
            .sheet(isPresented: $showCountryPicker) {
                CountryPickerView(selectedCountry: $selectedCountry, isPresented: $showCountryPicker)
            }
        }
    }

    @MainActor
    private func login() async {
        isLoading    = true
        errorMessage = nil
        defer { isLoading = false }

        // Rate limit check — blocks credential stuffing and repeated failures
        let identifier = usePhone
            ? selectedCountry.code + phone.trimmingCharacters(in: .whitespaces)
            : email.trimmingCharacters(in: .whitespaces)
        guard await authManager.checkAuthRateLimit(identifier: identifier) else {
            errorMessage = authManager.socialAuthError
            return
        }

        do {
            if usePhone {
                try await supabase.auth.signIn(phone: identifier, password: password)
            } else {
                try await supabase.auth.signIn(email: identifier, password: password)
            }
            // AuthManager listener picks up signedIn event automatically
        } catch {
            // Use a generic message — never expose whether the email exists or
            // the exact reason for failure (prevents user-enumeration attacks).
            errorMessage = "Invalid credentials. Please check your email and password."
        }
    }
}

// MARK: - Country Picker Sheet
struct CountryPickerView: View {
    @Binding var selectedCountry: CountryCode
    @Binding var isPresented: Bool
    @State private var searchText = ""

    var filteredCountries: [CountryCode] {
        if searchText.isEmpty {
            return countryCodes
        } else {
            return countryCodes.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.code.contains(searchText)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredCountries) { country in
                Button(action: {
                    selectedCountry = country
                    isPresented = false
                }) {
                    HStack {
                        Text(country.name)
                            .foregroundColor(.black)
                        Spacer()
                        Text(country.code)
                            .foregroundColor(.gray)
                        if country.id == selectedCountry.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.black)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search country or code")
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - Corner Radius Helper
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Social Login Button
struct SocialLoginButton: View {
    var label: String
    var icon: String = ""
    var iconText: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack {
                if let letter = iconText {
                    Text(letter)
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 20)
                } else {
                    Image(systemName: icon)
                }
                Text(label)
                    .fontWeight(.medium)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding()
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
    }
}

// MARK: - Forgot Password Flow

// Step 1: Enter email or phone
struct ForgotPasswordView: View {
    var onDone: () -> Void = {}
    @State private var usePhone          = false
    @State private var email             = ""
    @State private var phone             = ""
    @State private var selectedCountry   = countryCodes[0]
    @State private var showCountryPicker = false
    @State private var goToVerify        = false

    private var canContinue: Bool { usePhone ? !phone.isEmpty : !email.isEmpty }
    private var contact: String   { usePhone ? selectedCountry.code + phone : email }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 48))
                        .foregroundColor(.black)
                    Text("Reset Password")
                        .font(.system(size: 28, weight: .bold))
                    Text("Enter the email or phone number associated with your account and we'll send you a verification code.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if usePhone {
                        HStack(spacing: 0) {
                            Button(action: { showCountryPicker = true }) {
                                HStack(spacing: 4) {
                                    Text(selectedCountry.code).font(.subheadline).foregroundColor(.black)
                                    Image(systemName: "chevron.down").font(.caption).foregroundColor(.gray)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 14)
                                .background(Color(.systemGray5))
                                .cornerRadius(12, corners: [.topLeft, .bottomLeft])
                            }
                            TextField("Phone number", text: $phone)
                                .keyboardType(.phonePad)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12, corners: [.topRight, .bottomRight])
                        }
                        Button("Use email instead") { usePhone = false }
                            .font(.caption).foregroundColor(.gray)
                    } else {
                        TextField("Enter email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        Button("Use phone number instead") { usePhone = true }
                            .font(.caption).foregroundColor(.gray)
                    }
                }

                NavigationLink(destination: VerifyCodeView(contact: contact, onDone: onDone), isActive: $goToVerify) {
                    EmptyView()
                }

                Button(action: { goToVerify = true }) {
                    Text("Send Code")
                        .fontWeight(.semibold)
                        .foregroundColor(canContinue ? .white : Color(.systemGray3))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canContinue ? Color.black : Color(.systemGray5))
                        .cornerRadius(12)
                }
                .disabled(!canContinue)

                Spacer()
            }
            .padding(.horizontal, 24)
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Forgot Password")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCountryPicker) {
                CountryPickerView(selectedCountry: $selectedCountry, isPresented: $showCountryPicker)
            }
        }
    }
}

// Step 2: Enter email → Supabase sends the real reset link
// The OTP-style verify step is removed: Supabase's magic-link / recovery flow
// handles token validation server-side. The user opens the link from email which
// deep-links into the app via PasswordResetView (in KnotApp.swift).
struct VerifyCodeView: View {
    let contact: String
    var onDone: () -> Void = {}

    @State private var isLoading  = false
    @State private var sent       = false
    @State private var errorMsg   : String? = nil

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 48))
                    .foregroundColor(.black)
                Text("Check your \(contact.hasPrefix("+") ? "messages" : "inbox")")
                    .font(.system(size: 26, weight: .bold))
                if sent {
                    Text("A password-reset link has been sent to **\(contact)**. Open the link on this device to set a new password.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("We'll send a secure reset link to **\(contact)**.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            if let err = errorMsg {
                Text(err).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
            }

            if sent {
                Button("Done") { onDone() }
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .cornerRadius(12)
            } else {
                Button(action: { Task { await sendLink() } }) {
                    if isLoading {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    } else {
                        Text("Send Reset Link")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(Color.black)
                .cornerRadius(12)
                .disabled(isLoading)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendLink() async {
        isLoading = true
        errorMsg  = nil
        defer { isLoading = false }
        do {
            // Supabase sends a recovery email; the deep-link opens PasswordResetView
            // (in KnotApp.swift) which lets the user set a new password.
            let redirectURL = URL(string: "knot://auth/callback")!
            if contact.hasPrefix("+") {
                // Phone: Supabase sends OTP via SMS — wire when phone-reset is supported
                try await supabase.auth.resetPasswordForEmail(contact, redirectTo: redirectURL)
            } else {
                try await supabase.auth.resetPasswordForEmail(contact, redirectTo: redirectURL)
            }
            sent = true
        } catch {
            errorMsg = "Could not send reset link. Please check the email and try again."
        }
    }
}

// Step 3 (legacy UI stub — real reset handled by PasswordResetView in KnotApp.swift
// when the user opens the recovery deep-link on this device)
struct ResetPasswordView: View {
    var onDone: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 56))
                .foregroundColor(.black)
            Text("Check your email")
                .font(.system(size: 28, weight: .bold))
            Text("Open the reset link in the email on this device. The app will guide you through setting a new password.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Done") { onDone() }
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black)
                .cornerRadius(12)
                .padding(.horizontal)
            Spacer()
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Reset Password")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    LoginView()
}
