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
final class SiriPetView: NSView {
    private let orbLayer = CALayer()
    private let baseGradient = CAGradientLayer()
    private let ringLayer = CAShapeLayer()
    private let blobLayers: [CAGradientLayer] = (0..<4).map { _ in CAGradientLayer() }
    private var isActive = false
    private var hasLaidOut = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 44).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true

        orbLayer.masksToBounds = true
        orbLayer.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        layer?.addSublayer(orbLayer)

        baseGradient.colors = [
            NSColor.systemBlue.cgColor,
            NSColor.systemPurple.cgColor,
            NSColor.systemPink.cgColor,
            NSColor.systemCyan.cgColor,
        ]
        baseGradient.startPoint = CGPoint(x: 0, y: 0.5)
        baseGradient.endPoint = CGPoint(x: 1, y: 0.5)
        orbLayer.addSublayer(baseGradient)

        let colors: [NSColor] = [.systemCyan, .systemBlue, .systemPurple, .systemPink]
        for (blob, color) in zip(blobLayers, colors) {
            blob.type = .radial
            blob.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
            blob.locations = [0, 1]
            blob.startPoint = CGPoint(x: 0.5, y: 0.5)
            blob.endPoint = CGPoint(x: 1, y: 1)
            orbLayer.addSublayer(blob)
        }

        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.lineWidth = 1.4
        ringLayer.strokeColor = NSColor.systemCyan.withAlphaComponent(0.55).cgColor
        layer?.addSublayer(ringLayer)
        setAccessibilityLabel("Siri 风格状态光球")
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let orbFrame = CGRect(x: 7, y: 3, width: 30, height: 24)
        orbLayer.frame = orbFrame
        orbLayer.cornerRadius = orbFrame.height / 2
        baseGradient.frame = orbLayer.bounds
        for blob in blobLayers {
            blob.frame = CGRect(x: -4, y: -7, width: 25, height: 25)
        }
        ringLayer.frame = bounds
        ringLayer.path = CGPath(
            roundedRect: orbFrame.insetBy(dx: -1.2, dy: -1.2),
            cornerWidth: orbFrame.height / 2,
            cornerHeight: orbFrame.height / 2,
            transform: nil
        )
        if !hasLaidOut {
            hasLaidOut = true
            applyState(animated: false)
        }
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        guard hasLaidOut else { return }
        applyState(animated: true)
    }

    private func applyState(animated: Bool) {
        orbLayer.removeAllAnimations()
        ringLayer.removeAllAnimations()
        blobLayers.forEach { $0.removeAllAnimations() }

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.3 : 0)
        baseGradient.opacity = isActive ? 0.42 : 0.13
        ringLayer.opacity = isActive ? 1 : 0.55
        blobLayers.forEach { $0.opacity = isActive ? 0.9 : 0.12 }
        orbLayer.shadowColor = NSColor.systemPurple.cgColor
        orbLayer.shadowRadius = isActive ? 7 : 2
        orbLayer.shadowOpacity = isActive ? 0.75 : 0.2
        CATransaction.commit()

        guard isActive else { return }

        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1.0, 1.055, 0.985, 1.0]
        pulse.keyTimes = [0, 0.35, 0.72, 1]
        pulse.duration = 1.35
        pulse.repeatCount = .infinity
        pulse.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        orbLayer.add(pulse, forKey: "siri-pulse")

        let positions: [[CGPoint]] = [
            [CGPoint(x: 7, y: 7), CGPoint(x: 22, y: 9), CGPoint(x: 15, y: 21), CGPoint(x: 7, y: 7)],
            [CGPoint(x: 24, y: 18), CGPoint(x: 10, y: 20), CGPoint(x: 17, y: 5), CGPoint(x: 24, y: 18)],
            [CGPoint(x: 15, y: 4), CGPoint(x: 25, y: 15), CGPoint(x: 6, y: 16), CGPoint(x: 15, y: 4)],
            [CGPoint(x: 5, y: 17), CGPoint(x: 16, y: 5), CGPoint(x: 25, y: 19), CGPoint(x: 5, y: 17)],
        ]
        for (index, blob) in blobLayers.enumerated() {
            let movement = CAKeyframeAnimation(keyPath: "position")
            movement.values = positions[index].map { NSValue(point: $0) }
            movement.keyTimes = [0, 0.34, 0.68, 1]
            movement.duration = 1.7 + Double(index) * 0.17
            movement.repeatCount = .infinity
            movement.timingFunctions = Array(
                repeating: CAMediaTimingFunction(name: .easeInEaseOut),
                count: 3
            )
            blob.add(movement, forKey: "siri-flow-\(index)")
        }

        let ringColors = CAKeyframeAnimation(keyPath: "strokeColor")
        ringColors.values = [
            NSColor.systemCyan.cgColor,
            NSColor.systemBlue.cgColor,
            NSColor.systemPurple.cgColor,
            NSColor.systemPink.cgColor,
            NSColor.systemCyan.cgColor,
        ]
        ringColors.duration = 2.2
        ringColors.repeatCount = .infinity
        ringLayer.add(ringColors, forKey: "siri-ring")
    }
}
