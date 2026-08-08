//
//  KeychainTokenStore.swift
//  AstraStyle
//
//  Minimal Keychain wrapper for persisting the current `AuthSession`
//  across launches (spec §7 "Session restoration"). Tokens never touch
//  UserDefaults or disk outside the Keychain.
//

import Foundation
import Security

public struct KeychainTokenStore: Sendable {
    private let service: String
    private let account = "astra.session"

    public init(service: String = Bundle.main.bundleIdentifier ?? "com.astrastyle.app") {
        self.service = service
    }

    public func save(_ session: AuthSession) throws {
        let payload = try JSONEncoder.astraKeychain.encode(PersistedSession(session: session))
        var query = baseQuery
        query[kSecValueData as String] = payload
        // Accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
        //
        // The default when this attribute is omitted is
        // `kSecAttrAccessibleWhenUnlocked`, which makes the item unreadable
        // whenever the device is locked — including the exact "kill and
        // relaunch" case this store exists for: a background app refresh,
        // a notification tap, or any other cold launch that can happen
        // before the user has unlocked the device this boot. Under the
        // default, `restoreSession()` would see `errSecItemNotFound`-like
        // failure and incorrectly route to `.signedOut` even though a
        // valid session exists.
        // - "AfterFirstUnlock" fixes that: the item becomes readable once
        //   the device has been unlocked at least once since boot, and
        //   *stays* readable even if the device is locked again — correct
        //   for a token that background work and early launches need.
        // - "ThisDeviceOnly" additionally excludes the item from an
        //   unencrypted local backup being restored onto a *different*
        //   physical device. A session/refresh token silently carrying
        //   over to a new device via backup restore is a session-hijack
        //   vector the app doesn't need to support — a genuinely new
        //   device should re-authenticate, not inherit a live session.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let deleteStatus = SecItemDelete(baseQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw AstraError.auth("Failed to update stored session.")
        }

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AstraError.auth("Failed to save session to Keychain.")
        }
    }

    public func load() throws -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            let persisted = try JSONDecoder.astraKeychain.decode(PersistedSession.self, from: data)
            return persisted.session
        case errSecItemNotFound:
            return nil
        default:
            throw AstraError.auth("Failed to read session from Keychain.")
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AstraError.auth("Failed to clear stored session.")
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// A `Codable` mirror of `AuthSession` (which is not itself `Codable` to
/// avoid tempting call sites into round-tripping it through anything other
/// than the Keychain).
private struct PersistedSession: Codable {
    let userID: UUID
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    /// Decoded but unused. A Keychain item written by a build that still
    /// had guest mode carries this key, and dropping the property outright
    /// would make that item fail to decode — which `SessionStore
    /// .restoreSession()` treats as a corrupt entry, clears, and routes to
    /// Welcome. That is a survivable outcome (sign in again), but silently
    /// signing out every existing user on upgrade is not the same thing as
    /// removing a feature, so the key is tolerated and ignored.
    ///
    /// Note the value is not honoured: a restored *guest* session becomes
    /// an ordinary session with an empty access token, whose first
    /// authenticated call fails and routes to sign-in. That is the correct
    /// destination for a guest after ADR 0014; there is no account to
    /// restore him to.
    ///
    /// Safe to delete once no installed build can still be holding one.
    private let isGuest: Bool?

    init(session: AuthSession) {
        userID = session.userID
        accessToken = session.accessToken
        refreshToken = session.refreshToken
        expiresAt = session.expiresAt
        isGuest = nil
    }

    var session: AuthSession {
        AuthSession(userID: userID, accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }
}

extension JSONEncoder {
    fileprivate static let astraKeychain: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    fileprivate static let astraKeychain: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
