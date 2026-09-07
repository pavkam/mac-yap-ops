// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import ApplicationServices
import Darwin
import Foundation
import YapOpsCore

protocol AccessibilityNativeReading: Sendable {
    func isProcessTrusted() -> Bool
    func processExists(_ processIdentifier: Int32) -> Bool
    func applicationElement(processIdentifier: Int32) -> AXUIElement
    func setMessagingTimeout(_ timeout: Float, for element: AXUIElement) -> AXError
    func copyElementAttribute(_ attribute: CFString, from element: AXUIElement) -> ElementRead
    func copyMultiple(_ attributes: [CFString], from element: AXUIElement) -> MultipleRead
}

struct SystemAccessibilityContextReader: AccessibilityContextReading {
    private static let messagingTimeout: Float = 0.1
    private static let maximumSelectedElements = MacContextSnapshot.maximumResources
    private static let maximumTraversalElements = 64
    private static let maximumTraversalDepth = 3
    private static let nativeBudgetMilliseconds: UInt64 = 500
    private let native: any AccessibilityNativeReading
    private let now: any MacContextNow

    init(
        native: any AccessibilityNativeReading = SystemAccessibilityNativeReader(),
        now: any MacContextNow = ContinuousMacContextNow()
    ) {
        self.native = native
        self.now = now
    }

    func readContext(processIdentifier: Int32) -> AccessibilityContextReadResult {
        let startedAt = now.uptimeMilliseconds()
        guard native.isProcessTrusted() else {
            return .init(status: .notAuthorized)
        }
        guard native.processExists(processIdentifier) else {
            return .init(status: .targetUnavailable)
        }

        let application = native.applicationElement(processIdentifier: processIdentifier)
        let timeoutError = native.setMessagingTimeout(Self.messagingTimeout, for: application)
        if timeoutError == .apiDisabled {
            return .init(status: .notAuthorized)
        }
        guard timeoutError == .success else {
            return .init(status: native.processExists(processIdentifier)
                ? .failed
                : .targetUnavailable)
        }

        var hadFailure = false
        let windowRead = native.copyElementAttribute(
            kAXFocusedWindowAttribute as CFString,
            from: application)
        let focusedRead = native.copyElementAttribute(
            kAXFocusedUIElementAttribute as CFString,
            from: application)
        if windowRead.error == .apiDisabled || focusedRead.error == .apiDisabled {
            return .init(status: .notAuthorized)
        }
        hadFailure = hadFailure || windowRead.hadFailure || focusedRead.hadFailure

        var windowTitle: String?
        var windowDocumentURL: String?
        if let window = windowRead.element {
            let read = native.copyMultiple(
                [kAXTitleAttribute as CFString, kAXDocumentAttribute as CFString],
                from: window)
            if read.error == .apiDisabled {
                return .init(status: .notAuthorized)
            }
            hadFailure = hadFailure || read.hadFailure
            windowTitle = Self.string(from: read.values[safe: 0])
            windowDocumentURL = Self.urlString(from: read.values[safe: 1])
        }

        var focusedDocumentURL: String?
        var focusedURL: String?
        var selectedText: String?
        var selectedElements: [AXUIElement] = []
        if let focusedElement = focusedRead.element {
            let read = native.copyMultiple(
                [
                    kAXSelectedTextAttribute as CFString,
                    kAXDocumentAttribute as CFString,
                    kAXURLAttribute as CFString,
                    kAXSelectedChildrenAttribute as CFString,
                    kAXSelectedRowsAttribute as CFString,
                ],
                from: focusedElement)
            if read.error == .apiDisabled {
                return .init(status: .notAuthorized)
            }
            hadFailure = hadFailure || read.hadFailure
            selectedText = Self.string(from: read.values[safe: 0])
            focusedDocumentURL = Self.urlString(from: read.values[safe: 1])
            focusedURL = Self.urlString(from: read.values[safe: 2])
            Self.appendElements(
                from: read.values[safe: 3],
                maximumCount: Self.maximumSelectedElements,
                to: &selectedElements)
            Self.appendElements(
                from: read.values[safe: 4],
                maximumCount: Self.maximumSelectedElements - selectedElements.count,
                to: &selectedElements)
        }

        let resourceRead = readSelectedResources(selectedElements, startedAt: startedAt)
        if resourceRead.status == .notAuthorized { return resourceRead }
        hadFailure = hadFailure || resourceRead.status == .failed

        let result = AccessibilityContextReadResult(
            status: hadFailure ? .failed : .complete,
            windowTitle: windowTitle,
            documentURL: focusedDocumentURL ?? focusedURL ?? windowDocumentURL,
            selectedText: selectedText,
            resources: resourceRead.resources)
        if hadFailure, !native.processExists(processIdentifier) {
            return .init(status: .targetUnavailable)
        }
        return result
    }

    private func readSelectedResources(
        _ selectedElements: [AXUIElement],
        startedAt: UInt64
    ) -> AccessibilityContextReadResult {
        var visited: [AXUIElement] = []
        var resources: [MacContextResource] = []
        var hadFailure = false
        for root in selectedElements {
            var pending = [(element: root, depth: 0)]
            while let (element, depth) = pending.popLast() {
                if depth > 0, selectedElements.contains(where: { CFEqual($0, element) }) {
                    continue
                }
                if visited.contains(where: { CFEqual($0, element) }) { continue }
                let currentTime = now.uptimeMilliseconds()
                guard visited.count < Self.maximumTraversalElements,
                      currentTime >= startedAt,
                      currentTime - startedAt < Self.nativeBudgetMilliseconds
                else {
                    return .init(status: .failed, resources: resources)
                }
                visited.append(element)
                let read = native.copyMultiple(
                    [kAXURLAttribute, kAXTitleAttribute, kAXFilenameAttribute,
                     kAXChildrenAttribute, kAXRoleAttribute].map { $0 as CFString },
                    from: element)
                if read.error == .apiDisabled { return .init(status: .notAuthorized) }
                hadFailure = hadFailure || read.hadFailure
                // An expanded selected folder may expose unselected rows below its cells.
                // Stay within the selected item's structural wrappers, then stop at its link.
                let role = Self.string(from: read.values[safe: 4])
                if depth > 0, let role,
                   [kAXRowRole, kAXListRole, kAXOutlineRole, kAXTableRole, kAXBrowserRole]
                    .contains(role)
                {
                    continue
                }
                if let resource = Self.resource(from: read) {
                    resources.append(resource)
                    break
                }
                guard depth < Self.maximumTraversalDepth else { continue }
                var children: [AXUIElement] = []
                Self.appendElements(
                    from: read.values[safe: 3],
                    maximumCount: Self.maximumTraversalElements - visited.count - pending.count,
                    to: &children)
                pending.append(contentsOf: children.reversed().map { ($0, depth + 1) })
            }
        }
        return .init(status: hadFailure ? .failed : .complete, resources: resources)
    }

    private static func resource(from read: MultipleRead) -> MacContextResource? {
        let filename = string(from: read.values[safe: 2])
        let fileURI = filename.flatMap { path -> String? in
            guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
            return URL(fileURLWithPath: path, isDirectory: false).absoluteString
        }
        guard let uri = urlString(from: read.values[safe: 0]) ?? fileURI else { return nil }
        let name = string(from: read.values[safe: 1])
            ?? filename.map { ($0 as NSString).lastPathComponent }
            ?? URL(string: uri)?.lastPathComponent
            ?? ""
        return .init(uri: uri, name: name)
    }

    private static func string(from value: AnyObject?) -> String? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        return value as? String
    }

    private static func urlString(from value: AnyObject?) -> String? {
        guard let value, !(value is NSNull) else {
            return nil
        }
        if let url = value as? URL {
            return url.absoluteString
        }
        return value as? String
    }

    private static func appendElements(
        from value: AnyObject?,
        maximumCount: Int,
        to elements: inout [AXUIElement]
    ) {
        guard maximumCount > 0, let values = value as? NSArray else {
            return
        }
        for index in 0..<min(maximumCount, values.count) {
            let value = values[index]
            guard CFGetTypeID(value as CFTypeRef) == AXUIElementGetTypeID() else {
                continue
            }
            elements.append(unsafeDowncast(value as AnyObject, to: AXUIElement.self))
        }
    }
}

struct SystemAccessibilityNativeReader: AccessibilityNativeReading {
    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func processExists(_ processIdentifier: Int32) -> Bool {
        guard processIdentifier > 0 else {
            return false
        }
        if Darwin.kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    func applicationElement(processIdentifier: Int32) -> AXUIElement {
        AXUIElementCreateApplication(processIdentifier)
    }

    func setMessagingTimeout(_ timeout: Float, for element: AXUIElement) -> AXError {
        AXUIElementSetMessagingTimeout(element, timeout)
    }

    func copyElementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> ElementRead {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        if error == .success,
           let value,
           CFGetTypeID(value) == AXUIElementGetTypeID()
        {
            return ElementRead(
                element: unsafeDowncast(value as AnyObject, to: AXUIElement.self),
                error: .success)
        }
        return ElementRead(element: nil, error: error)
    }

    func copyMultiple(
        _ attributes: [CFString],
        from element: AXUIElement
    ) -> MultipleRead {
        var copiedValues: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(
            element,
            attributes as CFArray,
            AXCopyMultipleAttributeOptions(rawValue: 0),
            &copiedValues)
        guard error == .success, let values = copiedValues as? [Any] else {
            return MultipleRead(values: [], error: error, containsValueFailure: false)
        }
        return MultipleRead(
            values: values.map { $0 as AnyObject },
            error: error,
            containsValueFailure: values.contains(where: Self.isFailureValue))
    }

    private static func isFailureValue(_ value: Any) -> Bool {
        guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else {
            return false
        }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .axError else {
            return false
        }
        var error = AXError.success
        guard AXValueGetValue(axValue, .axError, &error) else {
            return true
        }
        return error != .attributeUnsupported && error != .noValue
    }
}

struct ElementRead {
    let element: AXUIElement?
    let error: AXError

    var hadFailure: Bool {
        error != .success && error != .attributeUnsupported && error != .noValue
    }
}

struct MultipleRead {
    let values: [AnyObject]
    let error: AXError
    let containsValueFailure: Bool

    var hadFailure: Bool {
        (error != .success && error != .attributeUnsupported && error != .noValue)
            || containsValueFailure
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
