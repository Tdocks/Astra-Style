//
//  MockLabelTextRecognizer.swift
//  AstraStyle
//
//  Injectable `LabelTextRecognizing` for unit tests. Never touches Vision.
//

import CoreGraphics
import Foundation

public struct MockLabelTextRecognizerError: Error, Sendable, Equatable {
    public init() {}
}

public struct MockLabelTextRecognizer: LabelTextRecognizing, Sendable {
    public var lines: [String]
    public var error: MockLabelTextRecognizerError?

    public init(lines: [String] = [], error: MockLabelTextRecognizerError? = nil) {
        self.lines = lines
        self.error = error
    }

    public func recognizeText(in image: CGImage) throws -> [String] {
        _ = image
        if let error { throw error }
        return lines
    }
}
