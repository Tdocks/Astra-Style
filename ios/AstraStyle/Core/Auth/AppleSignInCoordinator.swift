//
//  AppleSignInCoordinator.swift
//  AstraStyle
//
//  Bridges `ASAuthorizationController`'s delegate-based Sign in with Apple
//  flow into async/await (spec §7 "Sign in with Apple"), generating the
//  nonce pair `AppleSignInNonce` produces and attaching the hashed nonce to
//  the request per Apple/Supabase's documented flow.
//
//  `SwiftUI`'s built-in `SignInWithAppleButton` (used by
//  `App/RootView.swift`'s `SignedOutGateView`) wraps the same underlying
//  `ASAuthorizationController` API but only exposes it as an Apple-styled
//  button. `Features/Slice` needs to trigger the flow from an `AstraButton`
//  instead (design-system consistency — spec/CLAUDE.md "no hardcoded
//  values," and Apple's own button chrome can't be restyled with our
//  tokens), which requires driving `ASAuthorizationController` manually.
//

import AuthenticationServices
import Foundation
import UIKit

/// The result of a completed Sign in with Apple flow: the identity token
/// to exchange with the backend, plus the *raw* nonce that was hashed into
/// the request — both are required by
/// `AuthRepository.signInWithApple(identityToken:nonce:)`.
public struct AppleSignInResult: Equatable, Sendable {
    public let identityToken: String
    public let rawNonce: String

    public init(identityToken: String, rawNonce: String) {
        self.identityToken = identityToken
        self.rawNonce = rawNonce
    }
}

/// Testable seam over the Sign in with Apple flow — `SliceViewModel`
/// depends on this protocol, not `AppleSignInCoordinator` directly, so
/// view-model tests can drive success/failure/cancellation without
/// presenting real system UI.
public protocol AppleSignInProviding: Sendable {
    func performSignIn() async throws -> AppleSignInResult
}

/// Production `AppleSignInProviding`. `@unchecked Sendable`: the only
/// mutable state (`continuation`, `pendingRawNonce`) is guarded by
/// `continuationLock`, mirroring the pattern `LiveWeatherService`
/// (Core/Networking/Live) already uses to bridge a delegate-callback API
/// into a single `async` call.
public final class AppleSignInCoordinator: NSObject, AppleSignInProviding, @unchecked Sendable {
    private let continuationLock = NSLock()
    // `nonisolated(unsafe)`: mutation is manually synchronized by
    // `continuationLock`, not by actor isolation — these are written from
    // `performSignIn()` (main actor) and resumed from the `nonisolated`
    // `ASAuthorizationControllerDelegate` callbacks below, so they must be
    // reachable from both without the compiler inferring (and blocking on)
    // any single actor's isolation for them.
    nonisolated(unsafe) private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    nonisolated(unsafe) private var pendingRawNonce: String?

    override public init() {
        super.init()
    }

    /// Presents the system Sign in with Apple sheet and suspends until the
    /// user completes or cancels it. Must be called from the main actor
    /// since it drives UI presentation.
    @MainActor
    public func performSignIn() async throws -> AppleSignInResult {
        let rawNonce = try AppleSignInNonce.random()
        let hashedNonce = AppleSignInNonce.sha256(rawNonce)

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppleSignInResult, Error>) in
            continuationLock.lock()
            self.continuation = continuation
            self.pendingRawNonce = rawNonce
            continuationLock.unlock()
            controller.performRequests()
        }
    }

    nonisolated private func resume(with result: Result<AppleSignInResult, Error>) {
        continuationLock.lock()
        let pending = continuation
        continuation = nil
        pendingRawNonce = nil
        continuationLock.unlock()
        pending?.resume(with: result)
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    // Declared `nonisolated` explicitly (rather than relying on the
    // module's default actor isolation) so this always compiles as a
    // witness for `ASAuthorizationControllerDelegate`'s requirements
    // regardless of their own isolation — a `nonisolated` synchronous
    // function is a valid witness for both isolated and nonisolated
    // synchronous protocol requirements, whereas an implicitly-isolated
    // one is only valid for isolated requirements. Nothing in this method
    // touches main-actor-isolated state directly (`resume(with:)` is
    // lock-guarded and safe from any thread).
    nonisolated public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuationLock.lock()
        let rawNonce = pendingRawNonce
        continuationLock.unlock()

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            resume(with: .failure(AstraError.auth("Apple did not return a valid credential.")))
            return
        }
        guard let rawNonce else {
            resume(with: .failure(AstraError.auth("Your sign-in session expired. Please try again.")))
            return
        }
        guard
            let identityTokenData = credential.identityToken,
            let identityToken = String(data: identityTokenData, encoding: .utf8)
        else {
            resume(with: .failure(AstraError.auth("Apple did not return an identity token.")))
            return
        }

        resume(with: .success(AppleSignInResult(identityToken: identityToken, rawNonce: rawNonce)))
    }

    nonisolated public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            resume(with: .failure(AstraError.cancelled))
        } else {
            resume(with: .failure(AstraError.auth("Sign in with Apple failed. Please try again.")))
        }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    /// Called synchronously by `ASAuthorizationController` on the main
    /// thread as `performRequests()` begins presenting UI. Declared
    /// `nonisolated` (rather than relying on the module's default actor
    /// isolation) and uses `MainActor.assumeIsolated` because this is a
    /// plain, non-`async` delegate requirement that cannot itself `await`
    /// a hop onto the main actor.
    nonisolated public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
            return window ?? ASPresentationAnchor()
        }
    }
}
