import Metal
import MetalKit
import UIKit
import QuartzCore
import IOSurface
import CoreVideo

struct CaptureResult {
    let texture: MTLTexture
    let surface: IOSurface
    let poolGeneration: UInt64
    let meanColor: CaptureColor
}

struct CaptureColor: Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat

    var luminance: CGFloat { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    static func grey(_ value: CGFloat) -> CaptureColor {
        CaptureColor(red: value, green: value, blue: value)
    }
}

enum CaptureStatistics {
    static func meanColor(of image: CGImage) -> CaptureColor {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .grey(0.5) }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return CaptureColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255)
    }
}

private final class SurfacePool {
    private let cache = IdleResourceCache<SurfaceDimensions, IOSurface>(
        maxBytes: 4 * 1024 * 1024, maxCount: 12
    )

    struct SurfaceDimensions: Hashable {
        let width: Int
        let height: Int
    }

    var generation: UInt64 { cache.generation }

    func requestSurface(dimensions: SurfaceDimensions) -> IOSurface? {
        cache.take(dimensions) ?? makeSurface(dimensions: dimensions)
    }

    func returnSurface(_ surface: IOSurface, generation: UInt64) {
        let dims = SurfaceDimensions(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
        cache.put(surface, key: dims, bytes: IOSurfaceGetAllocSize(surface), generation: generation)
    }

    func clearCache() { cache.drain() }

    private func makeSurface(dimensions: SurfaceDimensions) -> IOSurface? {
        // Metal wants 16-byte row alignment
        let rowAlignment = 16
        let bytesPerPixel = 4
        let bytesPerRow = ((dimensions.width * bytesPerPixel) + rowAlignment - 1) & ~(rowAlignment - 1)

        let props: [IOSurfacePropertyKey: Any] = [
            .width: dimensions.width,
            .height: dimensions.height,
            .bytesPerElement: bytesPerPixel,
            .bytesPerRow: bytesPerRow,
            .allocSize: bytesPerRow * dimensions.height,
            .pixelFormat: kCVPixelFormatType_32BGRA
        ]
        return IOSurfaceCreate(props as CFDictionary)
    }
}

final class ViewLayerCapture {

    private let device: MTLDevice
    private let surfacePool = SurfacePool()

    init(device: MTLDevice) {
        self.device = device
    }

    deinit {
        invalidate()
    }

    func captureTexture(
        from sourceView: UIView,
        region: CGRect,
        scale: CGFloat = 1.0,
        excludedViews: [UIView] = []
    ) -> CaptureResult? {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let previousVisibility = excludedViews.map { $0.isHidden }
        excludedViews.forEach { $0.isHidden = true }

        // Must follow the exclusion hiding above so excluded subtrees are skipped.
        var compensation: [CaptureCompensation.Entry] = []
        UIView.performWithoutAnimation {
            compensation = CaptureCompensation.begin(in: sourceView, region: region)
        }

        defer {
            UIView.performWithoutAnimation { CaptureCompensation.end(compensation) }
            for (view, wasHidden) in zip(excludedViews, previousVisibility) {
                view.isHidden = wasHidden
            }
        }

        let screenScale = sourceView.window?.screen.scale ?? UIScreen.main.scale
        let renderScale = screenScale * scale

        guard region.width > 0 && region.height > 0 else { return nil }

        let pixelWidth = Int(ceil(region.width * renderScale - 0.001))
        let pixelHeight = Int(ceil(region.height * renderScale - 0.001))

        guard pixelWidth > 0 && pixelHeight > 0 else { return nil }

        let dims = SurfacePool.SurfaceDimensions(width: pixelWidth, height: pixelHeight)
        let generation = surfacePool.generation
        guard let surface = surfacePool.requestSurface(dimensions: dims) else {
            return nil
        }

        // Failed captures drop or recycle only after unlocking; successful ones
        // are returned by the GPU completion callback.
        guard IOSurfaceLock(surface, [], nil) == 0 else { return nil }
        var handedOff = false
        defer {
            IOSurfaceUnlock(surface, [], nil)
            if !handedOff { surfacePool.returnSurface(surface, generation: generation) }
        }

        let bytesPerRow = IOSurfaceGetBytesPerRow(surface)
        let baseAddress = IOSurfaceGetBaseAddress(surface)

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(
            data: baseAddress,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        ctx.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: renderScale, y: -renderScale)
        ctx.translateBy(x: -region.origin.x, y: -region.origin.y)

        sourceView.layer.render(in: ctx)
        CaptureEdges.extend(
            baseAddress,
            width: pixelWidth,
            height: pixelHeight,
            bytesPerRow: bytesPerRow,
            region: region,
            visible: CaptureEdges.visibleBounds(of: sourceView),
            scale: renderScale
        )
        let meanColor = ctx.makeImage().map(CaptureStatistics.meanColor(of:)) ?? .grey(0.5)

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: pixelWidth,
            height: pixelHeight,
            mipmapped: false
        )
        texDesc.usage = [.shaderRead]
        texDesc.storageMode = .shared

        guard let texture = device.makeTexture(
            descriptor: texDesc,
            iosurface: surface,
            plane: 0
        ) else {
            return nil
        }

        handedOff = true
        return CaptureResult(texture: texture, surface: surface, poolGeneration: generation, meanColor: meanColor)
    }

    func recycleSurface(_ surface: IOSurface, generation: UInt64) {
        surfacePool.returnSurface(surface, generation: generation)
    }

    func invalidate() {
        surfacePool.clearCache()
    }
}
