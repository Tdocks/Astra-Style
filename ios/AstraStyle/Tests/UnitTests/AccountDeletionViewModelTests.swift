//
//  AccountDeletionViewModelTests.swift
//  AstraStyleTests
//
//  P7-PRIVACY-02: `DELETE /account` answers 202 before its own cascade
//  runs (`account/handler.ts`), so everything worth pinning here is about
//  what the VIEW MODEL refuses to claim — never `.completed`, never a
//  second in-flight request — rather than about the network call itself,
//  which `AstraAPIClient`/`LiveAuthRepository` already own.
//
//  The `AuthRepository` stub is hand-rolled rather than reusing
//  `Core/Mocks/MockAuthRepository`: that mock cannot be made to fail, and
//  half of what matters here is what happens when `deleteAccount()`
//  throws.
//

import Foundation
import Testing
@testable import AstraStyle

@Suite("AccountDeletionViewModel — P7-PRIVACY-02 deletion flow")
@MainActor
struct AccountDeletionViewModelTests {

    @Test("Tapping delete without acknowledging irreversibility does nothing — the toggle is a real gate, not decoration")
    func deleteIsANoOpWithoutAcknowledgment() async {
        let repository = StubAuthRepository(deleteOutcome: .success(makeStatus(.pending)))
        let viewModel = AccountDeletionViewModel(authRepository: repository)

        await viewModel.delete()

        #expect(viewModel.phase == .confirming)
        let callCount = await repository.deleteAccountCallCount
        #expect(callCount == 0)
    }

    @Test("Acknowledging and deleting reaches .started with the server's own status, and calls the repository exactly once")
    func successfulDeleteReachesStarted() async {
        let status = makeStatus(.pending)
        let repository = StubAuthRepository(deleteOutcome: .success(status))
        let viewModel = AccountDeletionViewModel(authRepository: repository)
        viewModel.hasAcknowledgedIrreversibility = true

        await viewModel.delete()

        #expect(viewModel.phase == .started(status))
        let callCount = await repository.deleteAccountCallCount
        #expect(callCount == 1)
    }

    @Test("A second delete() while already .started is a no-op — the view model never starts a second request on its own")
    func secondDeleteAfterStartedIsANoOp() async {
        let repository = StubAuthRepository(deleteOutcome: .success(makeStatus(.pending)))
        let viewModel = AccountDeletionViewModel(authRepository: repository)
        viewModel.hasAcknowledgedIrreversibility = true

        await viewModel.delete()
        await viewModel.delete()

        let callCount = await repository.deleteAccountCallCount
        #expect(callCount == 1)
    }

    @Test("A failed request reaches .failed with the thrown AstraError, not .started with a fabricated status")
    func failedDeleteReachesFailed() async {
        let error = AstraError.network("The network connection was lost.")
        let repository = StubAuthRepository(deleteOutcome: .failure(error))
        let viewModel = AccountDeletionViewModel(authRepository: repository)
        viewModel.hasAcknowledgedIrreversibility = true

        await viewModel.delete()

        #expect(viewModel.phase == .failed(error))
    }

    @Test("Retrying after a failure calls the repository again, and a since-fixed backend now reaches .started")
    func retryAfterFailureCanSucceed() async {
        let error = AstraError.server("The server encountered an error.")
        let status = makeStatus(.processing)
        let repository = StubAuthRepository(deleteOutcome: .failure(error))
        let viewModel = AccountDeletionViewModel(authRepository: repository)
        viewModel.hasAcknowledgedIrreversibility = true

        await viewModel.delete()
        #expect(viewModel.phase == .failed(error))

        await repository.setDeleteOutcome(.success(status))
        await viewModel.delete()

        #expect(viewModel.phase == .started(status))
        let callCount = await repository.deleteAccountCallCount
        #expect(callCount == 2)
    }

    @Test("A .processing status decodes and carries through unchanged — the idempotent-replay case the endpoint documents")
    func processingStatusIsHandled() async {
        let status = makeStatus(.processing)
        let repository = StubAuthRepository(deleteOutcome: .success(status))
        let viewModel = AccountDeletionViewModel(authRepository: repository)
        viewModel.hasAcknowledgedIrreversibility = true

        await viewModel.delete()

        guard case .started(let started) = viewModel.phase else {
            Issue.record("Expected .started, got \(viewModel.phase)")
            return
        }
        #expect(started.status == .processing)
    }

    // MARK: - Fixtures

    private func makeStatus(_ state: AccountDeletionStatus.RequestState) -> AccountDeletionStatus {
        AccountDeletionStatus(deletionID: UUID(), status: state)
    }
}

@Suite("AccountDeletionStatus — DELETE /account response decoding")
struct AccountDeletionStatusTests {

    @Test("Decodes the exact wire shape account/schema.ts's AccountDeletionStatusDTO sends")
    func decodesServerShape() throws {
        let id = UUID()
        let jsonString = """
        {"deletion_id":"\(id.uuidString)","status":"pending"}
        """
        let json = Data(jsonString.utf8)

        let decoded = try JSONDecoder().decode(AccountDeletionStatus.self, from: json)

        #expect(decoded.deletionID == id)
        #expect(decoded.status == .pending)
    }
}

/// Configurable `AuthRepository` double. An `actor` so tests can safely
/// read `deleteAccountCallCount` and flip the outcome mid-test from the
/// `@MainActor` view model's own call.
private actor StubAuthRepository: AuthRepository {
    enum DeleteOutcome {
        case success(AccountDeletionStatus)
        case failure(AstraError)
    }

    private var deleteOutcome: DeleteOutcome
    private(set) var deleteAccountCallCount = 0

    init(deleteOutcome: DeleteOutcome) {
        self.deleteOutcome = deleteOutcome
    }

    func setDeleteOutcome(_ outcome: DeleteOutcome) {
        deleteOutcome = outcome
    }

    func signInWithApple(identityToken: String, nonce: String) async throws -> AuthSession {
        throw AstraError(category: .unknown, message: "not used by this suite")
    }

    func requestEmailOTP(email: String) async throws {}

    func verifyEmailOTP(email: String, code: String) async throws -> AuthSession {
        throw AstraError(category: .unknown, message: "not used by this suite")
    }

    func signInAnonymously() async throws -> AuthSession {
        throw AstraError(category: .unknown, message: "not used by this suite")
    }

    func linkAppleIdentity(identityToken: String, nonce: String) async throws -> AuthSession {
        throw AstraError(category: .unknown, message: "not used by this suite")
    }

    func linkEmailIdentity(email: String, code: String) async throws -> AuthSession {
        throw AstraError(category: .unknown, message: "not used by this suite")
    }

    func restoreSession() async throws -> AuthSession? { nil }

    func signOut() async throws {}

    func deleteAccount() async throws -> AccountDeletionStatus {
        deleteAccountCallCount += 1
        switch deleteOutcome {
        case .success(let status):
            return status
        case .failure(let error):
            throw error
        }
    }
}
