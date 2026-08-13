import AppKit
import QuartzCore

@MainActor
final class TaskStatusView: NSVisualEffectView {
    private let iconView = NSImageView()
    private let idleLabel = NSTextField(labelWithString: "Codex 空闲")
    private let processingButton = NSButton(title: "", target: nil, action: nil)
    private let unreadButton = NSButton(title: "", target: nil, action: nil)

    var onProcessingSelected: (() -> Void)?
    var onUnreadSelected: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 156).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        idleLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        idleLabel.translatesAutoresizingMaskIntoConstraints = false
        for button in [processingButton, unreadButton] {
            button.isBordered = false
            button.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        processingButton.target = self
        processingButton.action = #selector(processingSelected)
        unreadButton.target = self
        unreadButton.action = #selector(unreadSelected)

        let stack = NSStackView(views: [iconView, idleLabel, processingButton, unreadButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        update(processing: 0, unread: 0)
        updateDynamicColors()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDynamicColors()
    }

    func update(processing: Int, unread: Int) {
        let symbolName: String
        let accessibilityTitle: String
        switch (processing, unread) {
        case (0, 0):
            symbolName = "circle.dotted"
            idleLabel.stringValue = "Codex 空闲"
            accessibilityTitle = "Codex 空闲"
        case (_, 0):
            symbolName = "waveform.circle.fill"
            accessibilityTitle = "处理中 \(processing)"
        case (0, _):
            symbolName = "bell.badge.fill"
            accessibilityTitle = "待读 \(unread)"
        default:
            symbolName = "waveform.circle.fill"
            accessibilityTitle = "处理中 \(processing)，待读 \(unread)"
        }
        processingButton.title = "处理中 \(processing)"
        unreadButton.title = "待读 \(unread)"
        idleLabel.isHidden = processing > 0 || unread > 0
        processingButton.isHidden = processing == 0
        unreadButton.isHidden = unread == 0
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityTitle)
        iconView.image?.isTemplate = true
        processingButton.contentTintColor = .labelColor
        unreadButton.contentTintColor = .systemOrange
        setAccessibilityLabel(accessibilityTitle)
    }

    @objc private func processingSelected() {
        onProcessingSelected?()
    }

    @objc private func unreadSelected() {
        onUnreadSelected?()
    }

    private func updateDynamicColors() {
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        iconView.contentTintColor = .secondaryLabelColor
        idleLabel.textColor = .labelColor
    }
}

@MainActor
final class QuotaRingView: NSVisualEffectView {
    private let trackLayer = CAShapeLayer()
    private let ringLayer = CAShapeLayer()
    private let valueLabel = NSTextField(labelWithString: "—")
    private let titleLabel = NSTextField(labelWithString: "")
    private var remainingFraction: CGFloat = 0
    private var remainingPercent: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 112).isActive = true
        heightAnchor.constraint(equalToConstant: 30).isActive = true

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        valueLabel.alignment = .left
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        titleLabel.font = .systemFont(ofSize: 9, weight: .medium)
        titleLabel.alignment = .left
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 39),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -6),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 6),
        ])

        for shapeLayer in [trackLayer, ringLayer] {
            shapeLayer.fillColor = NSColor.clear.cgColor
            shapeLayer.lineWidth = 3
            shapeLayer.lineCap = .round
            layer?.addSublayer(shapeLayer)
        }
        trackLayer.strokeEnd = 1
        ringLayer.strokeStart = 0
        ringLayer.strokeEnd = 0
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        updateDynamicColors()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDynamicColors()
    }

    override func layout() {
        super.layout()
        let ringRect = CGRect(x: 7, y: 3, width: 24, height: 24)
        let ringPath = CGMutablePath()
        ringPath.addArc(
            center: CGPoint(x: ringRect.midX, y: ringRect.midY),
            radius: ringRect.width / 2,
            startAngle: -.pi / 2,
            endAngle: .pi * 3 / 2,
            clockwise: false
        )
        for shapeLayer in [trackLayer, ringLayer] {
            shapeLayer.frame = bounds
            shapeLayer.path = ringPath
            shapeLayer.setAffineTransform(.identity)
        }
    }

    func update(
        title: String,
        remainingPercent: Int?,
        detail: String? = nil,
        accessibilityText: String? = nil
    ) {
        titleLabel.stringValue = "\(title)额度"
        let clamped = remainingPercent.map { max(0, min(100, $0)) }
        self.remainingPercent = clamped
        let nextFraction = CGFloat(clamped ?? 0) / 100
        valueLabel.stringValue = detail ?? clamped.map { "\($0)% 剩余" } ?? "暂不可用"
        valueLabel.font = .monospacedDigitSystemFont(
            ofSize: detail == nil ? 10 : 8,
            weight: .semibold
        )
        let accessibilityValue = accessibilityText
            ?? clamped.map { "\(title)额度剩余 \($0)%" }
            ?? "\(title)额度不可用"
        setAccessibilityLabel(accessibilityValue)
        setAccessibilityValue(accessibilityValue)

        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = ringLayer.presentation()?.strokeEnd ?? remainingFraction
        animation.toValue = nextFraction
        animation.duration = 0.35
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.strokeEnd = nextFraction
        CATransaction.commit()
        ringLayer.add(animation, forKey: "quota-progress")
        remainingFraction = nextFraction
        updateDynamicColors()
    }

    private func updateDynamicColors() {
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        trackLayer.strokeColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
        valueLabel.textColor = remainingPercent == nil ? .tertiaryLabelColor : .labelColor
        titleLabel.textColor = .secondaryLabelColor
        let ringColor: NSColor
        if let remainingPercent {
            if remainingPercent <= 20 {
                ringColor = .systemRed
            } else if remainingPercent < 50 {
                ringColor = .systemOrange
            } else {
                ringColor = .controlAccentColor
            }
        } else {
            ringColor = .tertiaryLabelColor
        }
        ringLayer.strokeColor = ringColor.cgColor
    }
}
