//
//  MockClosetImageURLResolver.swift
//  AstraStyle
//
//  In-memory `ClosetImageURLResolving` for previews/tests. Pairs with
//  `MockClosetRepository`, whose `fetchImages(forItem:)` hands out storage
//  paths like `preview/<uuid>-front.jpg`.
//
//  WHAT THIS DELIBERATELY DOES NOT DO: return a URL that resolves. The
//  repo ships no bundled garment photography, so there is nothing truthful
//  to point at, and inventing a real image URL would make previews render
//  a photograph the app cannot actually show. The host is under
//  `.invalid`, the TLD RFC 2606 reserves for exactly this and which is
//  guaranteed never to resolve — so `AstraRemoteImage` falls through to
//  its no-photo state, which IS what a preview of a closet with no photos
//  should look like. Point `stubbedHost` at a real host when you want a
//  preview with pictures in it.
//

import Foundation

public struct MockClosetImageURLResolver: ClosetImageURLResolving {
    private let stubbedHost: String

    public init(stubbedHost: String = "https://images.astrastyle.invalid") {
        self.stubbedHost = stubbedHost
    }

    public func resolve(storagePath: String) async throws -> URL {
        guard let url = stubbedURL(for: storagePath) else {
            // No force unwrap and no `fatalError`, even in a mock: a path
            // that won't percent-encode is a real (if unlikely) input, and
            // a preview crash is a worse way to learn about it than the
            // same error the live resolver would throw.
            throw AstraError.server(String(localized: "Couldn't load that photo.", comment: "Closet image could not be resolved"))
        }
        return url
    }

    public func resolve(storagePaths: [String]) async throws -> [String: URL] {
        // Mirrors the live contract: unresolvable paths are omitted, not
        // thrown, so a screen tested against this mock exercises the same
        // "some tiles have no URL" branch it will meet in production.
        storagePaths.reduce(into: [:]) { result, path in
            result[path] = stubbedURL(for: path)
        }
    }

    private func stubbedURL(for storagePath: String) -> URL? {
        guard let encoded = storagePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(stubbedHost)/\(encoded)")
    }
}
