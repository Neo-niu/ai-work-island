import AppKit

enum StatusItemIconRenderer {
    static let canvasSize = NSSize(width: 18, height: 18)

    static func makeImage() -> NSImage {
        let image = NSImage(size: canvasSize, flipped: false) { _ in
            NSColor.black.setFill()

            // A Touch Bar that expands into the same central work island used by
            // the app icon. The three cut-outs stay legible at menu-bar scale.
            let touchBar = NSBezierPath(roundedRect: NSRect(x: 1, y: 7, width: 16, height: 4), xRadius: 2, yRadius: 2)
            touchBar.fill()
            let island = NSBezierPath(roundedRect: NSRect(x: 4.25, y: 5, width: 9.5, height: 8), xRadius: 4, yRadius: 4)
            island.fill()

            NSGraphicsContext.current?.compositingOperation = .clear
            for x in [6.0, 8.5, 11.0] {
                NSBezierPath(ovalIn: NSRect(x: x, y: 8.25, width: 1, height: 1.5)).fill()
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "AI工作岛"
        return image
    }
}
