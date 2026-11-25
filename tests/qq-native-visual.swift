import Foundation
import CoreGraphics
final class UIView {}
// The following four methods are extracted unchanged from the production
// component. This harness verifies control flow, not UIKit rendering.
final class Fixture {
    var qqCaptureSourceProvider: (() -> UIView?)?
    var qqOwnerIsCurrent: (() -> Bool)?
    var isPressing = false
    var latchedDuringPress = false
    var _isOn = false
    var visuallyOn = false
    var begins = 0, moves = 0, releases = 0, resets = 0
    var eventCount = 0
    func pressBegan(at point: CGPoint) { begins += 1; isPressing = true }
    func pressMoved(to point: CGPoint) { moves += 1; visuallyOn = point.x > 20 }
    func synchronizeNativeValue(_ value: Bool, force: Bool = false) {
        guard force || _isOn != value else { return }
        resets += 1; _isOn = value; visuallyOn = value; isPressing = false
    }
    func animateRelease(to value: Bool, cancelled: Bool) { releases += 1 }
/* PRODUCTION_QQ_METHODS */
}
let four = (0..<4).map { _ in Fixture() }
var valid = true
for control in four {
    control.qqCaptureSourceProvider = { UIView() }
    control.qqOwnerIsCurrent = { valid }
}
let target = four[3]
for index in 0..<100 {
    let old = target._isOn
    target.qqBeginNativeTouch(at: .zero)
    target.qqMoveNativeTouch(to: CGPoint(x: 40, y: 14))
    precondition(target._isOn == old, "observing touch must not change native logical value")
    let authoritativeNativeValue = index % 2 == 0
    target.qqEndNativeTouch(value: authoritativeNativeValue, cancelled: false)
    precondition(target._isOn == authoritativeNativeValue && !target.isPressing)
    precondition(target.eventCount == 0 && target.releases == index + 1)
    for other in four.prefix(3) {
        precondition(other.begins == 0 && other.releases == 0 && other.eventCount == 0 && !other._isOn)
    }
}
// Rejection/cancellation uses native value without applying another inversion.
target.qqBeginNativeTouch(at: .zero)
target.qqEndNativeTouch(value: false, cancelled: true)
precondition(!target._isOn && target.eventCount == 0)
let releases = target.releases
// Row identity/hiding invalidates only this visual, with no late release.
target.qqBeginNativeTouch(at: .zero); valid = false
target.qqEndNativeTouch(value: true, cancelled: false)
precondition(!target.isPressing && target.releases == releases && !target._isOn)
valid = true
// Default/Clock instances never opt in. QQ entry points are strict no-ops.
let unchanged = Fixture()
unchanged.qqOwnerIsCurrent = { true }
unchanged.qqBeginNativeTouch(at: .zero)
unchanged.qqMoveNativeTouch(to: CGPoint(x: 40, y: 14))
unchanged.qqEndNativeTouch(value: true, cancelled: false)
unchanged.qqCancelNativeVisual()
precondition(!unchanged._isOn && unchanged.begins == 0 && unchanged.moves == 0 && unchanged.releases == 0 && unchanged.resets == 0)
print("PASS exact QQ visual methods: 100 native-value releases, four-control isolation, rejection/cancellation, invalid owner and default/Clock no-op (Swift stand-in)")
