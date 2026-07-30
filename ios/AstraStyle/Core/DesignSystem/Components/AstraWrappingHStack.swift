//
//  AstraWrappingHStack.swift
//  AstraStyle
//
//  A row of items that wraps onto as many lines as it needs.
//
//  Exists because the alternative kept producing the same accessibility bug.
//  Chips in a plain `HStack` compress until their labels truncate; chips in a
//  horizontal `ScrollView` slide off the right edge with no scroll indicator,
//  which is worse — a truncated option at least announces that it is there. The
//  §6.6 measurements screen shipped the scroller version and at the largest text
//  size it put "Regular" half off the screen with two further options entirely
//  invisible and no affordance suggesting a sideways swipe.
//
//  A `Layout` rather than a hand-rolled VStack-of-HStacks. The manual approach
//  needs to know each item's width before it can decide where the rows break,
//  which SwiftUI will not tell you outside a layout context, so implementations
//  end up guessing from character counts and are wrong at every text size but
//  the one they were tuned against. `Layout` is given the real subview sizes.
//

import SwiftUI

public struct AstraWrappingHStack: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = AstraSpacing.xs, lineSpacing: CGFloat? = nil) {
        self.spacing = spacing
        // Defaults to the horizontal spacing. Equal gaps read as a grid; a
        // larger vertical gap makes two wrapped lines look like two groups.
        self.lineSpacing = lineSpacing ?? spacing
    }

    public func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        // `proposal.width` is nil when the parent is asking for the ideal size
        // and .infinity when it is offering everything it has. Neither is a
        // width to wrap against, so fall back to the unwrapped total rather
        // than wrapping at a nonsense boundary.
        let maxWidth = proposal.width.map { $0.isFinite ? $0 : .greatestFiniteMagnitude }
            ?? .greatestFiniteMagnitude
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)

        let height = rows.reduce(into: CGFloat.zero) { total, row in
            total += row.height
        } + lineSpacing * CGFloat(max(0, rows.count - 1))

        let widest = rows.map(\.width).max() ?? 0
        return CGSize(width: min(widest, maxWidth), height: height)
    }

    public func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    // MARK: - Row breaking

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthWithItem = current.indices.isEmpty
                ? size.width
                : current.width + spacing + size.width

            // The `!current.indices.isEmpty` guard matters: an item wider than
            // the whole container must still be placed, on a line of its own,
            // rather than pushed to an empty row forever. At accessibility sizes
            // a single chip genuinely can exceed the available width.
            if widthWithItem > maxWidth && !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = widthWithItem
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
