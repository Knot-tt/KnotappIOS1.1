import SwiftUI
import Supabase

// MARK: - Sign Up Landing Screen
struct SignUpView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 20) {

            Spacer()

            // Header
            Text("Create your Knot account")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 8)

            // Social Sign Up Buttons — Apple first per HIG / Guideline 4.8.
            VStack(spacing: 12) {
                AppleSignInButton()
                SocialLoginButton(label: "Continue with Google", icon: "globe") {
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
            HStack {
                Rectangle().frame(height: 1).foregroundColor(Color.knotBorder)
                Text("or").foregroundColor(.secondary).font(.footnote)
                Rectangle().frame(height: 1).foregroundColor(Color.knotBorder)
            }

            // Create Account Button
            NavigationLink(destination: CreateAccountView()) {
                Text("Create Account")
                    .fontWeight(.semibold)
                    .foregroundColor(Color.knotOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.knotAccent)
                    .cornerRadius(12)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Create Account Form Screen
struct CreateAccountView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var verifyPassword = ""
    @State private var usePhone = false
    @State private var selectedCountry = countryCodes[0]
    @State private var showCountryPicker = false
    @State private var showPassword = false
    @State private var showVerifyPassword = false
    @State private var agreedToTerms = false
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false

    // Error states
    @State private var emailError = ""
    @State private var phoneError = ""
    @State private var passwordError = ""
    @State private var verifyPasswordError = ""

    // Async sign-up state
    @State private var isLoading = false
    @State private var signUpError: String? = nil
    @State private var navigateToOTP = false
    @State private var navigateToBirthday = false

    // Email validation
    func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    // Phone validation based on selected country
    func isValidPhone(_ phone: String) -> Bool {
        let digits = phone.filter { $0.isNumber }
        return digits.count >= selectedCountry.minDigits && digits.count <= selectedCountry.maxDigits
    }

    // Run all validations and return true if everything passes
    func validate() -> Bool {
        var valid = true

        // Email or phone check
        if usePhone {
            if phone.isEmpty || !isValidPhone(phone) {
                phoneError = selectedCountry.minDigits == selectedCountry.maxDigits
                    ? "Phone must be \(selectedCountry.minDigits) digits for \(selectedCountry.name)"
                    : "Phone must be \(selectedCountry.minDigits)–\(selectedCountry.maxDigits) digits for \(selectedCountry.name)"
                valid = false
            } else {
                phoneError = ""
            }
        } else {
            if email.isEmpty || !isValidEmail(email) {
                emailError = "Enter a valid email address"
                valid = false
            } else {
                emailError = ""
            }
        }

        // Password strength check (via shared PasswordPolicy)
        if let issue = PasswordPolicy.errorMessage(for: password) {
            passwordError = issue
            valid = false
        } else {
            passwordError = ""
        }

        // Password match check
        if verifyPassword != password {
            verifyPasswordError = "Passwords do not match"
            valid = false
        } else {
            verifyPasswordError = ""
        }

        return valid
    }

    @MainActor
    private func signUp() async {
        isLoading   = true
        signUpError = nil
        defer { isLoading = false }

        let identifier = usePhone
            ? selectedCountry.code + phone.trimmingCharacters(in: .whitespaces)
            : email.trimmingCharacters(in: .whitespaces)
        guard await authManager.checkSignupRateLimit(identifier: identifier) else {
            signUpError = authManager.socialAuthError
            return
        }

        do {
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            if usePhone {
                // Phone accounts have NO SMS/OTP — the number is just an identifier.
                // The edge function creates an auto-confirmed account; we then sign
                // in and go straight to onboarding (no verification screen).
                let internalEmail = try await authManager.phoneSignUp(
                    e164Phone: identifier, password: password, name: trimmedName
                )
                try await supabase.auth.signIn(email: internalEmail, password: password)
                print("[SignUp] phone sign up succeeded")
                navigateToBirthday = true
            } else {
                try await supabase.auth.signUp(email: identifier, password: password, data: ["name": .string(trimmedName)])
                // KnotApp takes over: EmailVerificationGateView shown, then OnboardingFlowView after verification
            }
        } catch {
            print("[SignUp] error: \(error)")
            let msg = error.localizedDescription.lowercased()
            if !usePhone && (msg.contains("already registered") || msg.contains("already exists")) {
                // Email already has an account — re-send the confirmation email.
                try? await supabase.auth.resend(email: email.trimmingCharacters(in: .whitespaces), type: .signup)
            } else {
                // Phone "already exists" and all other failures surface their message.
                signUpError = error.localizedDescription
            }
        }
    }

    var body: some View {
        VStack(spacing: 20) {

            Spacer()

            // Header
            Text("Let's get you set up")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)

            Spacer().frame(height: 8)

            // Form Fields
            VStack(spacing: 12) {

                // Name
                TextField("Name", text: $name)
                    .padding()
                    .background(Color.knotSurface)
                    .cornerRadius(12)
                    .knotSurfaceBorder(cornerRadius: 12)

                // Email or Phone Toggle
                VStack(alignment: .leading, spacing: 6) {
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

                            TextField("Enter phone number", text: $phone)
                                .keyboardType(.phonePad)
                                .padding()
                                .background(phoneError.isEmpty ? Color.knotSurface : Color.red.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(phoneError.isEmpty ? Color.knotBorder : Color.red, lineWidth: phoneError.isEmpty ? 1 : 1.5)
                                        .cornerRadius(12, corners: [.topRight, .bottomRight])
                                )
                                .cornerRadius(12, corners: [.topRight, .bottomRight])
                                .onChange(of: phone) { _ in
                                    if !phone.isEmpty {
                                        phoneError = isValidPhone(phone) ? "" : selectedCountry.minDigits == selectedCountry.maxDigits ?
                                            "Phone number must be \(selectedCountry.minDigits) digits for \(selectedCountry.name)" :
                                            "Phone number must be \(selectedCountry.minDigits)–\(selectedCountry.maxDigits) digits for \(selectedCountry.name)"
                                    } else {
                                        phoneError = ""
                                    }
                                }
                        }

                        if !phoneError.isEmpty {
                            Text(phoneError).font(.caption).foregroundColor(.red)
                        }

                        Button(action: { usePhone = false; phoneError = "" }) {
                            Text("Enter email instead").font(.caption).foregroundColor(.secondary)
                        }

                    } else {
                        TextField("Enter email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                            .background(emailError.isEmpty ? Color.knotSurface : Color.red.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(emailError.isEmpty ? Color.knotBorder : Color.red, lineWidth: emailError.isEmpty ? 1 : 1.5)
                            )
                            .cornerRadius(12)
                            .onChange(of: email) { _ in
                                emailError = email.isEmpty || isValidEmail(email) ? "" : "Check email — enter a valid email address"
                            }

                        if !emailError.isEmpty {
                            Text(emailError).font(.caption).foregroundColor(.red)
                        }

                        Button(action: { usePhone = true; emailError = "" }) {
                            Text("Enter phone number instead").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                // Password Field with show/hide toggle
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                        Button(action: { showPassword.toggle() }) {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(passwordError.isEmpty ? Color.knotSurface : Color.red.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(passwordError.isEmpty ? Color.knotBorder : Color.red, lineWidth: passwordError.isEmpty ? 1 : 1.5)
                    )
                    .cornerRadius(12)
                    .onChange(of: password) { _ in
                        passwordError = password.isEmpty || password.count >= 8 ? "" : "Password must be at least 8 characters"
                    }

                    if !passwordError.isEmpty {
                        Text(passwordError).font(.caption).foregroundColor(.red)
                    }
                }

                // Verify Password Field with show/hide toggle
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if showVerifyPassword {
                            TextField("Verify Password", text: $verifyPassword)
                        } else {
                            SecureField("Verify Password", text: $verifyPassword)
                        }
                        Button(action: { showVerifyPassword.toggle() }) {
                            Image(systemName: showVerifyPassword ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(verifyPasswordError.isEmpty ? Color.knotSurface : Color.red.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(verifyPasswordError.isEmpty ? Color.knotBorder : Color.red, lineWidth: verifyPasswordError.isEmpty ? 1 : 1.5)
                    )
                    .cornerRadius(12)
                    .onChange(of: verifyPassword) { _ in
                        verifyPasswordError = verifyPassword.isEmpty || verifyPassword == password ? "" : "Passwords do not match"
                    }

                    if !verifyPasswordError.isEmpty {
                        Text(verifyPasswordError).font(.caption).foregroundColor(.red)
                    }
                }
            }

    // Terms & Privacy acceptance
            HStack(alignment: .top, spacing: 10) {
                Button(action: { agreedToTerms.toggle() }) {
                    ZStack {
                        Image(systemName: "square")
                            .font(.system(size: 20))
                            .foregroundColor(agreedToTerms ? Color.knotAccent : Color.knotMuted)
                        if agreedToTerms {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color.knotAccent)
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text("I agree to the")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Button(action: { showTermsSheet = true }) {
                            Text("Terms & Conditions")
                                .font(.footnote)
                                .underline()
                                .foregroundColor(Color.knotAccent)
                        }
                        .buttonStyle(.plain)
                        Text("and")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Button(action: { showPrivacySheet = true }) {
                            Text("Privacy Policy")
                                .font(.footnote)
                                .underline()
                                .foregroundColor(Color.knotAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)

    // Join Knot Button
            if let err = signUpError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: {
                if validate() {
                    Task { await signUp() }
                }
            }) {
                Group {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Join Knot")
                            .fontWeight(.semibold)
                            .foregroundColor(Color.knotOnAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(agreedToTerms ? Color.knotAccent : Color.knotMuted)
                .cornerRadius(12)
            }
            .disabled(isLoading || !agreedToTerms)

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerView(selectedCountry: $selectedCountry, isPresented: $showCountryPicker)
        }
        .sheet(isPresented: $showTermsSheet) {
            NavigationStack {
                LegalDocumentView(kind: .terms)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showTermsSheet = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPrivacySheet) {
            NavigationStack {
                LegalDocumentView(kind: .privacy)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showPrivacySheet = false }
                }
            }
        }
        .navigationDestination(isPresented: $navigateToOTP) {
            EmailVerificationView(email: selectedCountry.code + phone, name: name, isPhone: true)
        }
        .navigationDestination(isPresented: $navigateToBirthday) {
            BirthdayView(name: name)
        }
    }
}
}

// MARK: - OTP Verification Screen
struct EmailVerificationView: View {
    let email: String
    let name: String
    let isPhone: Bool
    @State private var otp: [String] = Array(repeating: "", count: 6)
    @State private var navigateToBirthday = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @FocusState private var focusedIndex: Int?

    var otpString: String { otp.joined() }

    var contactDisplay: String {
        isPhone ? "your phone number" : email
    }

    @MainActor
    private func verify() async {
        isLoading = true
        defer { isLoading = false }
        do {
            if isPhone {
                try await supabase.auth.verifyOTP(phone: email, token: otpString, type: .sms)
            } else {
                try await supabase.auth.verifyOTP(email: email, token: otpString, type: .signup)
            }
            navigateToBirthday = true
        } catch {
            errorMessage = "Invalid or expired code. Please check the code and try again."
            showErrorAlert = true
        }
    }

    @MainActor
    private func resendCode() async {
        do {
            if isPhone {
                try await supabase.auth.resend(phone: email, type: .sms)
            } else {
                try await supabase.auth.resend(email: email, type: .signup)
            }
        } catch {
            errorMessage = "Could not resend code. Please wait a moment and try again."
            showErrorAlert = true
        }
    }

    var body: some View {
        VStack(spacing: 28) {

            Spacer()

            // Icon
            Image(systemName: isPhone ? "phone.circle.fill" : "envelope.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.primary)

            // Header
            Text(isPhone ? "Verify your number" : "Verify your email")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)

            // Subtext
            VStack(spacing: 8) {
                Text("We sent a 6-digit code to")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(contactDisplay)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }

            // OTP Boxes
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    TextField("", text: $otp[index])
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.title2.bold())
                        .frame(width: 44, height: 52)
                        .background(Color.knotSurface)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(focusedIndex == index ? Color.knotAccent : Color.clear, lineWidth: 1.5)
                        )
                        .focused($focusedIndex, equals: index)
                        .onChange(of: otp[index]) { newValue in
                            // Only keep 1 digit
                            if newValue.count > 1 {
                                otp[index] = String(newValue.last!)
                            }
                            // Auto advance to next box
                            if newValue.count == 1 && index < 5 {
                                focusedIndex = index + 1
                            }
                            // Auto go back if deleted
                            if newValue.isEmpty && index > 0 {
                                focusedIndex = index - 1
                            }
                        }
                }
            }
            .onAppear { focusedIndex = 0 }

            // Verify Button
            Button(action: {
                if otpString.count < 6 {
                    errorMessage = "Please enter the full 6-digit code"
                    showErrorAlert = true
                } else {
                    Task { await verify() }
                }
            }) {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Verify")
                            .fontWeight(.semibold)
                            .foregroundColor(Color.knotOnAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(otpString.count == 6 ? Color.knotAccent : Color.gray)
                .cornerRadius(12)
            }
            .disabled(otpString.count < 6 || isLoading)

            // Resend code
            Button(action: {
                Task { await resendCode() }
            }) {
                Text("Resend code")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            NavigationLink(destination: BirthdayView(name: name), isActive: $navigateToBirthday) {
                EmptyView()
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Verification")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .alert("Invalid Code", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Birthday Screen
struct BirthdayView: View {
    let name: String
    @State private var birthday = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var navigateToInterests = false

    // Calculate age from birthday
    var age: Int {
        Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
    }

    var body: some View {
        VStack(spacing: 32) {

            Spacer()

            Text("When's your birthday?")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text("This helps us personalise your Knot experience.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // Date Picker
            DatePicker(
                "",
                selection: $birthday,
                in: ...Calendar.current.date(byAdding: .year, value: -13, to: Date())!,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()

            // Continue Button — persist birthday before advancing so age-range checks work later.
            Button(action: {
                let dob = birthday
                Task { try? await ProfileService.saveBirthday(dob) }
                navigateToInterests = true
            }) {
                Text("Continue")
                    .fontWeight(.semibold)
                    .foregroundColor(Color.knotOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.knotAccent)
                    .cornerRadius(12)
            }

            NavigationLink(destination: InterestsView(age: age, name: name), isActive: $navigateToInterests) {
                EmptyView()
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Customising Your Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Interests Data
struct Interest: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let minAge: Int
    let maxAge: Int
}

let allInterests: [Interest] = [
    // All ages (13+)
    Interest(name: "Music",         minAge: 13, maxAge: 99),
    Interest(name: "Gaming",        minAge: 13, maxAge: 99),
    Interest(name: "Sports",        minAge: 13, maxAge: 99),
    Interest(name: "Art",           minAge: 13, maxAge: 99),
    Interest(name: "Reading",       minAge: 13, maxAge: 99),
    Interest(name: "Cooking",       minAge: 13, maxAge: 99),
    Interest(name: "Travel",        minAge: 13, maxAge: 99),
    Interest(name: "Photography",   minAge: 13, maxAge: 99),
    Interest(name: "Movies",        minAge: 13, maxAge: 99),
    Interest(name: "Nature",        minAge: 13, maxAge: 99),
    Interest(name: "Dancing",       minAge: 13, maxAge: 99),
    Interest(name: "Volunteering",  minAge: 13, maxAge: 99),

    // Teens (13–17)
    Interest(name: "School Clubs",  minAge: 13, maxAge: 17),
    Interest(name: "Anime",         minAge: 13, maxAge: 17),
    Interest(name: "Skateboarding", minAge: 13, maxAge: 17),
    Interest(name: "Esports",       minAge: 13, maxAge: 17),

    // Young adults (18–25)
    Interest(name: "Nightlife",     minAge: 18, maxAge: 25),
    Interest(name: "Startups",      minAge: 18, maxAge: 25),
    Interest(name: "Fitness",       minAge: 18, maxAge: 25),
    Interest(name: "Networking",    minAge: 18, maxAge: 25),
    Interest(name: "Hiking",        minAge: 18, maxAge: 99),
    Interest(name: "Yoga",          minAge: 18, maxAge: 99),

    // Adults (26+)
    Interest(name: "Parenting",     minAge: 26, maxAge: 99),
    Interest(name: "Investing",     minAge: 26, maxAge: 99),
    Interest(name: "Wine Tasting",  minAge: 26, maxAge: 99),
    Interest(name: "Golf",          minAge: 26, maxAge: 99),

    // Seniors (55+)
    Interest(name: "Gardening",     minAge: 55, maxAge: 99),
    Interest(name: "Bridge",        minAge: 55, maxAge: 99),
    Interest(name: "Bird Watching", minAge: 55, maxAge: 99),
]

// MARK: - Interests Screen
struct InterestsView: View {
    let age: Int
    let name: String
    @EnvironmentObject var authManager: AuthManager
    @State private var selected: Set<UUID> = []
    @State private var showError = false
    @State private var navigateToWelcome = false
    @State private var navigateToWelcomeSkip = false

    let minRequired = 3

    var filteredInterests: [Interest] {
        allInterests.filter { age >= $0.minAge && age <= $0.maxAge }
    }

    var body: some View {
        VStack(spacing: 24) {

            Spacer().frame(height: 8)

            Text("What are you into?")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.primary)

            Text("Pick at least 3 interests to help us connect you with your community.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Bubble chips
            ScrollView {
                FlowLayout(spacing: 10) {
                    ForEach(filteredInterests) { interest in
                        let isSelected = selected.contains(interest.id)
                        Button(action: {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                if isSelected {
                                    selected.remove(interest.id)
                                } else {
                                    selected.insert(interest.id)
                                }
                            }
                            showError = false
                        }) {
                            HStack(spacing: 6) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .transition(.scale.combined(with: .opacity))
                                }
                                Text(interest.name)
                                    .font(.subheadline)
                                    .fontWeight(isSelected ? .semibold : .regular)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(isSelected ? Color.knotAccent : Color.knotSurface)
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(isSelected ? Color.knotAccent : Color.knotBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            if showError {
                Text("Please select at least 3 interests")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Counter
            Text("\(selected.count) selected")
                .font(.caption)
                .foregroundColor(.secondary)

            // Continue Button
            Button(action: {
                if selected.count >= minRequired {
                    Task { await completeOnboarding() }
                } else {
                    showError = true
                }
            }) {
                Text("Continue")
                    .fontWeight(.semibold)
                    .foregroundColor(Color.knotOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.knotAccent)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)

            // Skip button
            Button(action: {
                Task { await completeOnboarding() }
            }) {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)

            NavigationLink(destination: WelcomeView(name: name), isActive: $navigateToWelcomeSkip) {
                EmptyView()
            }

            NavigationLink(destination: LoadingView(name: name), isActive: $navigateToWelcome) {
                EmptyView()
            }
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Customising Your Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func completeOnboarding() async {
        // Persist selected interest names (display strings — stable and human-readable).
        let chosen = filteredInterests.filter { selected.contains($0.id) }.map(\.name)
        try? await ProfileService.saveInterests(chosen)
        try? await ProfileService.completeOnboarding()
        authManager.isOnboardingComplete = true
    }
}

// MARK: - Flow Layout for wrapping bubbles
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }
            .reduce(0) { $0 + $1 + spacing }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var currentRowWidth: CGFloat = 0
        let maxWidth = proposal.width ?? 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width + spacing > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentRowWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentRowWidth += size.width + spacing
        }
        return rows
    }
}

// MARK: - Loading Screen
struct LoadingView: View {
    let name: String
    @State private var navigateToWelcome = false
    @State private var dotCount = 0
    @State private var progress: CGFloat = 0

    // TODO: replace this timer with actual Supabase calibration time
    let simulatedDuration: Double = 3.0

    var dots: String {
        String(repeating: ".", count: dotCount)
    }

    var body: some View {
        VStack(spacing: 32) {

            Spacer()

            // Animated Knot logo / title
            Text("Knot")
                .font(.system(size: 48, weight: .heavy))
                .foregroundColor(.primary)

            Text("Calibrating your interests\(dots)")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 260, alignment: .leading)
                .onAppear {
                    // Animate dots
                    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                        dotCount = (dotCount + 1) % 4
                        if navigateToWelcome { timer.invalidate() }
                    }

                    // Animate progress bar
                    withAnimation(.linear(duration: simulatedDuration)) {
                        progress = 1.0
                    }

                    // Navigate after duration
                    DispatchQueue.main.asyncAfter(deadline: .now() + simulatedDuration) {
                        navigateToWelcome = true
                    }

                }

            // Progress bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.knotSurface)
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.knotAccent)
                    .frame(width: progress * (UIScreen.main.bounds.width - 80), height: 6)
            }
            .frame(height: 6)
            .padding(.horizontal, 40)

            Spacer()

            NavigationLink(destination: WelcomeView(name: name), isActive: $navigateToWelcome) {
                EmptyView()
            }
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
    }
}

struct WelcomeView: View {
    let name: String
    @State private var navigateToDashboard = false

    var body: some View {
        VStack(spacing: 32) {

            Spacer()

            Text("Welcome to your account,")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text(name)
                .font(.system(size: 36, weight: .heavy))
                .foregroundColor(.primary)

            Text("You're all set. Let's get you connected with your community.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Let's go button
            Button(action: {
                navigateToDashboard = true
            }) {
                Text("Let's go")
                    .fontWeight(.semibold)
                    .foregroundColor(Color.knotOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.knotAccent)
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            NavigationLink(destination: MainTabView(name: name, onLogout: { navigateToDashboard = false }), isActive: $navigateToDashboard) {
                EmptyView()
            }

            Spacer()
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
    }
}


// MARK: - Check Email View (shown after email sign-up)
struct CheckEmailView: View {
    let email: String
    @State private var didResend = false
    @State private var isResending = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "envelope.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.primary)

            VStack(spacing: 12) {
                Text("Check your email")
                    .font(.system(size: 28, weight: .bold))

                Text("We sent a confirmation link to\n**\(email)**")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("Tap the link in the email to activate your account.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button(action: resend) {
                    if isResending {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    } else {
                        Text(didResend ? "Email sent!" : "Resend confirmation email")
                            .fontWeight(.semibold)
                            .foregroundColor(Color.knotOnAccent)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding()
                .background(didResend ? Color.gray : Color.knotAccent)
                .cornerRadius(12)
                .disabled(didResend || isResending)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .background(Color.knotBackground.ignoresSafeArea())
        .navigationTitle("Verify Email")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resend() {
        isResending = true
        Task {
            try? await supabase.auth.resend(email: email, type: .signup)
            didResend   = true
            isResending = false
        }
    }
}

#Preview {
    SignUpView()
}
