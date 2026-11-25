import Metal
import Foundation

// A bounded cache of idle resources only. GPU-owned resources are not counted
// or reclaimed here until their existing completion callback returns them.
final class IdleResourceCache<Key: Hashable, Resource> {
    private struct Entry {
        let resource: Resource
        let bytes: Int
    }
    private var entries: [Key: [Entry]] = [:]
    private var bytes = 0
    private var count = 0
    private var epoch: UInt64 = 0
    private let lock = NSLock()
    private let maxBytes: Int
    private let maxCount: Int
    private let maxPerKey: Int

    init(maxBytes: Int, maxCount: Int, maxPerKey: Int = 5) {
        self.maxBytes = maxBytes
        self.maxCount = maxCount
        self.maxPerKey = maxPerKey
    }

    var generation: UInt64 {
        lock.withLock { epoch }
    }

    func take(_ key: Key) -> Resource? {
        lock.withLock {
            guard var bucket = entries[key], let entry = bucket.popLast() else { return nil }
            if bucket.isEmpty { entries.removeValue(forKey: key) }
            else { entries[key] = bucket }
            bytes -= entry.bytes
            count -= 1
            return entry.resource
        }
    }

    func put(_ resource: Resource, key: Key, bytes cost: Int, generation: UInt64? = nil) {
        lock.withLock {
            guard generation == nil || generation == epoch,
                  cost > 0, cost <= maxBytes - bytes,
                  count < maxCount, (entries[key]?.count ?? 0) < maxPerKey else { return }
            entries[key, default: []].append(Entry(resource: resource, bytes: cost))
            bytes += cost
            count += 1
        }
    }

    func drain() {
        lock.withLock {
            epoch &+= 1
            entries.removeAll()
            bytes = 0
            count = 0
        }
    }
}

final class TexturePool {
    private let device: MTLDevice
    private let cache = IdleResourceCache<TextureDimensions, MTLTexture>(
        maxBytes: 8 * 1024 * 1024, maxCount: 24
    )

    struct TextureDimensions: Hashable {
        let width: Int
        let height: Int
        let format: MTLPixelFormat
        let mipmapped: Bool
    }

    init(device: MTLDevice) { self.device = device }
    var generation: UInt64 { cache.generation }

    func checkout(width: Int, height: Int, format: MTLPixelFormat = .bgra8Unorm, mipmapped: Bool = false) -> MTLTexture? {
        let dims = TextureDimensions(width: width, height: height, format: format, mipmapped: mipmapped)
        if let texture = cache.take(dims) { return texture }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: dims.format, width: dims.width, height: dims.height, mipmapped: dims.mipmapped
        )
        descriptor.storageMode = .private
        descriptor.usage = dims.mipmapped ? [.renderTarget, .shaderRead, .pixelFormatView] : [.renderTarget, .shaderRead]
        return device.makeTexture(descriptor: descriptor)
    }

    func checkin(_ texture: MTLTexture, generation: UInt64? = nil) {
        let dims = TextureDimensions(width: texture.width, height: texture.height,
                                     format: texture.pixelFormat, mipmapped: texture.mipmapLevelCount > 1)
        cache.put(texture, key: dims, bytes: texture.allocatedSize, generation: generation)
    }

    func drain() { cache.drain() }
}
