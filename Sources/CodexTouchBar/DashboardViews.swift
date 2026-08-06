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
    private let bloomLayer = CAGradientLayer()
    private let orbLayer = CALayer()
    private let baseGradient = CAGradientLayer()
    private let glassLayer = CAGradientLayer()
    private let coreLayer = CAShapeLayer()
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

        bloomLayer.type = .radial
        bloomLayer.colors = [
            NSColor.systemCyan.withAlphaComponent(0.55).cgColor,
            NSColor.systemPurple.withAlphaComponent(0.24).cgColor,
            NSColor.clear.cgColor,
        ]
        bloomLayer.locations = [0, 0.48, 1]
        bloomLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        bloomLayer.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(bloomLayer)

        orbLayer.masksToBounds = true
        orbLayer.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        layer?.addSublayer(orbLayer)

        baseGradient.type = .conic
        baseGradient.colors = [
            NSColor.systemCyan.cgColor,
            NSColor.systemBlue.cgColor,
            NSColor.systemPurple.cgColor,
            NSColor.systemPink.cgColor,
            NSColor.systemCyan.cgColor,
        ]
        baseGradient.locations = [0, 0.22, 0.5, 0.76, 1]
        baseGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
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

        coreLayer.fillColor = NSColor.black.withAlphaComponent(0.24).cgColor
        orbLayer.addSublayer(coreLayer)

        glassLayer.colors = [
            NSColor.white.withAlphaComponent(0.34).cgColor,
            NSColor.white.withAlphaComponent(0.04).cgColor,
            NSColor.clear.cgColor,
        ]
        glassLayer.locations = [0, 0.34, 0.7]
        glassLayer.startPoint = CGPoint(x: 0.5, y: 0)
        glassLayer.endPoint = CGPoint(x: 0.5, y: 1)
        orbLayer.addSublayer(glassLayer)

        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.lineWidth = 1.4
        ringLayer.strokeColor = NSColor.systemCyan.withAlphaComponent(0.55).cgColor
        layer?.addSublayer(ringLayer)
        setAccessibilityLabel("Siri 风格状态光球")
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let orbFrame = CGRect(x: 9, y: 2, width: 26, height: 26)
        bloomLayer.frame = CGRect(x: 1, y: -6, width: 42, height: 42)
        orbLayer.frame = orbFrame
        orbLayer.cornerRadius = orbFrame.height / 2
        baseGradient.frame = orbLayer.bounds
        glassLayer.frame = orbLayer.bounds
        coreLayer.frame = orbLayer.bounds
        coreLayer.path = CGPath(
            ellipseIn: CGRect(x: 7, y: 7, width: 12, height: 12),
            transform: nil
        )
        let idlePositions = [
            CGPoint(x: 7, y: 8),
            CGPoint(x: 19, y: 18),
            CGPoint(x: 17, y: 6),
            CGPoint(x: 8, y: 19),
        ]
        for (index, blob) in blobLayers.enumerated() {
            let size: CGFloat = index.isMultiple(of: 2) ? 24 : 21
            blob.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            blob.position = idlePositions[index]
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
        bloomLayer.removeAllAnimations()
        baseGradient.removeAllAnimations()
        ringLayer.removeAllAnimations()
        blobLayers.forEach { $0.removeAllAnimations() }

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.3 : 0)
        baseGradient.opacity = isActive ? 0.58 : 0.17
        glassLayer.opacity = isActive ? 0.88 : 0.5
        coreLayer.opacity = isActive ? 0.6 : 0.84
        ringLayer.opacity = isActive ? 1 : 0.48
        ringLayer.lineWidth = isActive ? 1.5 : 1.05
        bloomLayer.opacity = isActive ? 0.72 : 0.18
        blobLayers.forEach { $0.opacity = isActive ? 0.88 : 0.1 }
        CATransaction.commit()

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        let gradientRotation = CABasicAnimation(keyPath: "transform.rotation.z")
        gradientRotation.fromValue = 0
        gradientRotation.toValue = Double.pi * 2
        gradientRotation.duration = isActive ? 3.2 : 12
        gradientRotation.repeatCount = .infinity
        gradientRotation.timingFunction = CAMediaTimingFunction(name: .linear)
        baseGradient.add(gradientRotation, forKey: "color-drift")

        if !isActive {
            let idleGlow = CABasicAnimation(keyPath: "opacity")
            idleGlow.fromValue = 0.13
            idleGlow.toValue = 0.23
            idleGlow.duration = 4.8
            idleGlow.autoreverses = true
            idleGlow.repeatCount = .infinity
            idleGlow.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bloomLayer.add(idleGlow, forKey: "idle-glow")
            return
        }

        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = [1.0, 1.045, 0.992, 1.025, 1.0]
        pulse.keyTimes = [0, 0.24, 0.52, 0.76, 1]
        pulse.duration = 1.6
        pulse.repeatCount = .infinity
        pulse.timingFunctions = Array(
            repeating: CAMediaTimingFunction(name: .easeInEaseOut),
            count: 4
        )
        orbLayer.add(pulse, forKey: "siri-pulse")

        let bloom = CAAnimationGroup()
        let bloomOpacity = CABasicAnimation(keyPath: "opacity")
        bloomOpacity.fromValue = 0.38
        bloomOpacity.toValue = 0.9
        let bloomScale = CABasicAnimation(keyPath: "transform.scale")
        bloomScale.fromValue = 0.88
        bloomScale.toValue = 1.08
        bloom.animations = [bloomOpacity, bloomScale]
        bloom.duration = 1.25
        bloom.autoreverses = true
        bloom.repeatCount = .infinity
        bloom.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bloomLayer.add(bloom, forKey: "active-bloom")

        let positions: [[CGPoint]] = [
            [CGPoint(x: 5, y: 6), CGPoint(x: 21, y: 7), CGPoint(x: 19, y: 21), CGPoint(x: 7, y: 19), CGPoint(x: 5, y: 6)],
            [CGPoint(x: 22, y: 18), CGPoint(x: 12, y: 23), CGPoint(x: 5, y: 11), CGPoint(x: 17, y: 4), CGPoint(x: 22, y: 18)],
            [CGPoint(x: 13, y: 3), CGPoint(x: 23, y: 13), CGPoint(x: 13, y: 23), CGPoint(x: 3, y: 13), CGPoint(x: 13, y: 3)],
            [CGPoint(x: 4, y: 18), CGPoint(x: 8, y: 5), CGPoint(x: 22, y: 8), CGPoint(x: 20, y: 21), CGPoint(x: 4, y: 18)],
        ]
        for (index, blob) in blobLayers.enumerated() {
            let movement = CAKeyframeAnimation(keyPath: "position")
            movement.values = positions[index].map { NSValue(point: $0) }
            movement.keyTimes = [0, 0.24, 0.5, 0.76, 1]
            movement.duration = 2.05 + Double(index) * 0.19
            movement.repeatCount = .infinity
            movement.timingFunctions = Array(
                repeating: CAMediaTimingFunction(name: .easeInEaseOut),
                count: 4
            )
            movement.beginTime = CACurrentMediaTime() + Double(index) * 0.11
            blob.add(movement, forKey: "siri-flow-\(index)")

            let shimmer = CABasicAnimation(keyPath: "opacity")
            shimmer.fromValue = 0.5 + Double(index) * 0.05
            shimmer.toValue = 1
            shimmer.duration = 0.85 + Double(index) * 0.12
            shimmer.autoreverses = true
            shimmer.repeatCount = .infinity
            blob.add(shimmer, forKey: "siri-shimmer-\(index)")
        }

        let ringColors = CAKeyframeAnimation(keyPath: "strokeColor")
        ringColors.values = [
            NSColor.systemCyan.cgColor,
            NSColor.systemBlue.cgColor,
            NSColor.systemPurple.cgColor,
            NSColor.systemPink.cgColor,
            NSColor.systemCyan.cgColor,
        ]
        ringColors.duration = 2.6
        ringColors.repeatCount = .infinity
        ringLayer.add(ringColors, forKey: "siri-ring")

        let ringBreath = CABasicAnimation(keyPath: "lineWidth")
        ringBreath.fromValue = 1.1
        ringBreath.toValue = 1.85
        ringBreath.duration = 1.3
        ringBreath.autoreverses = true
        ringBreath.repeatCount = .infinity
        ringBreath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ringLayer.add(ringBreath, forKey: "ring-breath")
    }
}
