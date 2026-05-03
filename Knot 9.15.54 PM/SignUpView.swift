import SwiftUI

// MARK: - Sign Up Landing Screen
struct SignUpView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {

                Spacer()

                // Header
                Text("Create your Knot account")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 8)

                // Social Sign Up Buttons
                VStack(spacing: 12) {
                    SocialLoginButton(label: "Continue with Google", icon: "globe")
                    SocialLoginButton(label: "Continue with Apple", icon: "apple.logo")
                    SocialLoginButton(label: "Continue with Facebook", icon: "f.circle.fill")
                }

                // Divider
                HStack {
                    Rectangle().frame(height: 1).foregroundColor(Color(.systemGray4))
                    Text("or").foregroundColor(.gray).font(.footnote)
                    Rectangle().frame(height: 1).foregroundColor(Color(.systemGray4))
                }

                // Create Account Button
                NavigationLink(destination: CreateAccountView()) {
                    Text("Create Account")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .cornerRadius(12)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Sign Up")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Create Account Form Screen
struct CreateAccountView: View {
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

    // Error states
    @State private var emailError = ""
    @State private var phoneError = ""
    @State private var passwordError = ""
    @State private var verifyPasswordError = ""

    // Success alert
    @State private var showSuccessAlert = false
    @State private var navigateToVerification = false
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
                if selectedCountry.minDigits == selectedCountry.maxDigits {
                    phoneError = "Phone number must be \(selectedCountry.minDigits) digits for \(selectedCountry.name)"
                } else {
                    phoneError = "Phone number must be \(selectedCountry.minDigits)–\(selectedCountry.maxDigits) digits for \(selectedCountry.name)"
                }
                valid = false
            } else {
                phoneError = ""
            }
        } else {
            if email.isEmpty || !isValidEmail(email) {
                emailError = "Check email — enter a valid email address"
                valid = false
            } else {
                emailError = ""
            }
        }

        // Password length check
        if password.count < 8 {
            passwordError = "Password must be at least 8 characters"
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

    var body: some View {
        VStack(spacing: 20) {

            Spacer()

            // Header
            Text("Let's get you set up")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.black)

            Spacer().frame(height: 8)

            // Form Fields
            VStack(spacing: 12) {

                // Name
                TextField("Name", text: $name)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                // Email or Phone Toggle
                VStack(alignment: .leading, spacing: 6) {
                    if usePhone {
                        HStack(spacing: 0) {
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

                            TextField("Enter phone number", text: $phone)
                                .keyboardType(.phonePad)
                                .padding()
                                .background(phoneError.isEmpty ? Color(.systemGray6) : Color.red.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(phoneError.isEmpty ? Color.clear : Color.red, lineWidth: 1.5)
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
                            Text("Enter email instead").font(.caption).foregroundColor(.gray)
                        }

                    } else {
                        TextField("Enter email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .padding()
                            .background(emailError.isEmpty ? Color(.systemGray6) : Color.red.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(emailError.isEmpty ? Color.clear : Color.red, lineWidth: 1.5)
                            )
                            .cornerRadius(12)
                            .onChange(of: email) { _ in
                                emailError = email.isEmpty || isValidEmail(email) ? "" : "Check email — enter a valid email address"
                            }

                        if !emailError.isEmpty {
                            Text(emailError).font(.caption).foregroundColor(.red)
                        }

                        Button(action: { usePhone = true; emailError = "" }) {
                            Text("Enter phone number instead").font(.caption).foregroundColor(.gray)
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
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(passwordError.isEmpty ? Color(.systemGray6) : Color.red.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(passwordError.isEmpty ? Color.clear : Color.red, lineWidth: 1.5)
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
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(verifyPasswordError.isEmpty ? Color(.systemGray6) : Color.red.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(verifyPasswordError.isEmpty ? Color.clear : Color.red, lineWidth: 1.5)
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

    // Join Knot Button
            Button(action: {
                if validate() {
                    showSuccessAlert = true
                }
            }) {
                Text("Join Knot")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .cornerRadius(12)
            }
            .alert("Account created successfully.", isPresented: $showSuccessAlert) {
                Button("Continue") {
                    navigateToVerification = true
                }
            }

            // Hidden navigation link to verification screen
            NavigationLink(destination: EmailVerificationView(email: usePhone ? phone : email, name: name, isPhone: usePhone), isActive: $navigateToVerification) {
                EmptyView()
            }

            // Hidden navigation link to birthday screen
            NavigationLink(destination: BirthdayView(name: name), isActive: $navigateToBirthday) {
                EmptyView()
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Create Account")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerView(selectedCountry: $selectedCountry, isPresented: $showCountryPicker)
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
    @FocusState private var focusedIndex: Int?

    var otpString: String { otp.joined() }

    var contactDisplay: String {
        isPhone ? "your phone number" : email
    }

    var body: some View {
        VStack(spacing: 28) {

            Spacer()

            // Icon
            Image(systemName: isPhone ? "phone.circle.fill" : "envelope.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.black)

            // Header
            Text(isPhone ? "Verify your number" : "Verify your email")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.black)

            // Subtext
            VStack(spacing: 8) {
                Text("We sent a 6-digit code to")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Text(contactDisplay)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
            }

            // OTP Boxes
            HStack(spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    TextField("", text: $otp[index])
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.title2.bold())
                        .frame(width: 44, height: 52)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(focusedIndex == index ? Color.black : Color.clear, lineWidth: 1.5)
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
                    // TODO: verify OTP with Supabase
                    // For now, any 6-digit code works
                    navigateToBirthday = true
                }
            }) {
                Text("Verify")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(otpString.count == 6 ? Color.black : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(otpString.count < 6)

            // Resend code
            Button(action: {
                // TODO: trigger Supabase to resend OTP
            }) {
                Text("Resend code")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            NavigationLink(destination: BirthdayView(name: name), isActive: $navigateToBirthday) {
                EmptyView()
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color.white.ignoresSafeArea())
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
                .foregroundColor(.black)
                .multilineTextAlignment(.center)

            Text("This helps us personalise your Knot experience.")
                .font(.subheadline)
                .foregroundColor(.gray)
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

            // Continue Button
            Button(action: {
                navigateToInterests = true
            }) {
                Text("Continue")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .cornerRadius(12)
            }

            NavigationLink(destination: InterestsView(age: age, name: name), isActive: $navigateToInterests) {
                EmptyView()
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(Color.white.ignoresSafeArea())
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
                .foregroundColor(.black)

            Text("Pick at least 3 interests to help us connect you with your community.")
                .font(.subheadline)
                .foregroundColor(.gray)
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
                            .background(isSelected ? Color.black : Color.white)
                            .foregroundColor(isSelected ? .white : .black)
                            .cornerRadius(20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(isSelected ? Color.black : Color(.systemGray3), lineWidth: 1)
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
                .foregroundColor(.gray)

            // Continue Button
            Button(action: {
                if selected.count >= minRequired {
                    navigateToWelcome = true
                } else {
                    showError = true
                }
            }) {
                Text("Continue")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)

            // Skip button
            Button(action: {
                navigateToWelcomeSkip = true
            }) {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 8)

            NavigationLink(destination: WelcomeView(name: name), isActive: $navigateToWelcomeSkip) {
                EmptyView()
            }

            NavigationLink(destination: LoadingView(name: name), isActive: $navigateToWelcome) {
                EmptyView()
            }
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("Customising Your Account")
        .navigationBarTitleDisplayMode(.inline)
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
                .foregroundColor(.black)

            Text("Calibrating your interests\(dots)")
                .font(.subheadline)
                .foregroundColor(.gray)
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
                    .fill(Color(.systemGray5))
                    .frame(height: 6)

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                    .frame(width: progress * (UIScreen.main.bounds.width - 80), height: 6)
            }
            .frame(height: 6)
            .padding(.horizontal, 40)

            Spacer()

            NavigationLink(destination: AddressView(name: name), isActive: $navigateToWelcome) {
                EmptyView()
            }
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
    }
}

// MARK: - Address View
struct AddressView: View {
    let name: String
    @State private var street      = ""
    @State private var city        = ""
    @State private var postalCode  = ""
    @State private var country     = ""
    @State private var navigateToWelcome = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 16)

                VStack(spacing: 8) {
                    Text("Where do you live?")
                        .font(.system(size: 28, weight: .bold)).foregroundColor(.black)
                        .multilineTextAlignment(.center)
                    Text("This is optional, but adding your address helps Knot show you the most relevant local groups, alerts, and neighbours.")
                        .font(.subheadline).foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Info banner
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill").foregroundColor(.black)
                    Text("Your address is private and never shared with other users.")
                        .font(.caption).foregroundColor(.black)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal)

                VStack(spacing: 14) {
                    TextField("Street address", text: $street)
                        .padding().background(Color(.systemGray6)).cornerRadius(12)
                    TextField("City", text: $city)
                        .padding().background(Color(.systemGray6)).cornerRadius(12)
                    HStack(spacing: 12) {
                        TextField("Postal code", text: $postalCode)
                            .padding().background(Color(.systemGray6)).cornerRadius(12)
                        TextField("Country", text: $country)
                            .padding().background(Color(.systemGray6)).cornerRadius(12)
                    }
                }
                .padding(.horizontal)

                Button(action: { navigateToWelcome = true }) {
                    Text("Continue")
                        .fontWeight(.semibold).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.black).cornerRadius(12)
                }
                .padding(.horizontal)

                Button(action: { navigateToWelcome = true }) {
                    Text("Skip for now")
                        .font(.subheadline).foregroundColor(.gray)
                }

                NavigationLink(destination: WelcomeView(name: name), isActive: $navigateToWelcome) {
                    EmptyView()
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden(false)
        .navigationTitle("Your Address")
        .navigationBarTitleDisplayMode(.inline)
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
                .foregroundColor(.black)
                .multilineTextAlignment(.center)

            Text(name)
                .font(.system(size: 36, weight: .heavy))
                .foregroundColor(.black)

            Text("You're all set. Let's get you connected with your community.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Let's go button
            Button(action: {
                navigateToDashboard = true
            }) {
                Text("Let's go")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.black)
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            NavigationLink(destination: MainTabView(name: name, onLogout: { navigateToDashboard = false }), isActive: $navigateToDashboard) {
                EmptyView()
            }

            Spacer()
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
    }
}


#Preview {
    SignUpView()
}
