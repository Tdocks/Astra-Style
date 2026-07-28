//
//  AppleSignInNonce.swift
//  AstraStyle
//
//  Nonce generation + SHA-256 hashing for Sign in with Apple, exactly as
//  Supabase's native "Login with Apple" flow requires (spec §7 "Sign in
//  with Apple"): the *raw* (unhashed) nonce is what gets sent to Supabase
//  for verification via `signInWithIdToken(credentials:)`, while its
//  SHA-256 *hash* is what's set on `ASAuthorizationAppleIDRequest.nonce`
//  and ends up embedded (still hashed) inside Apple's signed identity
//  token. Getting the two backwards compiles fine and fails silently at
//  the UI layer — Supabase just rejects the sign-in with a nonce-mismatch
//  error — which is exactly the failure mode this file exists to prevent.
//
//  See `AppleSignInCoordinator` for where this is actually wired into the
//  `ASAuthorizationAppleIDRequest` / Supabase exchange.
//

import CryptoKit
import Foundation
import Security

public enum AppleSignInNonce {
    /// Characters Apple's own sample code and Supabase's Sign in with
    /// Apple guide use for the raw nonce. Restricted to URL-safe/ASCII so
    /// the resulting string is always safe to embed in a request header or
    /// log line without further escaping.
    private static let charset: [Character] = Array(
        "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
    )

    /// A cryptographically random string suitable for use as a Sign in
    /// with Apple nonce.
    ///
    /// Throws rather than force-unwrapping/crashing if `SecRandomCopyBytes`
    /// ever fails (exceedingly rare on-device, but per house style — no
    /// force unwraps/`try!`/`fatalError` for a condition that is, in
    /// principle, recoverable by asking the user to try again).
    public static func random(length: Int = 32) throws -> String {
        guard length > 0 else {
            throw AstraError(category: .validation, message: "Nonce length must be positive.")
        }

        var result = ""
        result.reserveCapacity(length)
        var remainingLength = length

        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            guard status == errSecSuccess else {
                throw AstraError(
                    category: .unknown,
                    message: "Couldn't generate a secure sign-in token. Please try again."
                )
            }

            for random in randomBytes where remainingLength > 0 {
                // Reject bytes >= charset.count so every character has a
                // uniform selection probability (avoids modulo bias).
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }

    /// SHA-256 hex digest of `input`, lowercase, per the exact algorithm
    /// Apple's `ASAuthorizationAppleIDRequest.nonce` documentation and
    /// Supabase's Sign in with Apple guide both specify.
    public static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
