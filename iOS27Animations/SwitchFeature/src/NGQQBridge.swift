import UIKit
import QuartzCore

// Instantiated only by NGQQRefreshSwitch in com.tencent.mqq. The real UISwitch
// remains visible to hit-testing and accessibility and owns all value/actions.
@objc(NGQQTheseusSwitch)
final class NGQQTheseusSwitch: UIView {
    private let toggle = TheseusSwitch()
    @objc var ownerIsCurrent: (() -> Bool)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        toggle.isUserInteractionEnabled = false
        toggle.isAccessibilityElement = false
        toggle.gestureRecognizers?.forEach { toggle.removeGestureRecognizer($0) }
        toggle.qqCaptureSourceProvider = { [weak self] in self?.captureRow() }
        toggle.qqCaptureBackdropProvider = { [weak self] in self?.captureBackdrop() ?? .systemBackground }
        toggle.qqOwnerIsCurrent = { [weak self] in self?.ownerIsCurrent?() == true }
        addSubview(toggle)
        toggle.frame = bounds
    }

    required init?(coder: NSCoder) { return nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        if toggle.frame != bounds {
            UIView.performWithoutAnimation { self.toggle.frame = self.bounds }
        }
    }

    private func captureRow() -> UIView? {
        guard let native = superview as? UISwitch else { return nil }
        var ancestor = native.superview
        var localRow: UIView?
        while let view = ancestor {
            if view is UITableViewCell || view is UICollectionViewCell { return view }
            if localRow == nil, !(view is UIScrollView),
               view.bounds.width > native.bounds.width + 16,
               view.bounds.height >= native.bounds.height {
                localRow = view
            }
            ancestor = view.superview
        }
        return localRow ?? native.window?.rootViewController?.view
    }

    private func captureBackdrop() -> UIColor {
        let traits = captureRow()?.traitCollection ?? traitCollection
        var ancestor = captureRow()
        while let view = ancestor {
            if let color = view.backgroundColor?.resolvedColor(with: traits), color.cgColor.alpha >= 0.99 {
                return color.withAlphaComponent(1)
            }
            ancestor = view.superview
        }
        return UIColor.systemBackground.resolvedColor(with: traits)
    }

    @objc(setNativeValue:) func setNativeValue(_ value: Bool) {
        toggle.synchronizeNativeValue(value)
    }
    @objc(beginNativeTouch:) func beginNativeTouch(_ point: CGPoint) {
        guard ownerIsCurrent?() == true else { return }
        toggle.qqBeginNativeTouch(at: point)
    }
    @objc(moveNativeTouch:) func moveNativeTouch(_ point: CGPoint) {
        toggle.qqMoveNativeTouch(to: point)
    }
    @objc(endNativeTouch:cancelled:) func endNativeTouch(_ value: Bool, cancelled: Bool) {
        toggle.qqEndNativeTouch(value: value, cancelled: cancelled)
    }
    @objc func cancelNativeVisual() { toggle.qqCancelNativeVisual() }
}
