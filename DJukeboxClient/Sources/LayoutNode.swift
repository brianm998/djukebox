//
//  LayoutNode.swift
//  DJukeboxClient
//
//  The recursive layout tree for one window of the macOS dockable-panel
//  workspace: leaves are panels, splits arrange children along an axis with
//  per-child size fractions. Pure value type — mutations return new trees.
//

#if os(macOS)
import Foundation

public enum LayoutAxis: String, Codable, Sendable {
    case horizontal
    case vertical
}

public indirect enum LayoutNode: Identifiable, Sendable {
    case leaf(Panel)
    case split(id: UUID, axis: LayoutAxis, children: [LayoutNode], fractions: [Double])

    public var id: UUID {
        switch self {
        case .leaf(let panel):        return panel.id
        case .split(let id, _, _, _): return id
        }
    }

    // MARK: - Mutations (pure; return new trees)

    /// Remove the leaf carrying `id`. Splits left with one child collapse to that
    /// child; an empty subtree returns nil (caller closes the window).
    public func removingLeaf(id: UUID) -> LayoutNode? {
        switch self {
        case .leaf(let panel):
            return panel.id == id ? nil : self
        case .split(let sid, let axis, let children, let fractions):
            var keptChildren: [LayoutNode] = []
            var keptFractions: [Double] = []
            for (i, child) in children.enumerated() {
                if let kept = child.removingLeaf(id: id) {
                    keptChildren.append(kept)
                    keptFractions.append(i < fractions.count ? fractions[i] : 1.0)
                }
            }
            if keptChildren.isEmpty { return nil }
            if keptChildren.count == 1 { return keptChildren[0] }
            return .split(id: sid, axis: axis, children: keptChildren,
                          fractions: LayoutNode.normalize(keptFractions))
        }
    }

    /// Add a panel to this window: appended as a new child of the root split, or —
    /// if the root is a single leaf — wrapped into a new vertical split.
    public func appending(_ panel: Panel) -> LayoutNode {
        switch self {
        case .leaf:
            return .split(id: UUID(), axis: .vertical,
                          children: [self, .leaf(panel)], fractions: [0.5, 0.5])
        case .split(let sid, let axis, let children, let fractions):
            let newShare = 1.0 / Double(children.count + 1)
            let scaled = fractions.map { $0 * (1.0 - newShare) }
            return .split(id: sid, axis: axis,
                          children: children + [.leaf(panel)],
                          fractions: scaled + [newShare])
        }
    }

    /// Replace the fractions of the split identified by `splitID`.
    public func settingFractions(_ new: [Double], for splitID: UUID) -> LayoutNode {
        switch self {
        case .leaf:
            return self
        case .split(let sid, let axis, let children, let fractions):
            if sid == splitID && new.count == children.count {
                return .split(id: sid, axis: axis, children: children,
                              fractions: LayoutNode.normalize(new))
            }
            return .split(id: sid, axis: axis,
                          children: children.map { $0.settingFractions(new, for: splitID) },
                          fractions: fractions)
        }
    }

    /// Defensive cleanup after load: collapse degenerate splits and make every
    /// split's fractions match its child count and sum to 1.
    public func normalized() -> LayoutNode {
        switch self {
        case .leaf:
            return self
        case .split(let sid, let axis, let children, let fractions):
            let kids = children.map { $0.normalized() }
            if kids.count == 1 { return kids[0] }
            let f = fractions.count == kids.count
                ? fractions
                : Array(repeating: 1.0 / Double(kids.count), count: kids.count)
            return .split(id: sid, axis: axis, children: kids,
                          fractions: LayoutNode.normalize(f))
        }
    }

    static func normalize(_ fractions: [Double]) -> [Double] {
        guard !fractions.isEmpty else { return [] }
        let clamped = fractions.map { max(0.0, $0) }
        let sum = clamped.reduce(0, +)
        guard sum > 0 else {
            return Array(repeating: 1.0 / Double(fractions.count), count: fractions.count)
        }
        return clamped.map { $0 / sum }
    }

    // MARK: - Default

    /// Mirrors the classic macOS layout: a bands|albums|songs browse row on top,
    /// then controls, queue, search and history stacked beneath.
    public static func defaultLayout() -> LayoutNode {
        let browse = LayoutNode.split(
            id: UUID(), axis: .horizontal,
            children: [.leaf(Panel(.bands)), .leaf(Panel(.albums)), .leaf(Panel(.songs))],
            fractions: [0.33, 0.33, 0.34])
        return .split(
            id: UUID(), axis: .vertical,
            children: [browse,
                       .leaf(Panel(.playingControls)),
                       .leaf(Panel(.playingList)),
                       .leaf(Panel(.allSearch)),
                       .leaf(Panel(.history))],
            fractions: [0.42, 0.16, 0.18, 0.12, 0.12])
    }
}

// MARK: - Codable (discriminated)

extension LayoutNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, panel, id, axis, children, fractions
    }
    private enum NodeType: String, Codable { case leaf, split }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(NodeType.self, forKey: .type) {
        case .leaf:
            self = .leaf(try c.decode(Panel.self, forKey: .panel))
        case .split:
            self = .split(id: try c.decode(UUID.self, forKey: .id),
                          axis: try c.decode(LayoutAxis.self, forKey: .axis),
                          children: try c.decode([LayoutNode].self, forKey: .children),
                          fractions: try c.decode([Double].self, forKey: .fractions))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let panel):
            try c.encode(NodeType.leaf, forKey: .type)
            try c.encode(panel, forKey: .panel)
        case .split(let id, let axis, let children, let fractions):
            try c.encode(NodeType.split, forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(axis, forKey: .axis)
            try c.encode(children, forKey: .children)
            try c.encode(fractions, forKey: .fractions)
        }
    }
}
#endif
