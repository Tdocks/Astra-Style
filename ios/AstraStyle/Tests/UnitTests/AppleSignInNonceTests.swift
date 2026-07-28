//
//  AppleSignInNonceTests.swift
//  AstraStyleTests
//
//  Sign in with Apple's nonce generation + SHA-256 hashing (spec §7).
//  "Get this right" per the vertical-slice build instructions: Supabase's
//  replay check only works if the *raw* nonce round-trips unchanged and
//  its SHA-256 hash matches exactly what was sent as
//  `ASAuthorizationAppleIDRequest.nonce`.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("Apple Sign In nonce generation + hashing")
struct AppleSignInNonceTests {

    @Test("random() produces a string of the requested length")
    func randomProducesRequestedLength() throws {
        let nonce = try AppleSignInNonce.random(length: 32)
        #expect(nonce.count == 32)

        let shortNonce = try AppleSignInNonce.random(length: 8)
        #expect(shortNonce.count == 8)
    }

    @Test("random() only uses the documented URL-safe charset")
    func randomUsesSafeCharset() throws {
        let allowed = Set("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = try AppleSignInNonce.random(length: 128)
        #expect(nonce.allSatisfy { allowed.contains($0) })
    }

    @Test("random() is not deterministic across calls")
    func randomIsNotDeterministic() throws {
        let first = try AppleSignInNonce.random()
        let second = try AppleSignInNonce.random()
        #expect(first != second)
    }

    @Test("random() rejects a non-positive length rather than crashing")
    func randomRejectsInvalidLength() {
        #expect(throws: AstraError.self) {
            try AppleSignInNonce.random(length: 0)
        }
        #expect(throws: AstraError.self) {
            try AppleSignInNonce.random(length: -1)
        }
    }

    @Test(
        "sha256() matches known FIPS 180-2 SHA-256 test vectors",
        arguments: [
            ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ]
    )
    func sha256MatchesKnownVectors(input: String, expected: String) {
        #expect(expected.count == 64, "test vector itself must be a 64-char hex digest")
        #expect(AppleSignInNonce.sha256(input) == expected)
    }

    @Test("sha256() is deterministic for the same input")
    func sha256IsDeterministic() throws {
        let nonce = try AppleSignInNonce.random()
        #expect(AppleSignInNonce.sha256(nonce) == AppleSignInNonce.sha256(nonce))
    }

    @Test("sha256() of two different nonces does not collide in practice")
    func sha256DiffersForDifferentInput() throws {
        let first = try AppleSignInNonce.random()
        let second = try AppleSignInNonce.random()
        #expect(AppleSignInNonce.sha256(first) != AppleSignInNonce.sha256(second))
    }

    @Test("sha256() output is lowercase hex")
    func sha256OutputIsLowercaseHex() {
        let digest = AppleSignInNonce.sha256("astra")
        #expect(digest == digest.lowercased())
        #expect(digest.allSatisfy { $0.isHexDigit })
    }
}
