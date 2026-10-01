import MetalKit
import QuartzCore

/// One folder or file for the shaders of `Galaxy.metal`, which declare the same layout.
nonisolated struct GalaxyInstance {
    var position: SIMD2<Float>
    var radius: Float
    var value: Float
    var flags: UInt32 = 0
    var depth: UInt32 = 0
}

/// The camera and the level of detail for the shaders of `Galaxy.metal`, which declare the same layout.
nonisolated struct GalaxyUniforms {
    var center: SIMD2<Float>
    var viewport: SIMD2<Float>
    var scale: Float
    var tilt: Float
    var pixelsPerPoint: Float
    var starsAppear: Float
    var starsShown: Float
    var isSearching: UInt32
}

/// Draws a Galassia into its map: one instanced draw for the folders' rings, one for their points, one for the stars.
///
/// It draws only when asked: the map is paused and redraws on a change, so a still map costs no frames.
final class GalaxyRenderer: NSObject, MTKViewDelegate {
    /// Creates a renderer of `model` and configures `view` for it.
    ///
    /// - Throws: `GalaxyRendererError.metalUnavailable` when there is no Metal device or shader library.
    init(view: MTKView, model: GalaxyModel) throws {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { throw GalaxyRendererError.metalUnavailable }
        self.model = model
        self.device = device
        self.queue = queue
        ringPipeline = try Self.pipeline("galaxy_ring_vertex", "galaxy_ring_fragment", device: device, library: library)
        pointPipeline = try Self.pipeline("galaxy_point_vertex", "galaxy_disc_fragment", device: device,
                                          library: library)
        starPipeline = try Self.pipeline("galaxy_star_vertex", "galaxy_disc_fragment", device: device, library: library)
        selectionPipeline = try Self.pipeline("galaxy_selection_vertex", "galaxy_ring_fragment", device: device,
                                              library: library)
        super.init()
        view.device = device
        view.colorPixelFormat = Self.pixelFormat
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        // Palette.ink.
        view.clearColor = MTLClearColor(red: 0.047, green: 0.039, blue: 0.035, alpha: 1)
        view.delegate = self
    }

    /// Called after every frame, so the map can stop drawing continuously when a flight ends.
    var onDraw: (() -> Void)?

    private static let pixelFormat = MTLPixelFormat.bgra8Unorm
    private let model: GalaxyModel
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let ringPipeline: MTLRenderPipelineState
    private let pointPipeline: MTLRenderPipelineState
    private let starPipeline: MTLRenderPipelineState
    private let selectionPipeline: MTLRenderPipelineState
    private var clusters: MTLBuffer?
    private var stars: MTLBuffer?
    private var clusterCount = 0
    private var starCount = 0
    private var builtVersion = -1

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        model.advanceFlight(to: CACurrentMediaTime())
        if builtVersion != model.contentVersion { rebuild() }
        defer { onDraw?() }
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        let camera = model.camera
        let size = view.bounds.size
        var uniforms = GalaxyUniforms(center: camera.center, viewport: SIMD2(Float(size.width), Float(size.height)),
                                      scale: camera.scale, tilt: GalaxyCamera.tilt,
                                      pixelsPerPoint: Float(view.window?.backingScaleFactor ?? 2),
                                      starsAppear: GalaxyModel.starsAppearRadius,
                                      starsShown: GalaxyModel.starsShownRadius,
                                      isSearching: model.matches.isEmpty ? 0 : 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GalaxyUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GalaxyUniforms>.stride, index: 1)
        if let clusters, clusterCount > 0 {
            encoder.setVertexBuffer(clusters, offset: 0, index: 0)
            encoder.setRenderPipelineState(ringPipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: clusterCount)
            encoder.setRenderPipelineState(pointPipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: clusterCount)
        }
        if let stars, starCount > 0 {
            encoder.setVertexBuffer(stars, offset: 0, index: 0)
            encoder.setRenderPipelineState(starPipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: starCount)
        }
        if let selection = model.selection, let star = model.layout?.stars[selection] {
            var ring = GalaxyInstance(position: star.position, radius: 7, value: 0)
            encoder.setVertexBytes(&ring, length: MemoryLayout<GalaxyInstance>.stride, index: 0)
            encoder.setRenderPipelineState(selectionPipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
        model.didDraw()
    }

    /// Writes the folders and the stars again, with the search results and the selection.
    private func rebuild() {
        builtVersion = model.contentVersion
        guard let layout = model.layout else {
            clusterCount = 0
            starCount = 0
            return
        }
        let folders = layout.clusters.map { cluster in
            GalaxyInstance(position: cluster.center, radius: cluster.radius, value: Float(cluster.fileCount),
                           depth: UInt32(cluster.depth))
        }
        var files = layout.stars.map { star in
            GalaxyInstance(position: star.position, radius: star.spacing, value: layout.clusters[star.cluster].radius)
        }
        for index in model.matches { files[index].flags |= 1 }
        if let selection = model.selection { files[selection].flags |= 2 }
        clusters = makeBuffer(folders)
        stars = makeBuffer(files)
        clusterCount = folders.count
        starCount = files.count
    }

    private func makeBuffer(_ instances: [GalaxyInstance]) -> MTLBuffer? {
        guard !instances.isEmpty else { return nil }
        return instances.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
    }

    private static func pipeline(_ vertex: String, _ fragment: String, device: MTLDevice,
                                 library: MTLLibrary) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = pixelFormat
        // Premultiplied light over the dark plane.
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

/// Why the Galassia's map could not be drawn.
enum GalaxyRendererError: Error {
    /// No Metal device, command queue or compiled shader library.
    case metalUnavailable
}
