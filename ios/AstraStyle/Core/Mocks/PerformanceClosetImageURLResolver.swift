//
//  PerformanceClosetImageURLResolver.swift
//  AstraStyle
//
//  Resolves the synthetic closet fixture to local bundled photos copied under
//  unique temporary paths. It never contacts a provider or the network.
//

import Foundation

struct PerformanceClosetImageURLResolver: ClosetImageURLResolving {
    private static let imageResourceNames = [
        "quiz-w-logo-1-a",
        "quiz-w-formality-1-a",
        "quiz-w-silhouette-1-a",
        "quiz-w-texture-1-a",
        "quiz-w-colour-1-a",
        "quiz-w-trend-1-a",
        "quiz-w-accessory-1-a",
        "quiz-w-contrast-1-a"
    ]

    private let imageURLsByIndex: [URL]

    init() {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("AstraStylePerformanceCloset", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let sourceURLs = Self.imageResourceNames.compactMap { name in
            Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "QuizImagery")
        }
        imageURLsByIndex = (0..<PerformanceClosetFixture.itemCount).compactMap { index in
            guard !sourceURLs.isEmpty else { return nil }
            let destination = folder.appendingPathComponent("item-\(index).jpg")
            if !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.copyItem(at: sourceURLs[index % sourceURLs.count], to: destination)
            }
            return fileManager.fileExists(atPath: destination.path) ? destination : nil
        }
    }

    func resolve(storagePath: String) async throws -> URL {
        guard let index = fixtureIndex(for: storagePath), imageURLsByIndex.indices.contains(index) else {
            throw AstraError.server("Couldn't load the performance fixture photo.")
        }
        return imageURLsByIndex[index]
    }

    func resolve(storagePaths: [String]) async throws -> [String: URL] {
        storagePaths.reduce(into: [:]) { result, path in
            guard let index = fixtureIndex(for: path), imageURLsByIndex.indices.contains(index) else { return }
            result[path] = imageURLsByIndex[index]
        }
    }

    private func fixtureIndex(for storagePath: String) -> Int? {
        guard let lastPathComponent = storagePath.split(separator: "/").last else { return nil }
        let itemIDString = lastPathComponent.replacingOccurrences(of: "-front.jpg", with: "")
        guard let itemID = UUID(uuidString: itemIDString),
              let lastUUIDComponent = itemID.uuidString.split(separator: "-").last,
              let oneBasedIndex = Int(lastUUIDComponent, radix: 16),
              (1...PerformanceClosetFixture.itemCount).contains(oneBasedIndex)
        else {
            return nil
        }
        return oneBasedIndex - 1
    }
}
