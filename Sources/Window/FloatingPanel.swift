import AppKit
import SwiftUI

class FloatingPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        // Floating layout & space behavior settings
        self.isMovableByWindowBackground = true
        self.level = .floating // Floats above all standard app windows (Safari, KakaoTalk, etc.)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Hiding window system borders to allow premium glassmorphism bounds
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        
        // Critical Cocoa properties to prevent Window Server from drawing black rectangular border outlines:
        self.isOpaque = false
        self.backgroundColor = .clear // Transparent background enables rounded visual effect corners
        self.hasShadow = false // Rely entirely on premium rounded SwiftUI card shadow!
        
        self.contentView = contentView
    }
    
    // Core Overrides: Borderless style masks default to false for key status. 
    // Overriding these to true permits this custom panel to gain active keyboard focus instantly.
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}
