import MetalKit
import QuartzCore

/// One note for the shaders of `Neurons.metal`, which declare the same layout.
nonisolated struct NeuronNode {
    var position: SIMD2<Float>
    var radius: Float
    /// The folder's color, as RGBA bytes.
    var color: UInt32
    /// 1 when the folder filter or the search leaves the note out.
    var flags: UInt32
}

/// The camera for the shaders of `Neurons.metal`, which declare the same layout.
nonisolated struct NeuronUniforms {
    var center: SIMD2<Float>
    var viewport: SIMD2<Float>
    var scale: Float
    var pixelsPerPoint: Float
    var selected: UInt32
}

/// Draws the Neuroni: one instanced draw for the links, one for the notes, one for the rings of the selected and the
/// cited notes.
///
/// It draws only when asked: the map is paused and redraws on a change, so a still map costs no frames.
final class NeuronRenderer: NSObject, MTKViewDelegate {
    /// Creates a renderer of `model` and configures `view` for it.
    ///
    /// - Throws: `GalaxyRendererError.metalUnavailable` when there is no Metal device or shader library.
    init(view: MTKView, model: NeuronModel) throws {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { throw GalaxyRendererError.metalUnavailable }
        self.model = model
        self.device = device
        self.queue = queue
        linkPipeline = try Self.pipeline("neuron_link_vertex", "neuron_link_fragment", device: device, library: library)
        nodePipeline = try Self.pipeline("neuron_node_vertex", "neuron_disc_fragment", device: device, library: library)
        ringPipeline = try Self.pipeline("neuron_ring_vertex", "neuron_ring_fragment", device: device, library: library)
        super.init()
        view.device = device
        view.colorPixelFormat = Self.pixelFormat
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        // Palette.ink.
        view.clearColor = MTLClearColor(red: 0.039, green: 0.043, blue: 0.051, alpha: 1)
        view.delegate = self
    }

    /// Called after every frame, so the map can stop drawing continuously when a flight ends.
    var onDraw: (() -> Void)?

    /// The colors of the top folders, muted so that none reads as a signal (design system, Neuroni); a note at the
    /// top is grey.
    static let folderColors: [UInt32] = [0x8FA8C8, 0xB59A86, 0x8EB59B, 0xB39CC4, 0xC2B07E, 0x86B3B8, 0xC497A6, 0xA3AC86]
    /// The color of the notes at the top: Palette.textSecondary.
    static let topColor: UInt32 = 0x8E939B

    /// The color of `folder`, one of `folders`, as `0xRRGGBB`.
    static func color(of folder: String, among folders: [String]) -> UInt32 {
        guard !folder.isEmpty, let index = folders.filter({ !$0.isEmpty }).firstIndex(of: folder) else { return topColor }
        return folderColors[index % folderColors.count]
    }

    private static let pixelFormat = MTLPixelFormat.bgra8Unorm
    private let model: NeuronModel
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let linkPipeline: MTLRenderPipelineState
    private let nodePipeline: MTLRenderPipelineState
    private let ringPipeline: MTLRenderPipelineState
    private var nodes: MTLBuffer?
    private var links: MTLBuffer?
    private var rings: MTLBuffer?
    private var nodeCount = 0
    private var linkCount = 0
    private var ringCount = 0
    private var builtVersion = -1

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        model.advance(to: CACurrentMediaTime())
        if builtVersion != model.contentVersion { rebuild() }
        defer { onDraw?() }
        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        let size = view.bounds.size
        var uniforms = NeuronUniforms(center: model.camera.center,
                                      viewport: SIMD2(Float(size.width), Float(size.height)),
                                      scale: model.camera.scale,
                                      pixelsPerPoint: Float(view.window?.backingScaleFactor ?? 2),
                                      selected: model.selection.map(UInt32.init) ?? .max)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<NeuronUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<NeuronUniforms>.stride, index: 1)
        if let nodes, let links, linkCount > 0 {
            encoder.setVertexBuffer(links, offset: 0, index: 0)
            encoder.setVertexBuffer(nodes, offset: 0, index: 2)
            encoder.setRenderPipelineState(linkPipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: linkCount)
        }
        if let nodes, nodeCount > 0 {
            encoder.setVertexBuffer(nodes, offset: 0, index: 0)
            encoder.setRenderPipelineState(nodePipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: nodeCount)
        }
        if let rings, ringCount > 0 {
            encoder.setVertexBuffer(rings, offset: 0, index: 0)
            encoder.setRenderPipelineState(ringPipeline)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: ringCount)
        }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    /// Writes the notes, the links and the rings again.
    private func rebuild() {
        builtVersion = model.contentVersion
        guard let graph = model.graph else {
            (nodeCount, linkCount, ringCount) = (0, 0, 0)
            return
        }
        let folders = graph.folders
        let colors = Dictionary(uniqueKeysWithValues: folders.map { ($0, Self.color(of: $0, among: folders)) })
        let instances = graph.notes.enumerated().map { index, note in
            // RGBA bytes, red first in memory.
            let rgb = colors[note.folder] ?? Self.topColor
            let color = (rgb >> 16) | (rgb & 0xff00) | ((rgb & 0xff) << 16) | 0xff00_0000
            return NeuronNode(position: model.positions[index], radius: NeuronModel.radius(of: note), color: color,
                              flags: model.isShown(index) ? 0 : 1)
        }
        let ringed = ([model.selection].compactMap { $0 } + model.cited.sorted()).map { instances[$0] }
        nodes = makeBuffer(instances)
        links = makeBuffer(graph.edges)
        rings = makeBuffer(ringed)
        (nodeCount, linkCount, ringCount) = (instances.count, graph.edges.count, ringed.count)
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
