import Foundation

@MainActor
public protocol StudioEstimateExporting {
    /// Returns a protected local image carrying its visual-estimate disclosure.
    /// The caller supplies a freshly signed URL for an owned completed result.
    func export(imageURL: URL) async throws -> URL
}
