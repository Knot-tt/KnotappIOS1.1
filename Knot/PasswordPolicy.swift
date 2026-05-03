//
//  PasswordPolicy.swift
//  Knot
//
//  Single source of truth for password strength rules, used by both
//  CreateAccountView (sign-up) and PasswordResetView (password recovery).
//

import Foundation

enum PasswordPolicy {

    // MARK: - Rules

    private static let minLength   = 8
    private static let specialChars: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.invert()
        return cs
    }()

    // MARK: - API

    /// Human-readable checks with pass/fail for each rule — drives the strength indicator UI.
    static func checks(for password: String) -> [(label: String, passing: Bool)] {
        [
            ("At least \(minLength) characters",   password.count >= minLength),
            ("One uppercase letter (A–Z)",          password.rangeOfCharacter(from: .uppercaseLetters) != nil),
            ("One number (0–9)",                    password.rangeOfCharacter(from: .decimalDigits)    != nil),
            ("One special character (!@#$…)",       password.rangeOfCharacter(from: specialChars)      != nil),
        ]
    }

    /// Returns an array of failure messages — empty means the password passes all rules.
    static func validate(_ password: String) -> [String] {
        checks(for: password)
            .filter { !$0.passing }
            .map    {  $0.label   }
    }

    /// Returns a single consolidated error string, or nil if valid.
    static func errorMessage(for password: String) -> String? {
        let failures = validate(password)
        guard !failures.isEmpty else { return nil }
        if failures.count == 1 { return "Password needs: \(failures[0].lowercased())." }
        return "Password needs: \(failures.dropLast().map { $0.lowercased() }.joined(separator: ", ")), and \(failures.last!.lowercased())."
    }
}
