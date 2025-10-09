//
//  Extensions.swift
//  Prism
//
//  Core cross-cutting helpers (safe for macOS).
//

import Foundation
import SwiftUI
import Combine
import AppKit

// MARK: - Combine QoL

public extension Publisher where Failure == Never {
    /// Deliver values on the main thread and return a cancellable.
    @discardableResult
    func sinkOnMain(_ receiveValue: @escaping (Output) -> Void) -> AnyCancellable {
        receive(on: DispatchQueue.main)
            .sink(receiveValue: receiveValue)
    }
}

// MARK: - Keyboard handling for macOS SwiftUI
// Lets views react to specific key presses (used by Onboarding).

public enum KeyPress: Equatable {
    case leftArrow
    case rightArrow
    case `return`
}

public enum KeyPressResult {
    case handled
    case ignored
}

public extension View {
    /// Attach a key handler for a single key. The helper view tries to be first responder
    /// but won’t steal focus from the current first responder if one already exists.
    func onKeyPress(_ key: KeyPress, perform: @escaping () -> KeyPressResult) -> some View {
        overlay(KeyPressCatcher(key: key, perform: perform)) // overlay avoids affecting layout
    }
}

/// Invisible NSView that participates in the responder chain and intercepts keyDown.
private struct KeyPressCatcher: NSViewRepresentable {
    var key: KeyPress
    var perform: () -> KeyPressResult

    func makeNSView(context: Context) -> KeyCatcherView {
        KeyCatcherView(key: key, perform: perform)
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.key = key
        nsView.perform = perform
        // Only claim first responder if window has none or it’s already us
        DispatchQueue.main.async {
            guard let win = nsView.window else { return }
            if win.firstResponder !== nsView {
                // Don’t steal focus from text fields / search fields, etc.
                if win.firstResponder == nil || (win.firstResponder as? NSView)?.acceptsFirstResponder == false {
                    win.makeFirstResponder(nsView)
                }
            }
        }
    }
}

/// NSView subclass that captures key presses.
private final class KeyCatcherView: NSView {
    var key: KeyPress
    var perform: () -> KeyPressResult

    init(key: KeyPress, perform: @escaping () -> KeyPressResult) {
        self.key = key
        self.perform = perform
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true           // visually invisible
        canDrawConcurrently = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Try to join the chain without stealing focus aggressively.
        if window?.firstResponder == nil { window?.makeFirstResponder(self) }
    }

    override func keyDown(with event: NSEvent) {
        guard matches(event, key: key) else {
            super.keyDown(with: event)
            return
        }
        switch perform() {
        case .handled: break
        case .ignored: super.keyDown(with: event)
        }
    }

    private func matches(_ event: NSEvent, key: KeyPress) -> Bool {
        // Apple arrow key codes on macOS: left=123, right=124; return=36, keypad return=76
        switch key {
        case .leftArrow:  return event.keyCode == 123
        case .rightArrow: return event.keyCode == 124
        case .return:     return event.keyCode == 36 || event.keyCode == 76
        }
    }
}

// MARK: - Small convenience bits

public extension Optional where Wrapped == String {
    /// `true` when nil or only whitespace/newlines.
    var isNilOrBlank: Bool {
        switch self {
        case .none: return true
        case .some(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

public extension Date {
    /// Quick “time ago” string (1m, 2h, 3d).
    var shortRelativeDescription: String {
        let seconds = max(0, Int(Date().timeIntervalSince(self)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}
