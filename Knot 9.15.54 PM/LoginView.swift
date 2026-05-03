//
//  LoginView.swift
//  Knot
//
//  Created by Ruhaan Kumar on 23/3/26.
//
import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""

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
                    SocialLoginButton(label: "Continue with Google", icon: "globe")
                    SocialLoginButton(label: "Continue with Apple", icon: "apple.logo")
                    SocialLoginButton(label: "Continue with Facebook", icon: "f.circle.fill")
                }

                Spacer().frame(height: 8)

                // Email Field
                TextField("Enter email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                // Password Field
                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                // Login Button
                Button(action: {
                    // TODO: connect to Supabase auth
                }) {
                    Text("Login")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.black)
                        .cornerRadius(12)
                }

                // Sign Up Link
                NavigationLink(destination: SignUpView()) {
                    Text("Sign Up")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .background(Color.white.ignoresSafeArea())
        }
    }
}

// Reusable Social Login Button
struct SocialLoginButton: View {
    var label: String
    var icon: String

    var body: some View {
        Button(action: {
            // TODO: connect to Supabase auth
        }) {
            HStack {
                Image(systemName: icon)
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

// Placeholder Sign Up Screen
struct SignUpView: View {
    var body: some View {
        VStack {
            Text("Create your Knot account")
                .font(.system(size: 28, weight: .bold))
                .padding()
            Spacer()
            // TODO: build out sign up form
        }
        .navigationTitle("Sign Up")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    LoginView()
}

