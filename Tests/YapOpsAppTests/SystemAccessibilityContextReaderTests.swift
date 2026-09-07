// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import ApplicationServices
import Foundation
import Testing
import YapOpsCore

@testable import YapOpsApp

struct SystemAccessibilityContextReaderTests {
    @Test func read_WhenSelectedRowsContainFileLinks_CapturesOnlySelectedDescendants() {
        let native = SelectedAccessibilityTree()
        native.set(3, [
            kAXSelectedRowsAttribute: native.elements([10, 20]),
            kAXChildrenAttribute: native.elements([10, 20, 30]),
        ])
        native.set(10, [kAXChildrenAttribute: native.elements([11])])
        native.set(11, [kAXChildrenAttribute: native.elements([12, 13])])
        native.set(13, [kAXURLAttribute: "file:///tmp/First%20File.txt" as NSString])
        native.set(20, [kAXChildrenAttribute: native.elements([21])])
        native.set(21, [kAXFilenameAttribute: "/tmp/Second File.txt" as NSString])
        native.set(30, [kAXURLAttribute: "file:///tmp/unselected.txt" as NSString])

        let result = SystemAccessibilityContextReader(native: native)
            .readContext(processIdentifier: 42)

        #expect(result.resources == [
            .init(uri: "file:///tmp/First%20File.txt", name: "First File.txt"),
            .init(uri: "file:///tmp/Second%20File.txt", name: "Second File.txt"),
        ])
        #expect(!native.readIDs.contains(30))
        #expect(result.status == .complete)
    }

    @Test func read_WhenSelectedChildAndRowMatch_ReadsTheSelectionOnce() {
        let native = SelectedAccessibilityTree()
        native.set(3, [
            kAXSelectedChildrenAttribute: native.elements([10]),
            kAXSelectedRowsAttribute: native.elements([10]),
        ])
        native.set(10, [kAXURLAttribute: "file:///tmp/one.txt" as NSString])

        let result = SystemAccessibilityContextReader(native: native)
            .readContext(processIdentifier: 42)

        #expect(result.resources.count == 1)
        #expect(native.readIDs.filter { $0 == 10 }.count == 1)
    }

    @Test func read_WhenSelectedChildrenCycle_PreservesSiblingLinkAndTerminates() {
        let native = SelectedAccessibilityTree()
        native.set(3, [kAXSelectedRowsAttribute: native.elements([10])])
        native.set(10, [kAXChildrenAttribute: native.elements([10, 11])])
        native.set(11, [kAXURLAttribute: "file:///tmp/one.txt" as NSString])

        let result = SystemAccessibilityContextReader(native: native)
            .readContext(processIdentifier: 42)

        #expect(result.resources.map(\.uri) == ["file:///tmp/one.txt"])
        #expect(native.readIDs.filter { $0 == 10 }.count == 1)
    }

    @Test func read_WhenSelectedSubtreeIsLarge_BoundsTraversal() {
        let native = SelectedAccessibilityTree()
        native.set(3, [kAXSelectedRowsAttribute: native.elements([10])])
        native.set(10, [kAXChildrenAttribute: native.elements(Array(100..<1_100))])

        let result = SystemAccessibilityContextReader(native: native)
            .readContext(processIdentifier: 42)

        #expect(result.resources.isEmpty)
        #expect(native.readIDs.count <= 66)
    }

    @Test func read_WhenNativeBudgetExpires_DoesNotStartMoreChildReads() {
        let native = SelectedAccessibilityTree()
        native.set(3, [kAXSelectedRowsAttribute: native.elements([10])])
        native.set(10, [kAXChildrenAttribute: native.elements([11])])
        native.set(11, [kAXURLAttribute: "file:///tmp/too-late.txt" as NSString])
        native.elapseAfterReading(10, milliseconds: 500)

        let result = SystemAccessibilityContextReader(native: native, now: native)
            .readContext(processIdentifier: 42)

        #expect(result.resources.isEmpty)
        #expect(!native.readIDs.contains(11))
        #expect(result.status == .failed)
    }

    @Test func read_WhenSelectedFolderContainsUnselectedRows_OnlyCapturesFolderLink() {
        let native = SelectedAccessibilityTree()
        native.set(3, [kAXSelectedRowsAttribute: native.elements([10])])
        native.set(10, [kAXChildrenAttribute: native.elements([20, 11])])
        native.set(20, [
            kAXRoleAttribute: kAXRowRole as NSString,
            kAXURLAttribute: "file:///tmp/unselected-child.txt" as NSString,
        ])
        native.set(11, [kAXURLAttribute: "file:///tmp/selected-folder/" as NSString])

        let result = SystemAccessibilityContextReader(native: native)
            .readContext(processIdentifier: 42)

        #expect(result.resources.map(\.uri) == ["file:///tmp/selected-folder/"])
    }

    @Test func read_WhenNestedRowIsAlsoSelected_PreservesExplicitSelectionOrder() {
        let native = SelectedAccessibilityTree()
        native.set(3, [kAXSelectedRowsAttribute: native.elements([10, 20])])
        native.set(10, [kAXChildrenAttribute: native.elements([20, 11])])
        native.set(20, [
            kAXRoleAttribute: kAXRowRole as NSString,
            kAXURLAttribute: "file:///tmp/selected-child.txt" as NSString,
        ])
        native.set(11, [kAXURLAttribute: "file:///tmp/selected-folder/" as NSString])

        let result = SystemAccessibilityContextReader(native: native)
            .readContext(processIdentifier: 42)

        #expect(result.resources.map(\.uri) == [
            "file:///tmp/selected-folder/", "file:///tmp/selected-child.txt",
        ])
    }
}

// Safety: the fake tree and observations are accessed only while holding `lock`.
private final class SelectedAccessibilityTree:
    AccessibilityNativeReading, MacContextNow, @unchecked Sendable
{
    private let lock = NSRecursiveLock()
    private var handles: [Int: AXUIElement] = [:]
    private var nodes: [Int: [String: AnyObject]] = [:]
    private var reads: [Int] = []
    private var timeAfterRead: [Int: UInt64] = [:]
    private var uptime: UInt64 = 0

    var readIDs: [Int] { lock.withLock { reads } }

    func uptimeMilliseconds() -> UInt64 { lock.withLock { uptime } }

    func elapseAfterReading(_ id: Int, milliseconds: UInt64) {
        lock.withLock { timeAfterRead[id] = milliseconds }
    }

    func set(_ id: Int, _ attributes: [String: AnyObject]) {
        lock.withLock { nodes[id] = attributes }
    }

    func elements(_ ids: [Int]) -> NSArray {
        ids.map(element) as NSArray
    }

    private func element(_ id: Int) -> AXUIElement {
        lock.withLock {
            if let handle = handles[id] { return handle }
            let handle = AXUIElementCreateApplication(Int32(30_000 + id))
            handles[id] = handle
            return handle
        }
    }

    func isProcessTrusted() -> Bool { true }
    func processExists(_ processIdentifier: Int32) -> Bool { true }
    func applicationElement(processIdentifier: Int32) -> AXUIElement { element(1) }
    func setMessagingTimeout(_ timeout: Float, for element: AXUIElement) -> AXError { .success }

    func copyElementAttribute(_ attribute: CFString, from element: AXUIElement) -> ElementRead {
        switch attribute as String {
        case kAXFocusedWindowAttribute: .init(element: self.element(2), error: .success)
        case kAXFocusedUIElementAttribute: .init(element: self.element(3), error: .success)
        default: .init(element: nil, error: .attributeUnsupported)
        }
    }

    func copyMultiple(_ attributes: [CFString], from element: AXUIElement) -> MultipleRead {
        lock.withLock {
            guard let id = handles.first(where: { $0.value === element })?.key else {
                return .init(values: [], error: .invalidUIElement, containsValueFailure: false)
            }
            reads.append(id)
            if let elapsed = timeAfterRead[id] { uptime = elapsed }
            return .init(
                values: attributes.map { nodes[id]?[$0 as String] ?? NSNull() },
                error: .success,
                containsValueFailure: false)
        }
    }
}
