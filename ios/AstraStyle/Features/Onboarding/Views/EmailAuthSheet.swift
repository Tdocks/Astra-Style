//
//  EmailAuthSheet.swift
//  AstraStyle
//
//  Email one-time-code sign-in (spec §6.2 "Continue with email", §7
//  "Authentication: Email magic link or OTP").
//
//  This exists because the Welcome screen's "Continue with Email" button was
//  wired to `router.presentModal(.paywall(...))` behind a "placeholder route
//  hook" comment — it opened the paywall. Spec §22's acceptance bar forbids
//  dead buttons, and a button that silently does the wrong thing is worse than
//  one that does nothing: it teaches the user the app is unpredictable.
//
//  `AuthRepository.requestEmailOTP` / `verifyEmailOTP` already existed. This is
//  the surface over them.
//

import SwiftUI

/// Two-step email sign-in: request a code, then verify it.
struct EmailAuthSheet: View {
    /// Which half of the flow is on screen. Modelled as a state machine rather
    /// than a pile of booleans so an impossible combination cannot be shown.
    private enum Step: Equatable {
        case enterEmail
        case enterCode(email: String)
    }

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    /// Called with the established session so the caller can route onward.
    let onAuthenticated: (AuthSession) -> Void
    /// When true, verifying the code links the current anonymous user
    /// instead of minting a second account.
    var linksAnonymousAccount = false

    @State private var step: Step = .enterEmail
    @State private var email = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AstraColor.backgroundPrimary.ignoresSafeArea()

                VStack(alignment: .leading, spacing: AstraSpacing.lg) {
                    header

                    switch step {
                    case .enterEmail:
                        emailField
                    case .enterCode(let address):
                        codeField(sentTo: address)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .astraText(.caption)
                            .foregroundStyle(AstraColor.destructive)
                            .accessibilityLabel(Text("Error: \(errorMessage)"))
                    }

                    primaryAction

                    Spacer()
                }
                .padding(.horizontal, AstraSpacing.pagePadding)
                .padding(.top, AstraSpacing.lg)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                        .foregroundStyle(AstraColor.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(AstraColor.backgroundPrimary)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: AstraSpacing.xs) {
            Text(step == .enterEmail
                 ? String(localized: "What's your email?")
                 : String(localized: "Check your inbox."))
                .astraText(.title2)
                .foregroundStyle(AstraColor.textPrimary)

            Text(step == .enterEmail
                 ? String(localized: "We'll send you a single-use code. No password to remember.")
                 : String(localized: "Enter the six-digit code we just sent you."))
                .astraText(.callout)
                .foregroundStyle(AstraColor.textSecondary)
        }
    }

    private var emailField: some View {
        TextField(String(localized: "you@example.com"), text: $email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isFieldFocused)
            .astraText(.body)
            .foregroundStyle(AstraColor.textPrimary)
            .padding(AstraSpacing.md)
            .background(AstraColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: AstraSpacing.buttonRadius))
            .frame(minHeight: AstraSize.minTapTarget)
            .accessibilityLabel(Text("Email address"))
            .onAppear { isFieldFocused = true }
    }

    private func codeField(sentTo address: String) -> some View {
        VStack(alignment: .leading, spacing: AstraSpacing.sm) {
            TextField(String(localized: "123456"), text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($isFieldFocused)
                .astraText(.title2)
                .tracking(6)
                .foregroundStyle(AstraColor.textPrimary)
                .padding(AstraSpacing.md)
                .background(AstraColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: AstraSpacing.buttonRadius))
                .frame(minHeight: AstraSize.minTapTarget)
                .accessibilityLabel(Text("Six digit code"))

            Button(String(localized: "Use a different email")) {
                step = .enterEmail
                code = ""
                errorMessage = nil
            }
            .buttonStyle(.astraTertiary)
            .accessibilityHint(Text("Sent to \(address)"))
        }
        .onAppear { isFieldFocused = true }
    }

    private var primaryAction: some View {
        AstraButton(
            title: step == .enterEmail
                ? String(localized: "Send Code")
                : String(localized: "Sign In"),
            isLoading: isWorking
        ) {
            Task { await submit() }
        }
        .disabled(isWorking || !isCurrentStepValid)
    }

    private var isCurrentStepValid: Bool {
        switch step {
        case .enterEmail:
            // Deliberately permissive. Client-side email validation that tries
            // to be clever rejects valid addresses; the server is the real
            // authority. This only catches obviously-incomplete input.
            let trimmed = email.trimmingCharacters(in: .whitespaces)
            return trimmed.contains("@") && trimmed.count >= 5
        case .enterCode:
            return code.count >= 6
        }
    }

    // MARK: - Actions

    private func submit() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let address = email.trimmingCharacters(in: .whitespaces).lowercased()

        do {
            switch step {
            case .enterEmail:
                try await container.authRepository.requestEmailOTP(email: address)
                step = .enterCode(email: address)
                code = ""
            case .enterCode(let sentTo):
                let session: AuthSession
                if linksAnonymousAccount {
                    session = try await container.authRepository.linkEmailIdentity(
                        email: sentTo,
                        code: code.trimmingCharacters(in: .whitespaces)
                    )
                } else {
                    session = try await container.authRepository.verifyEmailOTP(
                        email: sentTo,
                        code: code.trimmingCharacters(in: .whitespaces)
                    )
                }
                onAuthenticated(session)
                dismiss()
            }
        } catch let error as AstraError {
            errorMessage = error.message
        } catch {
            errorMessage = String(localized: "Something went wrong. Please try again.")
        }
    }
}
