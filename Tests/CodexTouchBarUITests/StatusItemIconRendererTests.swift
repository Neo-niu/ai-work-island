import AppKit
@testable import CodexTouchBar
import Testing

@MainActor
@Test func statusItemIconUsesTemplateRenderingAtMenuBarSize() {
    let image = StatusItemIconRenderer.makeImage()

    #expect(image.size == NSSize(width: 18, height: 18))
    #expect(image.isTemplate)
    #expect(image.accessibilityDescription == "AI 工作岛")
}

@MainActor
@Test func statusItemIconContainsVisibleInkAndThreeTransparentStatusDots() throws {
    let image = StatusItemIconRenderer.makeImage()
    let representation = try #require(
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    )
    let bitmap = NSBitmapImageRep(cgImage: representation)

    #expect(bitmap.alphaAt(pointX: 2, pointY: 9) > 0.8)
    #expect(bitmap.alphaAt(pointX: 6.5, pointY: 9) < 0.2)
    #expect(bitmap.alphaAt(pointX: 9, pointY: 9) < 0.2)
    #expect(bitmap.alphaAt(pointX: 11.5, pointY: 9) < 0.2)
}

private extension NSBitmapImageRep {
    func alphaAt(pointX: CGFloat, pointY: CGFloat) -> CGFloat {
        let x = Int(pointX * CGFloat(pixelsWide) / StatusItemIconRenderer.canvasSize.width)
        let y = Int(pointY * CGFloat(pixelsHigh) / StatusItemIconRenderer.canvasSize.height)
        return colorAt(x: x, y: y)?.alphaComponent ?? 0
    }
}
