#!/usr/bin/env python3
"""Run the production Swift cache on the host with fake GPU resources.
No UIKit/Metal runtime or device profiling is implied.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
render = root / 'Vendor/Theseus/Sources/Theseus/Rendering'
cache = (render / 'TheseusTextureCache.swift').read_text()
renderer = (render / 'TheseusRenderer.swift').read_text()
capture = (render / 'ViewLayerCapture.swift').read_text()
assert 'maxBytes: 8 * 1024 * 1024, maxCount: 24' in cache
assert 'maxBytes: 4 * 1024 * 1024, maxCount: 12' in capture
assert 'idleCacheGrace: TimeInterval = 3' in renderer
assert 'self.idleCleanupGeneration == generation' in renderer
assert 'guard let self = self, !self.isRendering' in renderer
assert 'func startRendering() {\n        cancelIdleCleanup()' in renderer
assert 'UIApplication.didEnterBackgroundNotification' in renderer
assert 'UIApplication.didReceiveMemoryWarningNotification' in renderer
assert renderer.count('generation: poolGeneration') >= 3
assert 'if !submitted, let captured = capturedSurface' in renderer
assert 'max(_lastCompletedFrame, newValue)' in renderer
assert 'maxFramesInFlight: UInt64 = 3' in renderer
for operation in ('texturePool.drain()', 'viewLayerCapture?.invalidate()',
                  'backgroundCaptureDraw?.invalidate()', 'itemLayerTextures.removeAll()',
                  'blurKernelCalculator.invalidateCache()', 'frostCoarseKernel.invalidateCache()',
                  'frostFillKernel.invalidateCache()'):
    assert operation in renderer.split('private func purgeCachedResources()',1)[1].split('private func waitForGPUCompletion()',1)[0]

# Extract the actual Foundation-only production implementation; no model of the cache.
source = 'import Foundation\nfinal class IdleResourceCache' + cache.split('final class IdleResourceCache',1)[1].split('final class TexturePool',1)[0]
source += r'''
final class Token { let id: Int; init(_ id: Int) { self.id = id } }
let pool = IdleResourceCache<Int, Token>(maxBytes: 100, maxCount: 3, maxPerKey: 2)
let firstEpoch = pool.generation
pool.put(Token(1), key: 1, bytes: 30, generation: firstEpoch)
pool.put(Token(2), key: 1, bytes: 30, generation: firstEpoch)
pool.put(Token(3), key: 1, bytes: 10, generation: firstEpoch) // per-key cap
pool.put(Token(4), key: 2, bytes: 41, generation: firstEpoch) // total bytes
pool.put(Token(5), key: 2, bytes: 40, generation: firstEpoch)
pool.put(Token(6), key: 3, bytes: 1) // count/bytes full
assert(pool.take(1)?.id == 2)
assert(pool.take(1)?.id == 1)
assert(pool.take(1) == nil)
assert(pool.take(2)?.id == 5)
assert(pool.take(3) == nil)
// Returned resource costs must be subtracted accurately.
pool.put(Token(7), key: 3, bytes: 100)
assert(pool.take(3)?.id == 7)
let countPool = IdleResourceCache<Int, Token>(maxBytes: 10000, maxCount: 2)
for i in 0..<10 { countPool.put(Token(i), key: i, bytes: 1) }
assert((0..<10).compactMap { countPool.take($0) }.count == 2)
// An idle resource is really released on drain, not merely marked unavailable.
weak var weakToken: Token?
do {
    let token = Token(8)
    weakToken = token
    pool.put(token, key: 4, bytes: 50, generation: firstEpoch)
}
assert(weakToken != nil)
pool.drain()
assert(weakToken == nil)
assert(pool.generation != firstEpoch)
pool.put(Token(9), key: 4, bytes: 1, generation: firstEpoch)
assert(pool.take(4) == nil)
pool.put(Token(10), key: 4, bytes: 1, generation: pool.generation)
assert(pool.take(4)?.id == 10)
// Concurrent completions racing with a purge cannot repopulate it.
for _ in 0..<100 {
    let epoch = pool.generation
    DispatchQueue.concurrentPerform(iterations: 32) { i in
        if i == 0 { pool.drain() }
        else { pool.put(Token(i), key: i, bytes: 1, generation: epoch) }
    }
    for i in 0..<32 { assert(pool.take(i) == nil) }
}
// Concurrent puts across many dimensions remain bounded.
let stress = IdleResourceCache<Int, Token>(maxBytes: 80, maxCount: 16)
DispatchQueue.concurrentPerform(iterations: 1000) { i in
    stress.put(Token(i), key: i, bytes: 10, generation: stress.generation)
}
assert((0..<1000).compactMap { stress.take($0) }.count == 8)
print("PASS: production Swift cache, byte/count/per-key limits, release, stale returns, 100 purge races and 1000 concurrent puts")
'''
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / 'main.swift'
    path.write_text(source)
    subprocess.run(['swift', str(path)], check=True)
print('PASS: renderer lifecycle source contracts (not UIKit/Metal runtime tests)')
