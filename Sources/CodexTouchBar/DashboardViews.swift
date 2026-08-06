import AppKit
import QuartzCore

@MainActor
final class QuotaProgressView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let trackLayer = CALayer()
    private let fillLayer = CAGradientLayer()
    private var progress: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 102).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true

        titleLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        trackLayer.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        trackLayer.cornerRadius = 2.5
        fillLayer.colors = [NSColor.systemCyan.cgColor, NSColor.systemPurple.cgColor]
        fillLayer.startPoint = CGPoint(x: 0, y: 0.5)
        fillLayer.endPoint = CGPoint(x: 1, y: 0.5)
        fillLayer.cornerRadius = 2.5
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let barFrame = CGRect(x: 5, y: 3, width: max(bounds.width - 10, 1), height: 5)
        trackLayer.frame = barFrame
        fillLayer.frame = CGRect(
            x: barFrame.minX,
            y: barFrame.minY,
            width: max(barFrame.width * progress, progress > 0 ? 2 : 0),
            height: barFrame.height
        )
    }

    func update(title: String, usedPercent: Int?, isLow: Bool = false) {
        titleLabel.stringValue = title
        titleLabel.setAccessibilityLabel(title)
        let nextProgress = CGFloat(max(0, min(100, usedPercent ?? 0))) / 100
        progress = nextProgress
        fillLayer.colors = isLow
            ? [NSColor.systemOrange.cgColor, NSColor.systemRed.cgColor]
            : [NSColor.systemCyan.cgColor, NSColor.systemPurple.cgColor]
        let nextWidth = max((bounds.width - 10) * nextProgress, nextProgress > 0 ? 2 : 0)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        fillLayer.frame.size.width = nextWidth
        fillLayer.opacity = usedPercent == nil ? 0.25 : 1
        CATransaction.commit()
    }
}

@MainActor
final class EffortFeedbackView: NSView {
    private var selectedIndex = 1
    private var pulse: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 150).isActive = true
        heightAnchor.constraint(equalToConstant: 7).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    func select(index: Int, animated: Bool) {
        selectedIndex = max(0, min(4, index))
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                animator().alphaValue = 0.45
            } completionHandler: { [weak self] in
                guard let self else { return }
                self.needsDisplay = true
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    self.animator().alphaValue = 1
                }
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let spacing = bounds.width / 5
        for index in 0..<5 {
            let selected = index == selectedIndex
            let diameter: CGFloat = selected ? 5.5 : 3
            let x = spacing * (CGFloat(index) + 0.5) - diameter / 2
            let rect = NSRect(x: x, y: (bounds.height - diameter) / 2, width: diameter, height: diameter)
            (selected ? NSColor.systemCyan : NSColor.white.withAlphaComponent(0.3)).setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }
}

@MainActor
final class MechanicalPetView: NSView {
    private let glowLayer = CAGradientLayer()
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 42).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true

        glowLayer.type = .radial
        glowLayer.colors = [
            NSColor.systemCyan.withAlphaComponent(0.5).cgColor,
            NSColor.systemPurple.withAlphaComponent(0.18).cgColor,
            NSColor.clear.cgColor,
        ]
        glowLayer.locations = [0, 0.55, 1]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        glowLayer.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(glowLayer)

        if let image = Self.loadImage() {
            imageLayer.contents = image
            imageLayer.contentsGravity = .resizeAspect
        }
        layer?.addSublayer(imageLayer)
        setAccessibilityLabel("机械光核宠物")
        startAnimations(active: false)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        glowLayer.frame = bounds.insetBy(dx: 1, dy: -5)
        imageLayer.frame = bounds.insetBy(dx: 5, dy: 0)
    }

    func setActive(_ active: Bool) {
        startAnimations(active: active)
    }

    private func startAnimations(active: Bool) {
        glowLayer.removeAllAnimations()
        imageLayer.removeAllAnimations()

        let glow = CABasicAnimation(keyPath: "opacity")
        glow.fromValue = active ? 0.35 : 0.18
        glow.toValue = active ? 0.95 : 0.5
        glow.duration = active ? 0.65 : 1.8
        glow.autoreverses = true
        glow.repeatCount = .infinity
        glowLayer.add(glow, forKey: "glow")

        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        bob.fromValue = -0.7
        bob.toValue = 0.9
        bob.duration = active ? 0.55 : 1.45
        bob.autoreverses = true
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bob.repeatCount = .infinity
        imageLayer.add(bob, forKey: "bob")
    }

    private static func loadImage() -> NSImage? {
        let installed = Bundle.main.resourceURL?.appendingPathComponent("mechanical-touchbar-pet-96.png")
        if let installed, let image = NSImage(contentsOf: installed) {
            return image
        }
        return NSImage(contentsOfFile: "Resources/mechanical-touchbar-pet-96.png")
    }
}
