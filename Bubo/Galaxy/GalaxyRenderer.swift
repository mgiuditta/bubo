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

/// A ring or a disc of a fixed size in points for the shaders of `Galaxy.metal`, which declare the same layout.
nonisolated struct GalaxyMark {
    var position: SIMD2<Float>
    var radius: Float
    /// How high over the plane, in points.
    var lift: Float = 0
    var alpha: Float
}

/// A line between two raised points of the plane for the shaders of `Galaxy.metal`, which declare the same layout.
nonisolated struct GalaxySegment {
    var from: SIMD2<Float>
    var to: SIMD2<Float>
    var liftFrom: Float
    var liftTo: Float
    var alphaFrom: Float
    var alphaTo: Float
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
    var coreRadius: Float
    var isSearching: UInt32
    var writeLift: Float
}

/// Draws a Galassia into its map: one instanced draw for the folders' rings, one for their points, one for the stars;
/// then the files the Sessioni touched, their collisions and their comets.
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
        ringMarkPipeline = try Self.pipeline("galaxy_mark_vertex", "galaxy_ring_fragment", device: device,
                                             library: library)
        discMarkPipeline = try Self.pipeline("galaxy_mark_vertex", "galaxy_disc_fragment", device: device,
                                             library: library)
        segmentPipeline = try Self.pipeline("galaxy_segment_vertex", "galaxy_segment_fragment", device: device,
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
    private let ringMarkPipeline: MTLRenderPipelineState
    private let discMarkPipeline: MTLRenderPipelineState
    private let segmentPipeline: MTLRenderPipelineState
    private var clusters: MTLBuffer?
    private var stars: MTLBuffer?
    private var clusterCount = 0
    private var starCount = 0
    private var builtVersion = -1
    /// The files the Sessioni touched, the stems of the written ones and the double rings of the collisions.
    private var litStars: MTLBuffer?
    private var stems: MTLBuffer?
    private var collisions: MTLBuffer?
    private var litStarCount = 0
    private var stemCount = 0
    private var collisionCount = 0
    private var builtActivityVersion = -1

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        model.advance(to: now)
        if builtVersion != model.contentVersion { rebuild() }
        if builtActivityVersion != model.activityVersion { rebuildActivity() }
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
                                      coreRadius: GalaxyLayout.coreRadius,
                                      isSearching: model.matches.isEmpty ? 0 : 1, writeLift: GalaxyModel.writeLift)
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
        drawActivity(with: encoder)
        drawComets(at: now, with: encoder)
        if let selection = model.selection, let star = model.layout?.stars[selection] {
            var ring = GalaxyMark(position: star.position, radius: 9, lift: model.lift(of: star.path), alpha: 0.9)
            encoder.setVertexBytes(&ring, length: MemoryLayout<GalaxyMark>.stride, index: 0)
            encoder.setRenderPipelineState(ringMarkPipeline)
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
            GalaxyInstance(position: star.position, radius: star.spacing, value: 0)
        }
        for index in model.matches { files[index].flags |= 1 }
        if let selection = model.selection { files[selection].flags |= 2 }
        clusters = makeBuffer(folders)
        stars = makeBuffer(files)
        clusterCount = folders.count
        starCount = files.count
    }

    /// Draws the files the Sessioni touched over the stars, the written ones raised on their stems.
    private func drawActivity(with encoder: MTLRenderCommandEncoder) {
        if let stems, stemCount > 0 {
            encoder.setVertexBuffer(stems, offset: 0, index: 0)
            encoder.setRenderPipelineState(segmentPipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: stemCount)
        }
        if let litStars, litStarCount > 0 {
            encoder.setVertexBuffer(litStars, offset: 0, index: 0)
            encoder.setRenderPipelineState(starPipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: litStarCount)
        }
        if let collisions, collisionCount > 0 {
            encoder.setVertexBuffer(collisions, offset: 0, index: 0)
            encoder.setRenderPipelineState(ringMarkPipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: collisionCount)
        }
    }

    /// Draws each comet: its tail fading through the files touched before, then its head.
    private func drawComets(at now: CFTimeInterval, with encoder: MTLRenderCommandEncoder) {
        let comets = model.comets(at: now)
        guard !comets.isEmpty else { return }
        var segments: [GalaxySegment] = []
        var heads: [GalaxyMark] = []
        for comet in comets {
            let points = comet.tail + [(position: comet.head, lift: comet.headLift)]
            for (offset, pair) in zip(points, points.dropFirst()).enumerated() {
                let fade = { (index: Int) in 0.7 * Float(index + 1) / Float(points.count) }
                segments.append(GalaxySegment(from: pair.0.position, to: pair.1.position, liftFrom: pair.0.lift,
                                              liftTo: pair.1.lift, alphaFrom: fade(offset), alphaTo: fade(offset + 1)))
            }
            heads.append(GalaxyMark(position: comet.head, radius: 3, lift: comet.headLift, alpha: 1))
        }
        if !segments.isEmpty, setVertexInstances(segments, on: encoder) {
            encoder.setRenderPipelineState(segmentPipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: segments.count)
        }
        if setVertexInstances(heads, on: encoder) {
            encoder.setRenderPipelineState(discMarkPipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: heads.count)
        }
    }

    /// Hands `instances` to the vertex shader: inline when they fit Metal's 4 KB, else in a new buffer. A comet moves
    /// for a few frames only, so a buffer each frame is rare.
    private func setVertexInstances<Instance>(_ instances: [Instance], on encoder: MTLRenderCommandEncoder) -> Bool {
        instances.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return false }
            if bytes.count <= 4096 {
                encoder.setVertexBytes(base, length: bytes.count, index: 0)
            } else {
                guard let buffer = device.makeBuffer(bytes: base, length: bytes.count, options: .storageModeShared)
                else { return false }
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            }
            return true
        }
    }

    /// Writes again the files the Sessioni touched, the stems of the written ones and the collisions' double rings.
    private func rebuildActivity() {
        builtActivityVersion = model.activityVersion
        guard let layout = model.layout else {
            litStarCount = 0
            stemCount = 0
            collisionCount = 0
            return
        }
        var lit: [GalaxyInstance] = []
        var stems: [GalaxySegment] = []
        var collisions: [GalaxyMark] = []
        for star in model.litStars() {
            let position = layout.stars[star.index].position
            lit.append(GalaxyInstance(position: position, radius: 0, value: 0, flags: star.isWritten ? 8 : 4))
            guard star.isWritten else { continue }
            stems.append(GalaxySegment(from: position, to: position, liftFrom: 0, liftTo: GalaxyModel.writeLift,
                                       alphaFrom: 0.1, alphaTo: 0.35))
            if star.isCollision {
                for radius: Float in [4, 6] {
                    collisions.append(GalaxyMark(position: position, radius: radius, lift: GalaxyModel.writeLift,
                                                 alpha: 0.85))
                }
            }
        }
        litStars = makeBuffer(lit)
        self.stems = makeBuffer(stems)
        self.collisions = makeBuffer(collisions)
        litStarCount = lit.count
        stemCount = stems.count
        collisionCount = collisions.count
    }

    private func makeBuffer<Instance>(_ instances: [Instance]) -> MTLBuffer? {
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
