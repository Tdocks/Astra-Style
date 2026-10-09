import Foundation

public func isValidScannerBatchStoragePath(_ path: String, ownerID: UUID) -> Bool {
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
          !path.contains("\\"),
          !path.contains("%"),
          let filename = components.last else { return false }
    let filenameParts = filename.split(separator: ".", omittingEmptySubsequences: false)
    guard filenameParts.count == 2,
          let imageID = UUID(uuidString: String(filenameParts[0])),
          String(filenameParts[0]) == imageID.uuidString.lowercased(),
          ["jpg", "png"].contains(String(filenameParts[1])) else { return false }
    let owner = Substring(ownerID.uuidString.lowercased())
    let remote = components.count == 5 &&
        components[0] == "users" && components[1] == owner &&
        components[2] == "closet" && components[3] == "batch"
    let local = components.count == 3 &&
        components[0] == "guest-local" && components[1] == owner
    return remote || local
}

public struct ScannerBatchPendingEntry: Codable, Sendable {
    public let id: UUID
    public let data: Data
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let originalByteCount: Int
    public let deviceHints: GarmentDeviceHints?
    public let storagePath: String?
    public let analysis: ClosetItemAnalysisResult?
    public let analysisFailureReason: ClosetItemAnalysisFailureReason?

    public init(
        id: UUID,
        data: Data,
        pixelWidth: Int,
        pixelHeight: Int,
        originalByteCount: Int,
        deviceHints: GarmentDeviceHints?,
        storagePath: String?,
        analysis: ClosetItemAnalysisResult? = nil,
        analysisFailureReason: ClosetItemAnalysisFailureReason? = nil
    ) {
        self.id = id
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.originalByteCount = originalByteCount
        self.deviceHints = deviceHints
        self.storagePath = storagePath
        self.analysis = analysis
        self.analysisFailureReason = analysisFailureReason
    }
}

public struct ScannerBatchPendingRecord: Codable, Sendable {
    public let ownerID: UUID
    public let idempotencyKey: String
    public let entries: [ScannerBatchPendingEntry]
    public let selected: Int
    public let skippedOverLimit: Int
    public let couldNotLoad: Int
    public let unreadable: Int
    public let uploadFailed: Int
    public let isComplete: Bool
    public let consumedDraftIDs: Set<UUID>
    public let discardedDraftIDs: Set<UUID>

    public init(
        ownerID: UUID,
        idempotencyKey: String,
        entries: [ScannerBatchPendingEntry],
        selected: Int,
        skippedOverLimit: Int,
        couldNotLoad: Int,
        unreadable: Int,
        uploadFailed: Int,
        isComplete: Bool = false,
        consumedDraftIDs: Set<UUID> = [],
        discardedDraftIDs: Set<UUID> = []
    ) {
        self.ownerID = ownerID
        self.idempotencyKey = idempotencyKey
        self.entries = entries
        self.selected = selected
        self.skippedOverLimit = skippedOverLimit
        self.couldNotLoad = couldNotLoad
        self.unreadable = unreadable
        self.uploadFailed = uploadFailed
        self.isComplete = isComplete
        self.consumedDraftIDs = consumedDraftIDs
        self.discardedDraftIDs = discardedDraftIDs
    }

    private enum CodingKeys: String, CodingKey {
        case ownerID, idempotencyKey, entries, selected, skippedOverLimit
        case couldNotLoad, unreadable, uploadFailed, isComplete
        case consumedDraftIDs, discardedDraftIDs
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ownerID = try values.decode(UUID.self, forKey: .ownerID)
        idempotencyKey = try values.decode(String.self, forKey: .idempotencyKey)
        entries = try values.decode([ScannerBatchPendingEntry].self, forKey: .entries)
        selected = try values.decode(Int.self, forKey: .selected)
        skippedOverLimit = try values.decode(Int.self, forKey: .skippedOverLimit)
        couldNotLoad = try values.decode(Int.self, forKey: .couldNotLoad)
        unreadable = try values.decode(Int.self, forKey: .unreadable)
        uploadFailed = try values.decode(Int.self, forKey: .uploadFailed)
        isComplete = try values.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
        consumedDraftIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .consumedDraftIDs) ?? []
        discardedDraftIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .discardedDraftIDs) ?? []
    }
}

public protocol ScannerBatchPendingStoring: Sendable {
    func save(_ record: ScannerBatchPendingRecord) async throws
    func load(ownerID: UUID) async throws -> ScannerBatchPendingRecord?
    func remove(ownerID: UUID) async throws
}

/// Keeps batch retry inputs in protected, owner-keyed Application Support.
/// A pending record is intentionally not synced or backed up.
public actor FileScannerBatchPendingStore: ScannerBatchPendingStoring {
    public static let live = FileScannerBatchPendingStore()

    private let directoryURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("AstraStyle/ScannerBatch", isDirectory: true)
        self.fileManager = fileManager
    }

    public func save(_ record: ScannerBatchPendingRecord) async throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var directoryValues = URLResourceValues()
        directoryValues.isExcludedFromBackup = true
        var directory = directoryURL
        try directory.setResourceValues(directoryValues)

        let data = try JSONEncoder.astraDefault.encode(record)
        let destination = fileURL(ownerID: record.ownerID)
        let staged = directoryURL.appendingPathComponent(
            ".batch-\(record.ownerID.uuidString.lowercased())-\(UUID().uuidString.lowercased()).tmp"
        )
        try data.write(to: staged, options: .atomic)
        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: staged.path
            )
            var fileValues = URLResourceValues()
            fileValues.isExcludedFromBackup = true
            var protectedFile = staged
            try protectedFile.setResourceValues(fileValues)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fileManager.moveItem(at: staged, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }

    public func load(ownerID: UUID) async throws -> ScannerBatchPendingRecord? {
        let source = fileURL(ownerID: ownerID)
        guard fileManager.fileExists(atPath: source.path) else { return nil }
        let data = try Data(contentsOf: source)
        let record = try JSONDecoder.astraDefault.decode(ScannerBatchPendingRecord.self, from: data)
        guard record.ownerID == ownerID,
              UUID(uuidString: record.idempotencyKey) != nil,
              record.entries.allSatisfy({ entry in
                  guard let path = entry.storagePath else { return true }
                  return isValidScannerBatchStoragePath(path, ownerID: ownerID)
              }) else {
            throw AstraError.auth("A saved batch belongs to another account and cannot be resumed.")
        }
        return record
    }

    public func remove(ownerID: UUID) async throws {
        let source = fileURL(ownerID: ownerID)
        guard fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.removeItem(at: source)
    }

    private func fileURL(ownerID: UUID) -> URL {
        directoryURL.appendingPathComponent("batch-\(ownerID.uuidString.lowercased()).json")
    }

}

public actor InMemoryScannerBatchPendingStore: ScannerBatchPendingStoring {
    private var records: [UUID: ScannerBatchPendingRecord] = [:]

    public init() {}

    public func save(_ record: ScannerBatchPendingRecord) async throws {
        records[record.ownerID] = record
    }

    public func load(ownerID: UUID) async throws -> ScannerBatchPendingRecord? {
        records[ownerID]
    }

    public func remove(ownerID: UUID) async throws {
        records.removeValue(forKey: ownerID)
    }
}
