#!/usr/bin/env python3
"""Host-side model and source contracts, not UIKit execution."""
from pathlib import Path
from itertools import permutations
root=Path(__file__).resolve().parents[1]
native=(root/'src/NGSwitch.m').read_text()
swift=(root/'Vendor/Theseus/Sources/Theseus/Components/TheseusSwitch.swift').read_text()
tweak=(root/'src/Tweak.m').read_text()
replay=swift.split('func replayClockTransition(to value: Bool) {',1)[1].split('private func animateRelease',1)[0]
assert 'onValueChanged' not in replay and 'sendActions' not in replay and 'hapticFeedback' not in replay
assert 'animateRelease(to: value, cancelled: false)' in replay # no glass fallback
assert 'beginPress()' not in replay
assert 'pendingFlight = true' in replay and 'showGlass()' in replay
assert replay.index('pendingFlight = true') < replay.index('showGlass()')
assert 'if clockReplayInFlight { setThumbX(glassMotion.position) }' in swift
assert 'clockReplayInFlight = false' in swift.split('private func teardownGlass()',1)[1].split('public override func didMoveToWindow',1)[0]
assert 'synchronizeNativeValue(value, force: true)' in replay
assert 'NGClockResetAlarmCell(cell);\n    NGClockScheduleReplay(table);' in tweak
assert 'NGClockResetAlarmCell(cell);\n    if (gAlarmPrepareForReuse)' in tweak
assert 'source.isOn != ticket.value' in native
assert 'objc_getAssociatedObject(current, &kNGClockReplayKey) != ticket' in native
assert 'current.indexPathsForVisibleRows containsObject:ticket.path' in native
assert 'ticket.lastResetVersion == binding.clockResetVersion' in native

def select(rows, target, value, old_binding, old_reset, *, latest=True, visible=True, expired=False, touching=False, editing=False, structure=True):
    if not latest or not visible or expired or touching or editing or not structure: return None
    binding, state, reset = rows[target]
    if state != value or (binding,reset)==(old_binding,old_reset): return None
    return target

for order in permutations(range(6)):
    rows=[(binding, i==0, 1) for i,binding in enumerate(order)]
    assert select(rows,0,True,0,0)==0
    for condition in ('latest','visible','expired','touching','editing','structure'):
        assert select(rows,0,True,0,0,**{condition: condition in ('expired','touching','editing')}) is None
    assert select(rows,0,False,0,0) is None
assert select([(0,True,0)],0,True,0,0) is None
# Rapid toggles supersede previous tickets, whether the cell was moved or not.
for i in range(50):
    value=bool(i%2)
    rows=[((i+3)%6,value,i+1)]+[(j,False,i+1) for j in range(1,6)]
    assert select(rows,0,not value,0,i,latest=False) is None
    assert select(rows,0,value,0,i)==0
print('PASS: source contracts, 720 row permutations, 50 rapid-toggle model cases (not device tests)')
