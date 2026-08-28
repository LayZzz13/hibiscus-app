import CoreImage
import MetalKit
import SwiftUI

nonisolated final class CameraPreviewRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let device: MTLDevice
    private let context: CIContext
    private let commandQueue: MTLCommandQueue
    private let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    private var latestImage: CIImage?
    private var latestCharacter: CameraCharacter = .alpha
    private var frameVersion: UInt64 = 0
    private var submittedVersion: UInt64 = 0
    private var isRendering = false

    override init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Hibiscus requires a Metal-capable iPhone.")
        }
        self.device = device
        self.context = CIContext(mtlDevice: device, options: [.cacheIntermediates: true])
        self.commandQueue = commandQueue
        super.init()
    }

    @MainActor
    func configure(_ view: MTKView) {
        view.device = device
        view.delegate = self
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0.02, 0.02, 0.02, 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.autoResizeDrawable = true
    }

    func submit(_ image: CIImage, character: CameraCharacter) {
        lock.lock()
        latestImage = image
        latestCharacter = character
        frameVersion &+= 1
        lock.unlock()
    }

    func clear() {
        lock.lock()
        latestImage = nil
        frameVersion &+= 1
        lock.unlock()
    }

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 0,
              view.drawableSize.height > 0 else { return }

        lock.lock()
        guard !isRendering,
              frameVersion != submittedVersion,
              let image = latestImage else {
            lock.unlock()
            return
        }
        let character = latestCharacter
        submittedVersion = frameVersion
        isRendering = true
        lock.unlock()

        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            lock.lock()
            isRendering = false
            lock.unlock()
            return
        }

        let target = CGRect(origin: .zero, size: view.drawableSize)
        // Process only the newest buffer and build the filter graph after scaling
        // to the actual drawable. Preview effects never need full still resolution.
        let displayImage = aspectFill(image, into: target)
        let output = ImageRenderer.cameraPreview(displayImage, character: character)
        context.render(
            output,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: target,
            colorSpace: colorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.isRendering = false
            self.lock.unlock()
        }
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func aspectFill(_ image: CIImage, into target: CGRect) -> CIImage {
        let source = image.extent
        let targetRatio = target.width / target.height
        let sourceRatio = source.width / source.height
        var crop = source
        if sourceRatio > targetRatio {
            crop.size.width = source.height * targetRatio
            crop.origin.x = source.midX - crop.width / 2
        } else {
            crop.size.height = source.width / targetRatio
            crop.origin.y = source.midY - crop.height / 2
        }

        let cropped = image
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        return cropped.transformed(by: CGAffineTransform(
            scaleX: target.width / crop.width,
            y: target.height / crop.height
        ))
    }
}

struct CameraMetalPreview: UIViewRepresentable {
    let renderer: CameraPreviewRenderer
    let isActive: Bool
    let onPreviewLayerReady: (CALayer) -> Void

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero)
        renderer.configure(view)
        onPreviewLayerReady(view.layer)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.isPaused = !isActive
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: ()) {
        uiView.isPaused = true
        uiView.delegate = nil
    }
}
