//
//  AstraChromeTabBar.swift
//  AstraStyle
//
//  The chrome is the system tab bar (SwiftUI `TabView`) so iOS 26 Liquid
//  Glass and content-behind-the-bar come for free. A sixth destination
//  still collapses into More — that's intended. This helper only tags the
//  system `UITabBar` so UI tests can find it.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Finds the system tab bar and sets `main.tabBar` for UI tests.
struct AstraSystemTabBarConfigurator: UIViewRepresentable {
    var identifier: String = "main.tabBar"

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            Self.configure(from: view, identifier: identifier, attempt: 0)
        }
    }

    #if canImport(UIKit)
    private static func configure(from view: UIView, identifier: String, attempt: Int) {
        guard let tabBar = findTabBar(from: view) else {
            guard attempt < 10 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                configure(from: view, identifier: identifier, attempt: attempt + 1)
            }
            return
        }
        tabBar.accessibilityIdentifier = identifier
    }

    private static func findTabBar(from view: UIView) -> UITabBar? {
        if let window = view.window {
            return firstTabBar(in: window)
        }
        var ancestor: UIView? = view.superview
        while let current = ancestor {
            if let bar = firstTabBar(in: current) { return bar }
            ancestor = current.superview
        }
        return nil
    }

    private static func firstTabBar(in root: UIView) -> UITabBar? {
        if let tabBar = root as? UITabBar { return tabBar }
        for subview in root.subviews {
            if let tabBar = firstTabBar(in: subview) { return tabBar }
        }
        return nil
    }
    #endif
}
