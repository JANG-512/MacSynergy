import AppKit
import Combine
import SwiftUI
import CoreGraphics

class WindowController: NSObject, ObservableObject {
    var window: FloatingPanel!
    @Published var isContentVisible: Bool = false
    @Published var isWindowAboveCursor: Bool = true
    @Published var isHandoffActive: Bool = false
    private var isSidebarShown: Bool = false
    let viewModel: MacSynergyViewModel

    private var currentWidth: CGFloat {
        return isSidebarShown ? 850 : 680
    }

    private var cancellables = Set<AnyCancellable>()

    init(viewModel: MacSynergyViewModel) {
        self.viewModel = viewModel
        super.init()
        setupWindow()
        setupNotificationObservers()
    }

    private func setupWindow() {
        let contentView = NSHostingView(rootView: MainLauncherView(controller: self, viewModel: viewModel))
        window = FloatingPanel(contentView: contentView)
        
        // Initial positioning
        positionWindowOnScreen()
    }
    
    /// Centered fallback positioning on the primary display.
    private func positionWindowOnScreen() {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowWidth: CGFloat = currentWidth
        let windowHeight: CGFloat = window.frame.height
        
        // Center horizontally; place at 75% height from bottom.
        let x = screenFrame.minX + (screenFrame.width - windowWidth) / 2
        let y = screenFrame.minY + (screenFrame.height * 0.75) - (windowHeight / 2)
        
        window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }
    
    /// Anchors the floating panel right above the mouse cursor — multi-monitor aware.
    private func positionWindowNearCursor() {
        let mouseLocation = NSEvent.mouseLocation
        // Use the screen that actually contains the cursor, not necessarily NSScreen.main
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        guard let screen = screen else { return }
        let screenFrame = screen.visibleFrame
        
        let windowWidth: CGFloat = currentWidth
        let windowHeight: CGFloat = window.frame.height
        
        // Center horizontally relative to mouse cursor
        var x = mouseLocation.x - (windowWidth / 2)
        
        // Position vertically: Try anchoring 20 pixels ABOVE the mouse cursor first
        var y = mouseLocation.y + 20
        isWindowAboveCursor = true
        
        // Screen boundary safety: If panel overflows the top visible boundary, anchor it BELOW the cursor instead
        if y + windowHeight > screenFrame.maxY - 10 {
            y = mouseLocation.y - windowHeight - 20
            isWindowAboveCursor = false
        }
        
        // Keep window fully visible horizontally within visible screen bounds
        if x < screenFrame.minX + 10 {
            x = screenFrame.minX + 10
        } else if x + windowWidth > screenFrame.maxX - 10 {
            x = screenFrame.maxX - windowWidth - 10
        }
        
        // Keep window fully visible vertically within screen bounds
        if y < screenFrame.minY + 10 {
            y = screenFrame.minY + 10
        }
        
        window.setFrame(NSRect(x: x, y: y, width: windowWidth, height: windowHeight), display: true)
    }
    
    /// Programmatically simulates a CMD+C keyboard shortcut event tap to capture selected text
    private func simulateCopyShortcut() {
        // Cmd keycode is 0x37 (55), 'c' keycode is 0x08 (8)
        guard let cmdDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: true),
              let cDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: true),
              let cUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x08, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: false) else { return }
        
        cmdDown.flags = CGEventFlags.maskCommand
        cDown.flags = CGEventFlags.maskCommand
        cUp.flags = CGEventFlags.maskCommand
        
        let loc = CGEventTapLocation.cghidEventTap
        cmdDown.post(tap: loc)
        cDown.post(tap: loc)
        cUp.post(tap: loc)
        cmdUp.post(tap: loc)
    }
    
    /// Programmatically simulates a CMD+V keyboard shortcut event tap to paste text back into active applications
    private func simulatePasteShortcut() {
        // Cmd keycode is 0x37 (55), 'v' keycode is 0x09 (9)
        guard let cmdDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: false) else { return }
        
        cmdDown.flags = CGEventFlags.maskCommand
        vDown.flags = CGEventFlags.maskCommand
        vUp.flags = CGEventFlags.maskCommand
        
        let loc = CGEventTapLocation.cghidEventTap
        cmdDown.post(tap: loc)
        vDown.post(tap: loc)
        vUp.post(tap: loc)
        cmdUp.post(tap: loc)
    }
    
    private func setupNotificationObservers() {
        // Spotlight-style Auto-Dismiss: hide whenever application resigns active focus
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if !self.isHandoffActive {
                    self.hide()
                }
            }
            .store(in: &cancellables)
            
        // Paste back to the previously active app
        NotificationCenter.default.publisher(for: .pasteBackToActiveApp)
            .sink { [weak self] notification in
                guard let self = self, let text = notification.object as? String else { return }
                
                // 1. Copy answer string to standard system pasteboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                
                // 2. Hide MacSynergy panel (which automatically returns keyboard focus to the previous active app)
                self.hide()
                
                // 3. Wait 150ms for window orderOut hide transitions to finish safely, then trigger paste back Cmd+V!
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.simulatePasteShortcut()
                }
            }
            .store(in: &cancellables)
            
        // Keep window visible during Ultimate Ensemble Handoff
        NotificationCenter.default.publisher(for: Notification.Name("ultimateHandoffDidStart"))
            .sink { [weak self] _ in
                self?.isHandoffActive = true
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: Notification.Name("ultimateHandoffDidComplete"))
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Reset handoff guard after a short delay so Chrome activation doesn't auto-dismiss.
                // User manually dismisses with Escape or Shift+Space — no auto-hide.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.isHandoffActive = false
                }
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: Notification.Name("showSidebarDidChange"))
            .sink { [weak self] notification in
                guard let self = self, let show = notification.object as? Bool else { return }
                self.isSidebarShown = show
                
                // Dynamically adjust window width with animation
                let targetWidth: CGFloat = show ? 850 : 680
                let currentFrame = self.window.frame
                let newX = currentFrame.minX - (targetWidth - currentFrame.width) / 2
                
                // Animating window frame
                self.window.setFrame(NSRect(x: newX, y: currentFrame.minY, width: targetWidth, height: currentFrame.height), display: true, animate: true)
            }
            .store(in: &cancellables)
    }
    
    func show() {
        // Clear general pasteboard slightly to verify new text copies cleanly
        let previousPasteboardCount = NSPasteboard.general.changeCount
        
        // 1. Simulate copy command to grab text selections from active applications
        simulateCopyShortcut()
        
        // 2. Allow 120ms delay for system pasteboard buffers to compile selected text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self = self else { return }
            
            // Check if clipboard received selected text
            if NSPasteboard.general.changeCount != previousPasteboardCount,
               let copiedText = NSPasteboard.general.string(forType: .string),
               !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Post selected text directly to the ViewModel
                NotificationCenter.default.post(name: .didReceiveSelectedText, object: copiedText)
            } else {
                // Post empty text to notify the ViewModel that NO text is selected!
                NotificationCenter.default.post(name: .didReceiveSelectedText, object: "")
            }
            
            // Position the balloon bubble right next to their active cursor coordinate
            self.positionWindowNearCursor()
            
            // Bring panel to front and gain keyboard focus
            self.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.76, blendDuration: 0)) {
                self.isContentVisible = true
            }
        }
    }
    
    func hide() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.8, blendDuration: 0)) {
            isContentVisible = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self = self else { return }
            if !self.isContentVisible {
                self.window.orderOut(nil)
            }
        }
    }
    
    func toggle() {
        if window.isVisible && isContentVisible {
            hide()
        } else {
            show()
        }
    }

    /// Shows the panel pre-loaded from a Quick Action (skips Cmd+C clipboard capture).
    func showForQuickAction() {
        positionWindowNearCursor()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.76, blendDuration: 0)) {
            isContentVisible = true
        }
    }

    /// Shows the panel with pre-supplied selected text (skips Cmd+C, posts text directly).
    func showWithText(_ text: String) {
        NotificationCenter.default.post(name: .didReceiveSelectedText, object: text)
        positionWindowNearCursor()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.76, blendDuration: 0)) {
            isContentVisible = true
        }
    }
    
    /// Dynamically resizes the physical NSWindow frame on screen using smooth AppKit animations.
    /// Keep the top edge (maxY) of the window anchored so the search bar stays locked in position while expanding downward.
    func adjustWindowHeight(to newHeight: CGFloat) {
        guard let window = self.window else { return }
        
        let currentFrame = window.frame
        let deltaHeight = newHeight - currentFrame.height
        
        // If the height hasn't changed, skip resizing to avoid rendering stutters
        guard deltaHeight != 0 else { return }
        
        let newFrame = NSRect(
            x: currentFrame.minX,
            // If window is anchored above the cursor, let it expand upwards so the bottom tip stays locked relative to the text.
            // If drawn below the cursor, let it expand downwards as normal.
            y: isWindowAboveCursor ? currentFrame.minY : currentFrame.minY - deltaHeight,
            width: currentFrame.width,
            height: newHeight
        )
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }, completionHandler: nil)
    }
}

extension Notification.Name {
    static let didReceiveSelectedText = Notification.Name("didReceiveSelectedText")
    static let pasteBackToActiveApp = Notification.Name("pasteBackToActiveApp")
    static let ultimateHandoffDidStart = Notification.Name("ultimateHandoffDidStart")
    static let ultimateHandoffDidComplete = Notification.Name("ultimateHandoffDidComplete")
}
