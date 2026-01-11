import Foundation
import CoreGraphics
import AppKit

class KeyboardDebouncer {
    static let shared = KeyboardDebouncer()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastKeyDownTimes: [CGKeyCode: Double] = [:]
    private var lastKeyUpTimes: [CGKeyCode: Double] = [:]
    private var thresholdMs: Double = 100.0
    private var isEnabled: Bool = false
    private var suppressedCount: Int = 0
    private var isRunning: Bool = false

    private let queue = DispatchQueue(label: "com.clattering.debouncer")

    private init() {
        loadSettings()
    }

    var threshold: Double {
        get { thresholdMs }
        set {
            thresholdMs = newValue
            UserDefaults.standard.set(newValue, forKey: "debounceThreshold")
            print("[Clattering] Threshold set to \(newValue)ms")
        }
    }

    var enabled: Bool {
        get { isEnabled }
        set {
            isEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: "debounceEnabled")
            if newValue && !isRunning {
                start()
            } else if !newValue && isRunning {
                stop()
            }
        }
    }

    var suppressedKeyCount: Int {
        return suppressedCount
    }

    func resetSuppressedCount() {
        suppressedCount = 0
    }

    private func loadSettings() {
        if UserDefaults.standard.object(forKey: "debounceThreshold") != nil {
            thresholdMs = UserDefaults.standard.double(forKey: "debounceThreshold")
        }
        if UserDefaults.standard.object(forKey: "debounceEnabled") != nil {
            isEnabled = UserDefaults.standard.bool(forKey: "debounceEnabled")
        } else {
            isEnabled = true // Default to enabled
        }
    }

    func start() {
        guard eventTap == nil else {
            print("[Clattering] Event tap already exists")
            return
        }

        print("[Clattering] Creating event tap...")

        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        // Store self pointer for callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }

                let debouncer = Unmanaged<KeyboardDebouncer>.fromOpaque(refcon).takeUnretainedValue()

                // Handle tap disabled events (system disables tap if it takes too long)
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    print("[Clattering] Event tap was disabled, re-enabling...")
                    CGEvent.tapEnable(tap: debouncer.eventTap!, enable: true)
                    return Unmanaged.passRetained(event)
                }

                guard type == .keyDown || type == .keyUp else {
                    return Unmanaged.passRetained(event)
                }

                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let isKeyDown = type == .keyDown

                if debouncer.shouldSuppressKey(keyCode: keyCode, isKeyDown: isKeyDown) {
                    print("[Clattering] SUPPRESSED \(isKeyDown ? "keyDown" : "keyUp") \(keyCode)")
                    return nil // Suppress the event
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: selfPtr
        ) else {
            print("[Clattering] ERROR: Failed to create event tap. Will retry in 1 second...")
            // Retry after delay (permissions might be granted soon)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, self.isEnabled && !self.isRunning else { return }
                self.start()
            }
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            isRunning = true
            print("[Clattering] Event tap started successfully!")
        } else {
            print("[Clattering] ERROR: Failed to create run loop source")
        }
    }

    func stop() {
        print("[Clattering] Stopping event tap...")
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        lastKeyDownTimes.removeAll()
        lastKeyUpTimes.removeAll()
        isRunning = false
        print("[Clattering] Event tap stopped")
    }

    private func shouldSuppressKey(keyCode: CGKeyCode, isKeyDown: Bool) -> Bool {
        let now = Date().timeIntervalSince1970 * 1000 // Convert to ms

        var shouldSuppress = false

        queue.sync {
            let lastTimes = isKeyDown ? lastKeyDownTimes : lastKeyUpTimes
            if let lastTime = lastTimes[keyCode] {
                let elapsed = now - lastTime
                if elapsed < thresholdMs {
                    shouldSuppress = true
                    suppressedCount += 1
                }
            }

            if !shouldSuppress {
                if isKeyDown {
                    lastKeyDownTimes[keyCode] = now
                } else {
                    lastKeyUpTimes[keyCode] = now
                }
            }
        }

        return shouldSuppress
    }

    static func checkAccessibilityPermissions(prompt: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    var isActuallyRunning: Bool {
        return isRunning
    }
}
