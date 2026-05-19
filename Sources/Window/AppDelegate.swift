import AppKit
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: WindowController!
    private var statusItem: NSStatusItem?
    private var selectionOverlay: SelectionOverlayController?
    private let hotkeyManager = HotkeyManager()
    private var sharedViewModel: MacSynergyViewModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        sharedViewModel = MacSynergyViewModel()
        windowController = WindowController(viewModel: sharedViewModel)

        registerToggleHotkey()
        setupMenuBarItem()

        // Always start — AX calls inside SelectionMonitor return nil gracefully if permission is missing.
        // Never gate on AXIsProcessTrusted(): ad-hoc re-signing changes the binary hash each build,
        // which causes TCC to forget the grant even when the user added the app.
        startSelectionOverlay()

        // Trigger the system Accessibility dialog on first launch (non-blocking).
        promptAccessibilityIfNeeded()
    }

    // MARK: - Selection Overlay

    private func startSelectionOverlay() {
        let overlay = SelectionOverlayController()
        overlay.windowController = windowController
        overlay.viewModel = sharedViewModel
        overlay.start()
        selectionOverlay = overlay
    }

    // MARK: - Accessibility prompt (one-time dialog, never blocks the app)

    private func promptAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        // Shows the system "MacSynergy wants Accessibility access" alert.
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Menu Bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "MacSynergy")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "MacSynergy 열기  (Shift+Space)",
                                action: #selector(showApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "접근성 설정 열기 (텍스트 선택 기능)",
                                action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "MacSynergy 종료",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func showApp() { windowController.show() }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Global Hotkey (Carbon — no Accessibility needed)

    private func registerToggleHotkey() {
        hotkeyManager.onHotkeyPressed = { [weak self] in
            self?.windowController.toggle()
        }
        hotkeyManager.register(keyCode: 49, modifiers: UInt32(shiftKey))

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 49 where event.modifierFlags.contains(.shift):
                self?.windowController.toggle()
                return nil
            case 53:
                self?.windowController.hide()
                return nil
            default:
                return event
            }
        }
    }
}
