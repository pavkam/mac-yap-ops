// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import AppKit

enum AgentRunPanelLayout {
    static let preferredExpandedSize = NSSize(width: 680, height: 560)
    static let compactSize = NSSize(width: 372, height: 84)
    static let bottomInset: CGFloat = 42
    static let compactTopTrailingInset: CGFloat = 16
    static let transitionDuration: TimeInterval = 0.42

    static func expandedSize(in visibleFrame: NSRect) -> NSSize {
        NSSize(
            width: min(preferredExpandedSize.width, visibleFrame.width),
            height: min(preferredExpandedSize.height, visibleFrame.height))
    }

    static func expandedFrame(in visibleFrame: NSRect) -> NSRect {
        let size = expandedSize(in: visibleFrame)
        let preferredX = visibleFrame.midX - (size.width / 2)
        let preferredY = visibleFrame.minY + bottomInset
        return clampedFrame(
            origin: NSPoint(x: preferredX, y: preferredY),
            size: size,
            in: visibleFrame)
    }

    static func compactFrame(minimizing _: NSRect, in visibleFrame: NSRect) -> NSRect {
        topRightAnchoredFrame(
            size: compactSize,
            topRight: NSPoint(
                x: visibleFrame.maxX - compactTopTrailingInset,
                y: visibleFrame.maxY - compactTopTrailingInset),
            in: visibleFrame)
    }

    static func expandedFrame(restoring frame: NSRect, in visibleFrame: NSRect) -> NSRect {
        topRightAnchoredFrame(
            size: expandedSize(in: visibleFrame),
            topRight: NSPoint(x: frame.maxX, y: frame.maxY),
            in: visibleFrame)
    }

    private static func topRightAnchoredFrame(
        size: NSSize,
        topRight: NSPoint,
        in visibleFrame: NSRect) -> NSRect
    {
        clampedFrame(
            origin: NSPoint(
                x: topRight.x - size.width,
                y: topRight.y - size.height),
            size: size,
            in: visibleFrame)
    }

    private static func clampedFrame(
        origin: NSPoint,
        size: NSSize,
        in visibleFrame: NSRect) -> NSRect
    {
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        return NSRect(
            x: min(max(origin.x, visibleFrame.minX), maximumX),
            y: min(max(origin.y, visibleFrame.minY), maximumY),
            width: size.width,
            height: size.height)
    }
}
