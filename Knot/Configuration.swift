// Configuration.swift
// Reads values from the generated Info.plist, which are injected at build
// time by Config.xcconfig via the INFOPLIST_KEY_ build setting mechanism.
//
// If this crashes on launch with a fatalError, copy Knot/Config.xcconfig.example
// to Knot/Config.xcconfig and fill in the real values.

import Foundation

enum Configuration {
    static let supabaseURL          = "https://flwwgpgqoqntpdxygknj.supabase.co"
    static let supabaseAnonKey      = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZsd3dncGdxb3FudHBkeHlna25qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU5NDk1ODIsImV4cCI6MjA5MTUyNTU4Mn0.rwNcUGECCvuyvbH-1htToRw8Y1RRHudUHdwWli-tiBg"
    static let stripePublishableKey = "pk_test_51TeT1hHCGBV9qjrsba9vk1WH2nkgYFseeyLfsNZ6Hm1XXPezoxwhDpbKzChNxdBE3VUajEbYEQEdwK1MwWeCT7fb00LvfhJddm"
}
