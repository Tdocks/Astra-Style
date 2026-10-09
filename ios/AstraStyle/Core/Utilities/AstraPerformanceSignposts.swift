//
//  AstraPerformanceSignposts.swift
//  AstraStyle
//
//  Opt-in signposts consumed by the performance acceptance UI tests and
//  Instruments. They carry no user or request data and are silent unless the
//  process is launched with `-astra-measure-performance`.
//

import Foundation
import os

enum AstraPerformanceSignposts {
    static let subsystem = "com.astrastyle.app"
    static let category = "Performance"

    private static let log = OSLog(subsystem: subsystem, category: category)

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-astra-measure-performance")
    }

    static func beginAppLaunch() {
        guard isEnabled else { return }
        os_signpost(.begin, log: log, name: "AppLaunchToInteractive", signpostID: .exclusive)
    }

    static func endAppLaunch() {
        guard isEnabled else { return }
        os_signpost(.end, log: log, name: "AppLaunchToInteractive", signpostID: .exclusive)
    }

    static func beginHomeRender() {
        guard isEnabled else { return }
        os_signpost(.begin, log: log, name: "HomeCachedRender", signpostID: .exclusive)
    }

    static func endHomeRender() {
        guard isEnabled else { return }
        os_signpost(.end, log: log, name: "HomeCachedRender", signpostID: .exclusive)
    }
}
