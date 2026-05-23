import AppKit
import SwiftUI

private let menuWidth:  CGFloat = 220
private let menuHeight: CGFloat = 300

class SelectionOverlayController {
    private let monitor = SelectionMonitor()
    private var plusPanel: NSPanel?
    private var actionPanel: NSPanel?
    private var dismissMonitor: Any?
    // Fixed frame stored when menu opens — used for hit-testing in dismiss monitor.
    // Using a stored rect (not panel.frame) avoids reading frame during a layout pass.
    private var actionPanelFixedFrame: NSRect = .zero

    private var capturedText: String = ""
    private var plusButtonPosition: NSPoint = .zero
    private var targetApp: NSRunningApplication?

    weak var windowController: WindowController?
    weak var viewModel: MacSynergyViewModel?

    // MARK: - Lifecycle

    deinit {
        monitor.stop()
        removeDismissMonitor()
    }

    func start() {
        monitor.onDragDetected = { [weak self] mousePoint in
            guard let self else { return }
            self.plusButtonPosition = mousePoint
            self.targetApp = self.monitor.lastFrontmostApp
            self.capturedText = ""
            self.showPlusButton(at: mousePoint)
        }
        monitor.onMouseDown = { [weak self] in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            let inPlus   = self.plusPanel?.frame.contains(loc) ?? false
            // Use stored fixed frame — not panel.frame — so we never read frame mid-layout
            let inAction = self.actionPanelFixedFrame.contains(loc)
            if !inPlus && !inAction { self.hideAll() }
        }
        monitor.start()
    }

    func stop() {
        monitor.stop()
        hideAll()
    }

    // MARK: - Plus Button

    private func showPlusButton(at point: NSPoint) {
        let size: CGFloat = 32
        let gap:  CGFloat = 8

        var x = point.x + gap
        var y = point.y + gap

        if let screen = (NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main {
            let vis = screen.visibleFrame
            x = min(x, vis.maxX - size - 4)
            y = min(y, vis.maxY - size - 4)
            y = max(y, vis.minY + 4)
        }

        let frame = NSRect(x: x, y: y, width: size, height: size)

        if plusPanel == nil {
            plusPanel = makeBorderlessPanel(frame: frame, hasShadow: false)
            let hosting = NSHostingView(rootView: SelectionPlusButtonView { [weak self] in
                self?.onPlusTapped()
            })
            // Prevent SwiftUI from auto-resizing the panel
            hosting.sizingOptions = []
            hosting.frame = NSRect(origin: .zero, size: CGSize(width: size, height: size))
            plusPanel?.contentView = hosting
        }

        plusPanel?.setFrame(frame, display: true)
        plusPanel?.orderFront(nil)
    }

    // MARK: - + Tapped: capture text then show menu

    private func onPlusTapped() {
        let plusFrame = plusPanel?.frame
            ?? NSRect(x: plusButtonPosition.x, y: plusButtonPosition.y, width: 32, height: 32)

        // 1. Try Accessibility API to get selected text directly
        if let pid = targetApp?.processIdentifier,
           let text = readSelectedTextViaAX(pid: pid), !text.isEmpty {
            capturedText = text
            showActionMenu(near: plusFrame)
            return
        }

        // 2. Synthesise Cmd+C and wait for pasteboard to update
        let prevCount = NSPasteboard.general.changeCount
        synthesiseCopy()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self else { return }
            let pb = NSPasteboard.general
            if pb.changeCount != prevCount,
               let text = pb.string(forType: .string),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.capturedText = text
            } else {
                // 3. Fall back: use whatever is currently in clipboard
                self.capturedText = pb.string(forType: .string) ?? ""
            }
            self.showActionMenu(near: plusFrame)
        }
    }

    // MARK: - AX selected-text reader

    private func readSelectedTextViaAX(pid: pid_t) -> String? {
        let axApp = AXUIElementCreateApplication(pid)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp,
              kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else { return nil }

        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let focusedElement = focused as! AXUIElement

        var textRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement,
              kAXSelectedTextAttribute as CFString, &textRef) == .success,
              let text = textRef as? String, !text.isEmpty else { return nil }

        return text
    }

    // MARK: - Action Menu (FIXED SIZE — never resizes after creation)

    private func showActionMenu(near plusFrame: NSRect) {
        // Position: above and right-aligned to the + button's right edge
        var rightEdge = plusFrame.maxX
        var y = plusFrame.minY - menuHeight - 6

        if let screen = (NSScreen.screens.first { NSMouseInRect(plusFrame.origin, $0.frame, false) }) ?? NSScreen.main {
            let vis = screen.visibleFrame
            rightEdge = min(rightEdge, vis.maxX - 8)
            if y < vis.minY + 8 { y = plusFrame.maxY + 6 }
        }

        let frame = NSRect(x: rightEdge - menuWidth, y: y, width: menuWidth, height: menuHeight)
        // Store the fixed frame for hit-testing in dismiss monitor.
        // This is the canonical truth about where the panel is — we never call panel.frame
        // inside layout callbacks to avoid the constraint-exception crash.
        actionPanelFixedFrame = frame

        let text = capturedText
        let rootView = QuickActionMenuView(
            selectedText: text,
            onAction: { [weak self] action, prompt in self?.handleAction(action, prompt: prompt, text: text) },
            onExpand:  { [weak self] in self?.expandToMainWindow(text: text) },
            onDismiss: { [weak self] in self?.hideAll() }
        )
        let hosting = NSHostingView(rootView: rootView)
        // CRITICAL: prevent SwiftUI from auto-resizing the panel during layout passes.
        // Without this, NSHostingView.invalidateSafeAreaInsets fires inside a layout cycle
        // and throws NSInternalInconsistencyException → crash.
        hosting.sizingOptions = []

        if actionPanel == nil {
            let panel = makeBorderlessPanel(frame: frame, hasShadow: true)
            panel.contentView = hosting
            actionPanel = panel
        } else {
            actionPanel?.contentView = hosting
            // Use display:false — we are potentially inside a layout pass triggered by
            // mouse events; display:true would re-enter the layout cycle and crash.
            actionPanel?.setFrame(frame, display: false)
        }

        actionPanel?.makeKeyAndOrderFront(nil)
        installDismissMonitor()
    }

    // MARK: - Hide

    func hideAll() {
        plusPanel?.orderOut(nil)
        hideActionMenu()
        capturedText = ""
        actionPanelFixedFrame = .zero
    }

    private func hideActionMenu() {
        actionPanel?.orderOut(nil)
        removeDismissMonitor()
    }

    // MARK: - Handle action / expand

    private func handleAction(_ action: QuickAction, prompt: String?, text: String) {
        guard let vm = viewModel, let wc = windowController else { return }
        hideAll()
        DispatchQueue.main.async {
            vm.executeQuickAction(action, selectedText: text, writePrompt: prompt)
            wc.showForQuickAction()
        }
    }

    private func expandToMainWindow(text: String) {
        guard let wc = windowController, let vm = viewModel else { return }
        hideAll()
        DispatchQueue.main.async {
            vm.selectedContextText = text
            vm.isExpanded = true
            wc.showForQuickAction()
        }
    }

    // MARK: - Click-outside dismiss

    private func installDismissMonitor() {
        guard dismissMonitor == nil else { return }
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            let inPlus   = self.plusPanel?.frame.contains(loc) ?? false
            let inAction = self.actionPanelFixedFrame.contains(loc)
            if !inPlus && !inAction { self.hideAll() }
        }
    }

    private func removeDismissMonitor() {
        if let m = dismissMonitor { NSEvent.removeMonitor(m) }
        dismissMonitor = nil
    }

    // MARK: - Cmd+C synthesis via HID

    private func synthesiseCopy() {
        func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { return }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
        let cmd = CGEventFlags.maskCommand
        post(0x37, down: true,  flags: cmd)
        post(0x08, down: true,  flags: cmd)
        post(0x08, down: false, flags: cmd)
        post(0x37, down: false, flags: [])
    }

    // MARK: - Panel factory

    private func makeBorderlessPanel(frame: NSRect, hasShadow: Bool) -> NSPanel {
        let p = OverlayPanel(contentRect: frame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = hasShadow
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return p
    }
}

class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}
