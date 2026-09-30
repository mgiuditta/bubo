#if DEBUG
import CoreGraphics
import Foundation
import Metal

/// Draws still, monochrome pictures of the Orb, one per Variante, for the Galleria del Catalogo.
final class OrbSnapshotter {
    /// Creates a snapshotter on the system's Metal device.
    ///
    /// - Throws: An error if Metal is unavailable or the Blob's pipeline cannot be built.
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { throw OrbRendererError.metalUnavailable }
        self.device = device
        self.queue = queue
        pipelines = try OrbPipelines(device: device, library: library)
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipelines: OrbPipelines
    private var cache: [Key: CGImage] = [:]

    /// A still of `variante` in Riposo, halo included, `pixelSize` pixels square on a transparent background.
    ///
    /// - Returns: The picture, or `nil` if its Forma fails to build; a Forma the renderer lacks is drawn as the Blob.
    func snapshot(of variante: Variante, pixelSize: Int) async -> CGImage? {
        let key = Key(nome: variante.nome, pixelSize: pixelSize)
        if let image = cache[key] { return image }
        let forma = Forma(rawValue: variante.forma) ?? .blob
        guard let pipeline = await pipelines.loadedPipeline(for: forma),
              let image = render(forma, with: pipeline, pixelSize: pixelSize)
        else { return nil }
        cache[key] = image
        return image
    }

    private func render(_ forma: Forma, with pipeline: MTLRenderPipelineState, pixelSize: Int) -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: pixelSize,
                                                                  height: pixelSize, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        let pass = MTLRenderPassDescriptor()
        guard let texture = device.makeTexture(descriptor: descriptor),
              let commands = queue.makeCommandBuffer()
        else { return nil }
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        var uniforms = OrbUniforms()
        uniforms.applyMonochromeTinta()
        uniforms.resolution = SIMD2(repeating: Float(pixelSize))
        uniforms.morph = forma == .blob ? 0 : 1
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OrbUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.commit()
        // A few hundred pixels of one still: waiting is shorter than a frame.
        commands.waitUntilCompleted()

        let bytesPerRow = pixelSize * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * pixelSize)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, pixelSize, pixelSize), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: pixelSize, height: pixelSize, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// One cached picture: a Variante at one size.
    private struct Key: Hashable {
        var nome: String
        var pixelSize: Int
    }
}
#endif
