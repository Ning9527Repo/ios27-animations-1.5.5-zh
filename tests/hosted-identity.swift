import Foundation
/* PRODUCTION_IDENTITY */
final class Haptic {
    enum Strength { case light }
    var count = 0
    func impact(_ strength: Strength) { count += 1 }
}
final class Fixture {
    var confinesHostedGlass = true
    var hostedInteractionIsValid: (() -> Bool)?
    var hostedIdentity: (() -> HostedSwitchIdentity?)?
    private var pressHostIdentity: HostedSwitchIdentity?
/* PRODUCTION_GATE */
    var isPressing = false
    var _isOn = false
    var visuallyOn = false
    var latchedDuringPress = false
    var releaseGeneration = 0
    let hapticFeedback = Haptic()
    var onValueChanged: ((Bool) -> Void)?
    enum Event { case valueChanged }
    var events = 0, releases = 0, resets = 0
    func sendActions(for event: Event) { events += 1 }
    func traceClockInteraction(_ event: String) {}
    func synchronizeNativeValue(_ on: Bool, force: Bool) {
        guard force || on != _isOn else { return }
        releaseGeneration += 1; _isOn = on; visuallyOn = on; isPressing = false; resets += 1
    }
    static func committedValue(isOn: Bool, visuallyOn: Bool, latched: Bool) -> Bool {
        latched ? visuallyOn : !isOn
    }
    func animateRelease(to value: Bool, cancelled: Bool) { releases += 1 }
    func begin() { pressHostIdentity = hostedIdentity?(); isPressing = true }
    func end(cancelled: Bool = false) { finishPress(cancelled: cancelled) }
/* PRODUCTION_FINISH */
}
let source = NSObject(), parent = NSObject(), row = NSObject(), list = NSObject()
let identity = HostedSwitchIdentity(source: ObjectIdentifier(source), parent: ObjectIdentifier(parent),
    row: ObjectIdentifier(row), list: ObjectIdentifier(list), path: IndexPath(index: 3))
var current = identity
var valid = true
let controls = (0..<4).map { _ in Fixture() }
for control in controls { control.hostedIdentity = { current }; control.hostedInteractionIsValid = { valid } }
let target = controls[3]
for _ in 0..<100 { target.begin(); target.end() }
precondition(target.events == 100 && target.releases == 100 && !target._isOn)
for other in controls.prefix(3) { precondition(other.events == 0 && other.releases == 0 && !other._isOn) }
// Same native object/cell, but now another row: old interaction cannot commit.
target.begin(); current = HostedSwitchIdentity(source: identity.source, parent: identity.parent,
    row: identity.row, list: identity.list, path: IndexPath(index: 1)); target.end()
precondition(target.events == 100 && target.releases == 100 && target.resets == 1)
current = identity
// The host changes row during valueChanged: deliver once, cancel old release.
target.onValueChanged = { _ in current = HostedSwitchIdentity(source: identity.source,
    parent: identity.parent, row: identity.row, list: identity.list, path: IndexPath(index: 1)) }
target.begin(); target.end()
precondition(target.events == 101 && target.releases == 100 && target.resets == 2)
current = identity
// Synchronous host rejection must not restart stale animation after correction.
target.onValueChanged = { _ in target.synchronizeNativeValue(false, force: true) }
target.begin(); target.end()
precondition(target.events == 102 && target.releases == 100 && !target._isOn)
// Hidden/disconnected owner invalidates old touch before sending a second event.
target.onValueChanged = nil; target.begin(); valid = false; target.end()
precondition(target.events == 102 && target.releases == 100)
valid = true
// Clock retains its existing branch; it does not consult hosted identities.
let clock = Fixture(); clock.confinesHostedGlass = false; clock.begin(); clock.end()
precondition(clock.events == 1 && clock.releases == 1)
print("PASS exact production finishPress + identity gate: 100 isolated toggles, row reuse, host rejection, hidden owner, Clock branch (Swift stand-in)")
