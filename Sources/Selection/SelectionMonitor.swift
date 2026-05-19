import AppKit

struct TextSelectionInfo {
    let text: String
    let screenRect: NSRect
}

/// Detects text selections without Accessibility permission.
///
/// Strategy:
///   1. Global mouseDown/mouseUp monitors track drag gestures (no Accessibility needed for mouse events).
///   2. When a drag is detected, the + button appears near the mouse cursor.
///   3. When the user clicks +, a Cmd+C is synthesised to capture whatever is selected;
///      the clipboard result becomes the "selected text" for the action menu.
///
/// This avoids kAXSelectedTextAttribute (which requires Accessibility) entirely.
class SelectionMonitor {
    var onDragDetected: ((NSPoint) -> Void)?   // mouse position at mouseUp
    var onMouseDown: (() -> Void)?

    private var mouseUpMonitor: Any?
    private var mouseDownMonitor: Any?

    private var dragStartPoint: NSPoint = .zero
    private var dragStartTime: Date = Date()
    private(set) var lastFrontmostApp: NSRunningApplication?

    func start() {
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            DispatchQueue.main.async {
                self?.dragStartPoint = NSEvent.mouseLocation
                self?.dragStartTime  = Date()
                // Remember which app was active when the drag started
                if let front = NSWorkspace.shared.frontmostApplication,
                   front.bundleIdentifier != "com.antigravity.MacSynergy" {
                    self?.lastFrontmostApp = front
                }
                self?.onMouseDown?()
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.evaluateDrag()
            }
        }
    }

    func stop() {
        [mouseUpMonitor, mouseDownMonitor].compactMap { $0 }.forEach { NSEvent.removeMonitor($0) }
        mouseUpMonitor = nil; mouseDownMonitor = nil
    }

    private func evaluateDrag() {
        // Skip events from MacSynergy's own panels
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier == "com.antigravity.MacSynergy" { return }

        let endPoint = NSEvent.mouseLocation
        let dx = endPoint.x - dragStartPoint.x
        let dy = endPoint.y - dragStartPoint.y
        let distance = sqrt(dx * dx + dy * dy)
        let duration = Date().timeIntervalSince(dragStartTime)

        // A drag is any mouse-down→move→up with enough distance and time
        // (distinguishes text-selection drags from simple clicks)
        guard distance > 12, duration > 0.08 else { return }

        onDragDetected?(endPoint)
    }
}
