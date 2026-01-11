import SwiftUI
import AppKit

@main
struct ClatteringApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var debouncer = KeyboardDebouncer.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[Clattering] Starting up...")

        // Check accessibility permissions (don't prompt - let menu handle it)
        let hasPermissions = KeyboardDebouncer.checkAccessibilityPermissions(prompt: false)
        print("[Clattering] Accessibility permissions: \(hasPermissions ? "granted" : "NOT granted")")

        // Set up status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: "Clattering")
            print("[Clattering] Menu bar icon created")
        }

        // Always start debouncing on launch
        debouncer.enabled = true
        print("[Clattering] Debouncing started with threshold: \(debouncer.threshold)ms")

        // Build menu after enabling (so checkmark state is correct)
        updateStatusIcon()
        setupMenu()

        print("[Clattering] Ready! Click the keyboard icon in the menu bar.")
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Status indicator
        let isActive = debouncer.isActuallyRunning

        let statusMenuItem = NSMenuItem()
        statusMenuItem.tag = 1
        if isActive {
            statusMenuItem.title = "Status: Active"
            let checkImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Active")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
            statusMenuItem.image = checkImage?.withSymbolConfiguration(config)
        } else if debouncer.enabled {
            statusMenuItem.title = "Status: Starting..."
            let warningImage = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemYellow])
            statusMenuItem.image = warningImage?.withSymbolConfiguration(config)
        } else {
            statusMenuItem.title = "Status: Disabled"
            statusMenuItem.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Disabled")
        }
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        // Help buttons (always add, but hide if not needed)
        let grantItem = NSMenuItem(title: "Grant Permissions...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        grantItem.tag = 2
        grantItem.target = self
        let warningIcon = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemYellow])
        grantItem.image = warningIcon?.withSymbolConfiguration(config)
        grantItem.isHidden = isActive || !debouncer.enabled
        menu.addItem(grantItem)

        let retryItem = NSMenuItem(title: "Retry", action: #selector(retryStart), keyEquivalent: "")
        retryItem.tag = 3
        retryItem.target = self
        retryItem.isHidden = isActive || !debouncer.enabled
        menu.addItem(retryItem)

        menu.addItem(NSMenuItem.separator())

        // Enable/Disable toggle
        let enableItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "e")
        enableItem.target = self
        enableItem.state = debouncer.enabled ? .on : .off
        menu.addItem(enableItem)

        menu.addItem(NSMenuItem.separator())

        // Threshold display and adjustment
        let thresholdItem = NSMenuItem(title: "Threshold: \(Int(debouncer.threshold)) ms", action: nil, keyEquivalent: "")
        thresholdItem.isEnabled = false
        menu.addItem(thresholdItem)

        // Threshold slider in a custom view
        let sliderItem = NSMenuItem()
        let sliderView = ThresholdSliderView(debouncer: debouncer) { [weak self] in
            self?.updateThresholdDisplay()
        }
        let hostingView = NSHostingView(rootView: sliderView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 40)
        sliderItem.view = hostingView
        menu.addItem(sliderItem)

        menu.addItem(NSMenuItem.separator())

        // Suppressed key count
        let countItem = NSMenuItem(title: "Suppressed: \(debouncer.suppressedKeyCount) keys", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        countItem.tag = 100 // Tag for updating later
        menu.addItem(countItem)

        let resetItem = NSMenuItem(title: "Reset Counter", action: #selector(resetCounter), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateThresholdDisplay() {
        if let menu = statusItem.menu,
           let thresholdItem = menu.items.first(where: { $0.title.starts(with: "Threshold:") }) {
            thresholdItem.title = "Threshold: \(Int(debouncer.threshold)) ms"
        }
    }

    // NSMenuDelegate - update menu items when it opens
    func menuWillOpen(_ menu: NSMenu) {
        // Update status
        let isActive = debouncer.isActuallyRunning
        if let statusMenuItem = menu.item(withTag: 1) {
            if isActive {
                statusMenuItem.title = "Status: Active"
                let checkImage = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Active")
                let config = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
                statusMenuItem.image = checkImage?.withSymbolConfiguration(config)
            } else if debouncer.enabled {
                statusMenuItem.title = "Status: Starting..."
                let warningImage = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")
                let config = NSImage.SymbolConfiguration(paletteColors: [.systemYellow])
                statusMenuItem.image = warningImage?.withSymbolConfiguration(config)
            } else {
                statusMenuItem.title = "Status: Disabled"
                statusMenuItem.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "Disabled")
            }
        }

        // Show/hide help buttons based on state
        let showHelpButtons = !isActive && debouncer.enabled
        menu.item(withTag: 2)?.isHidden = !showHelpButtons
        menu.item(withTag: 3)?.isHidden = !showHelpButtons

        // Update suppressed count
        if let countItem = menu.item(withTag: 100) {
            countItem.title = "Suppressed: \(debouncer.suppressedKeyCount) keys"
        }

        updateStatusIcon()
    }

    private func updateStatusIcon() {
        if let button = statusItem.button {
            let isActive = debouncer.isActuallyRunning
            if isActive {
                button.image = NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: "Clattering (Active)")
            } else {
                button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Clattering (Inactive)")
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func retryStart() {
        debouncer.enabled = false
        debouncer.enabled = true

        // Re-open menu after a short delay to show updated status
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupMenu()
            self?.updateStatusIcon()
            self?.statusItem.button?.performClick(nil)
        }
    }

    @objc private func toggleEnabled() {
        debouncer.enabled.toggle()
        updateStatusIcon()
        setupMenu()
    }

    @objc private func resetCounter() {
        debouncer.resetSuppressedCount()
        setupMenu()
    }

    @objc private func quit() {
        debouncer.enabled = false
        NSApplication.shared.terminate(nil)
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = "Clattering needs Accessibility permissions to filter keyboard events.\n\nPlease go to System Settings > Privacy & Security > Accessibility and enable Clattering."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

struct ThresholdSliderView: View {
    @ObservedObject var viewModel: ThresholdViewModel

    init(debouncer: KeyboardDebouncer, onUpdate: @escaping () -> Void) {
        self.viewModel = ThresholdViewModel(debouncer: debouncer, onUpdate: onUpdate)
    }

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: $viewModel.threshold, in: 1...200, step: 1)
                .frame(width: 180)
            Text("\(Int(viewModel.threshold)) ms")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

class ThresholdViewModel: ObservableObject {
    @Published var threshold: Double {
        didSet {
            debouncer.threshold = threshold
            onUpdate()
        }
    }

    private let debouncer: KeyboardDebouncer
    private let onUpdate: () -> Void

    init(debouncer: KeyboardDebouncer, onUpdate: @escaping () -> Void) {
        self.debouncer = debouncer
        self.threshold = debouncer.threshold
        self.onUpdate = onUpdate
    }
}
