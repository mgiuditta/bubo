import Foundation
import Metal

/// The Orb's render pipelines, one per Forma, each built from the shader's `FORMA` function constant.
///
/// The Blob's pipeline is ready at once. Any other loads in the background on first request,
/// from the Metal 4 archive of the Release build or else by compiling; until it is ready the Orb stays Blob.
final class OrbPipelines {
    /// The Blob's pipeline, always ready.
    let blob: MTLRenderPipelineState

    /// Loads the Blob's pipeline and opens the Forme archive, if the bundle has one.
    ///
    /// - Throws: An error if the Blob's pipeline cannot be built.
    init(device: MTLDevice, library: MTLLibrary, bundle: Bundle = .main) throws {
        self.library = library
        compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        archive = bundle.url(forResource: "Forme", withExtension: "mtl4archive")
            .flatMap { try? device.makeArchive(url: $0) }
        blob = try Self.makePipeline(for: .blob, library: library, archive: archive, compiler: compiler)
    }

    private let library: MTLLibrary
    private let compiler: MTL4Compiler
    private let archive: MTL4Archive?
    private var ready: [Forma: MTLRenderPipelineState] = [:]
    private var requested: Set<Forma> = [.blob]

    /// The pipeline of `forma` if it is ready; otherwise `nil`, after starting to load it.
    func pipeline(for forma: Forma) -> MTLRenderPipelineState? {
        if forma == .blob { return blob }
        if let pipeline = ready[forma] { return pipeline }
        guard requested.insert(forma).inserted else { return nil }
        Task { [library, archive, compiler] in
            // A Forma that fails to build stays requested, so the Orb stays Blob instead of retrying every frame.
            ready[forma] = try? await Self.loadPipeline(for: forma, library: library, archive: archive, compiler: compiler)
        }
        return nil
    }

    @concurrent
    private static func loadPipeline(for forma: Forma, library: MTLLibrary, archive: MTL4Archive?,
                                     compiler: MTL4Compiler) async throws -> MTLRenderPipelineState {
        try makePipeline(for: forma, library: library, archive: archive, compiler: compiler)
    }

    private nonisolated static func makePipeline(for forma: Forma, library: MTLLibrary, archive: MTL4Archive?,
                                                 compiler: MTL4Compiler) throws -> MTLRenderPipelineState {
        let descriptor = makeDescriptor(for: forma, library: library)
        if let archived = try? archive?.makeRenderPipelineState(descriptor: descriptor) {
            return archived
        }
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    /// The pipeline of `forma`; `scripts/metal-archive.sh` describes the same pipelines for the archive.
    private nonisolated static func makeDescriptor(for forma: Forma, library: MTLLibrary) -> MTL4RenderPipelineDescriptor {
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "orbVertex"
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = "orbFragment"
        let constants = MTLFunctionConstantValues()
        var value = forma.functionConstant
        constants.setConstantValue(&value, type: .int, index: 0)
        let specialized = MTL4SpecializedFunctionDescriptor()
        specialized.functionDescriptor = fragment
        specialized.constantValues = constants

        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = specialized
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        color.blendingState = .enabled
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return descriptor
    }
}
