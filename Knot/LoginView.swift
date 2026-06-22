import SwiftUI
import Supabase
import Auth
import AuthenticationServices

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

let passwordRecoveryNameKey = "PasswordRecoveryName"
let passwordRecoveryContactKey = "PasswordRecoveryContact"
let passwordRecoveryUsesPhoneKey = "PasswordRecoveryUsesPhone"

func normalizeRecoveryName(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
}

func normalizeRecoveryEmail(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

func normalizeRecoveryPhone(_ countryCode: String, number: String) -> String {
    countryCode + number.filter(\.isNumber)
}

func isRecoveryEmailValid(_ email: String) -> Bool {
    let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
    return email.range(of: pattern, options: .regularExpression) != nil
}

func isRecoveryPhoneValid(_ phone: String, country: CountryCode) -> Bool {
    let digits = phone.filter(\.isNumber)
    return digits.count >= country.minDigits && digits.count <= country.maxDigits
}

enum PasswordRecoveryService {
    enum RecoveryError: LocalizedError {
        case phoneRecoveryUnavailable

        var errorDescription: String? {
            switch self {
            case .phoneRecoveryUnavailable:
                return "Password recovery by phone isn't available yet. Use your email address instead."
            }
        }
    }

    @AppStorage(passwordRecoveryNameKey) private static var recoveryName = ""
    @AppStorage(passwordRecoveryContactKey) private static var recoveryContact = ""
    @AppStorage(passwordRecoveryUsesPhoneKey) private static var recoveryUsesPhone = false

    @MainActor
    static func resetPassword(
        name: String,
        contact: String,
        usesPhone: Bool,
        newPassword: String
    ) async throws {
        guard !usesPhone else {
            throw RecoveryError.phoneRecoveryUnavailable
        }

        recoveryName = name
        recoveryContact = contact
        recoveryUsesPhone = false

        try await supabase.auth.resetPasswordForEmail(
            contact,
            redirectTo: URL(string: "knot://auth/callback")!
        )
    }
}

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


    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                Spacer()

                // Welcome Header
                Text("Welcome to Knot")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)

                Spacer().frame(height: 8)

                // Social Login Buttons — Apple first per HIG; required alongside any
                // third-party social login (App Review Guideline 4.8).
                VStack(spacing: 12) {
                    AppleSignInButton()
                    SocialLoginButton(label: "Continue with Google", iconText: "G") {
                        Task { await authManager.signInWithGoogle() }
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
                        .fill(Color.knotBorder)
                        .frame(height: 1)
                    Text("or")
                        .font(.subheadline)
                        .foregroundColor(Color.knotMuted)
                    Rectangle()
                        .fill(Color.knotBorder)
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
                                        .foregroundColor(.primary)
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                                .background(Color.knotSurface)
                                .cornerRadius(12, corners: [.topLeft, .bottomLeft])
                            }

                            // Phone Number TextField
                            TextField("Enter phone number", text: $phone)
                                .keyboardType(.phonePad)
                                .padding()
                                .background(Color.knotSurface)
                                .cornerRadius(12, corners: [.topRight, .bottomRight])
                        }
                        .knotSurfaceBorder(cornerRadius: 12)

                        // Toggle back to email
                        Button(action: { usePhone = false }) {
                            Text("Enter email instead")
                                .font(.caption)
                                .foregroundColor(Color.knotAccent)
                        }

                    } else {
                        // Email TextField
                        TextField("Enter email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                            .background(Color.knotSurface)
                            .cornerRadius(12)
                            .knotSurfaceBorder(cornerRadius: 12)

                        // Toggle to phone
                        Button(action: { usePhone = true }) {
                            Text("Enter phone number instead")
                                .font(.caption)
                                .foregroundColor(Color.knotAccent)
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
                            .foregroundColor(Color.knotMuted)
                    }
                }
                .padding()
                .background(Color.knotSurface)
                .cornerRadius(12)
                .knotSurfaceBorder(cornerRadius: 12)

                // Login Button
                Button(action: { Task { await login() } }) {
                    if isLoading {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    } else {
                        Text("Login")
                            .fontWeight(.semibold)
                            .foregroundColor(Color.knotOnAccent)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(Color.knotAccent)
                .cornerRadius(12)
                .disabled(isLoading)

                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 20) {
                    NavigationLink(destination: SignUpView()) {
                        Text("Sign Up")
                            .font(.subheadline)
                            .foregroundColor(Color.knotAccent)
                    }

                    NavigationLink(destination: ForgotPasswordView()) {
                        Text("Forgot Password?")
                            .font(.subheadline)
                            .foregroundColor(Color.knotAccent)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .background(
                Color.knotBackground.ignoresSafeArea()
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                       to: nil, from: nil, for: nil)
                    }
            )
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
                // Phone accounts are stored under a deterministic internal email
                // (no SMS provider) — sign in with that, not the phone identifier.
                let internalEmail = AuthManager.phoneInternalEmail(forE164: identifier)
                try await supabase.auth.signIn(email: internalEmail, password: password)
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
                            .foregroundColor(.primary)
                        Spacer()
                        Text(country.code)
                            .foregroundColor(.secondary)
                        if country.id == selectedCountry.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.primary)
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
//
// Mirrors the Apple Sign In button style exactly:
// filled black + white text in light mode, filled white + black text in dark mode.
struct SocialLoginButton: View {
    var label: String
    var icon: String = ""
    var iconText: String? = nil
    var action: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: Color  { colorScheme == .dark ? .white : .black }
    private var fgColor: Color  { colorScheme == .dark ? .black : .white }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let letter = iconText {
                    Text(letter)
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 22)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 19, weight: .semibold))
            }
            .foregroundColor(fgColor)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(bgColor)
            .cornerRadius(12)
        }
    }
}

// MARK: - Forgot Password Flow

struct ForgotPasswordView: View {
    @State private var name = ""
    @State private var usePhone = false
    @State private var email = ""
    @State private var phone = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var selectedCountry = countryCodes[0]
    @State private var showCountryPicker = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var showPassword = false

    private var normalizedName: String {
        normalizeRecoveryName(name)
    }

    private var normalizedContact: String {
        usePhone
            ? normalizeRecoveryPhone(selectedCountry.code, number: phone)
            : normalizeRecoveryEmail(email)
    }

    private var passwordIssue: String? {
        PasswordPolicy.errorMessage(for: newPassword)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "lock.rotation")
                    .font(.system(size: 48))
                    .foregroundColor(.primary)
                Text("Forgot Password")
                    .font(.system(size: 28, weight: .bold))
                Text("Enter your name, your email or phone number, and your new password. This screen is wired for the future backend reset endpoint.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                TextField("Name", text: $name)
                    .padding()
                    .background(Color.knotSurface)
                    .cornerRadius(12)
                    .knotSurfaceBorder(cornerRadius: 12)

                VStack(alignment: .leading, spacing: 8) {
                    if usePhone {
                        HStack(spacing: 0) {
                            Button(action: { showCountryPicker = true }) {
                                HStack(spacing: 4) {
                                    Text(selectedCountry.code)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                                .background(Color.knotSurface)
                                .cornerRadius(12, corners: [.topLeft, .bottomLeft])
                            }

                            TextField("Phone number", text: $phone)
                                .keyboardType(.phonePad)
                                .padding()
                                .background(Color.knotSurface)
                                .cornerRadius(12, corners: [.topRight, .bottomRight])
                        }
                        .knotSurfaceBorder(cornerRadius: 12)

                        Button("Use email instead") {
                            usePhone = false
                            errorMessage = nil
                            successMessage = nil
                        }
                        .font(.caption)
                        .foregroundColor(Color.knotAccent)
                    } else {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                            .background(Color.knotSurface)
                            .cornerRadius(12)
                            .knotSurfaceBorder(cornerRadius: 12)

                        Button("Use phone number instead") {
                            usePhone = true
                            errorMessage = nil
                            successMessage = nil
                        }
                        .font(.caption)
                        .foregroundColor(Color.knotAccent)
                    }
                }

                PasswordField(label: "New password", text: $newPassword, show: $showPassword)
                PasswordField(label: "Confirm password", text: $confirmPassword, show: $showPassword)
                PasswordStrengthIndicator(password: newPassword)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            if let successMessage {
                Text(successMessage)
                    .font(.caption)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.center)
            }

            Button(action: { Task { await submitReset() } }) {
                if isLoading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Text("Reset Password")
                        .fontWeight(.semibold)
                        .foregroundColor(Color.knotOnAccent)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Color.knotAccent)
            .cornerRadius(12)
            .disabled(isLoading)

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Forgot Password")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerView(selectedCountry: $selectedCountry, isPresented: $showCountryPicker)
        }
    }

    @MainActor
    private func submitReset() async {
        guard !normalizedName.isEmpty else {
            errorMessage = "Enter your name."
            return
        }

        if usePhone {
            guard isRecoveryPhoneValid(phone, country: selectedCountry) else {
                errorMessage = selectedCountry.minDigits == selectedCountry.maxDigits
                    ? "Phone number must be \(selectedCountry.minDigits) digits for \(selectedCountry.name)."
                    : "Phone number must be \(selectedCountry.minDigits)–\(selectedCountry.maxDigits) digits for \(selectedCountry.name)."
                return
            }
        } else {
            guard isRecoveryEmailValid(normalizedContact) else {
                errorMessage = "Enter a valid email address."
                return
            }
        }

        guard let passwordIssue else {
            guard newPassword == confirmPassword else {
                errorMessage = "Passwords do not match."
                return
            }

            isLoading = true
            errorMessage = nil
            successMessage = nil
            defer { isLoading = false }

            do {
                try await PasswordRecoveryService.resetPassword(
                    name: normalizedName,
                    contact: normalizedContact,
                    usesPhone: usePhone,
                    newPassword: newPassword
                )
                successMessage = "Password reset completed."
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        errorMessage = passwordIssue
    }
}

// MARK: - Apple Sign-In Button
//
// Native iOS Sign in with Apple button. Wraps SwiftUI's SignInWithAppleButton
// and hands the result to AuthManager which does the Supabase JWT exchange.
//
// Apple App Store Review Guideline 4.8 requires this whenever the app offers
// a third-party social login (Google in our case). It must be at least as
// prominent as the other social options.
struct AppleSignInButton: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SignInWithAppleButton(.continue,
            onRequest: { request in
                request.requestedScopes = [.fullName, .email]
                request.nonce = authManager.makeNonceForAppleRequest()
            },
            onCompletion: { result in
                switch result {
                case .success(let authorization):
                    Task { await authManager.handleAppleAuthorization(authorization) }
                case .failure(let error):
                    let nsError = error as NSError
                    if nsError.code == ASAuthorizationError.canceled.rawValue { return }
                    print("[AppleSignIn] error: \(error)")
                }
            }
        )
        // Match the Google button alongside us: filled-black in light, filled-white in dark.
        // Apple HIG permits .black or .white — both are official styles.
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 52)
        .cornerRadius(12)
        .id(colorScheme)   // force recreation when scheme changes so style updates
    }
}

#Preview {
    LoginView()
}
