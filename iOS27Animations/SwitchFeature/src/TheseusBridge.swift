import UIKit
import QuartzCore

// The overlay itself never has an intentional animation. In Clock, prevent
// implicit actions inherited from a host list transaction at this layer only.
// Knob and glass layers retain their own explicit animations.
private final class NGClockOverlayLayer: CALayer {
    override func action(forKey event: String) -> CAAction? {
        if Bundle.main.bundleIdentifier == "com.apple.mobiletimer" {
            switch event {
            case "position", "bounds", "anchorPoint", "transform", "opacity", "hidden", "sublayerTransform":
                return NSNull()
            default: break
            }
        }
        return super.action(forKey: event)
    }
}

// No geometry, material, animation, colour or physics override is applied to
// this instance. Only the existing UISwitch's value and enabled state are bound.
@objc(NGTheseusSwitch)
final class NGTheseusSwitch: UIView {
    override class var layerClass: AnyClass { NGClockOverlayLayer.self }
    private let toggle = TheseusSwitch()
    @objc var onChanged: ((Bool) -> Void)?
    @objc var on: Bool {
        get { toggle.isOn }
        set { toggle.isOn = newValue }
    }
    @objc(isOn) func isOn() -> Bool { toggle.isOn }

    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: 63, height: 28)))
        backgroundColor = .clear
        clipsToBounds = false
        isOpaque = false
        toggle.isolatesClockCapture = Bundle.main.bundleIdentifier == "com.apple.mobiletimer"
        addSubview(toggle)
        toggle.frame = bounds
        toggle.onValueChanged = { [weak self] value in self?.onChanged?(value) }
    }
    required init?(coder: NSCoder) { return nil }
    override var intrinsicContentSize: CGSize { toggle.intrinsicContentSize }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard toggle.frame != bounds else { return }
        UIView.performWithoutAnimation { toggle.frame = bounds }
    }
    @objc(setOn:animated:) func setOn(_ value: Bool, animated: Bool) {
        if animated { toggle.setOn(value, animated: true) }
        else { toggle.synchronizeNativeValue(value) }
    }
    @objc(resetForClockReuse:) func resetForClockReuse(_ value: Bool) {
        toggle.synchronizeNativeValue(value, force: true)
    }
    @objc(replayClockTransition:) func replayClockTransition(_ value: Bool) {
        toggle.replayClockTransition(to: value)
    }
    @objc func clockTouchActive() -> Bool { toggle.clockTouchActive }
    @objc(setControlEnabled:) func setControlEnabled(_ enabled: Bool) {
        if toggle.isEnabled != enabled { toggle.isEnabled = enabled }
    }
    override var accessibilityLabel: String? {
        get { toggle.accessibilityLabel }
        set { toggle.accessibilityLabel = newValue }
    }
    override func accessibilityActivate() -> Bool { toggle.accessibilityActivate() }
}
