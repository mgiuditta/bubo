import Foundation
import Metal
import OSLog

/// The Orb's render pipelines, one per Forma, each built from the Forma's own fragment function (ADR 0010).
///
/// The Blob's pipeline is ready at once: the Release build ships it compiled, in a Metal 4 archive with a library of
/// its own; otherwise it compiles. Any other Forma compiles in the background on first request and stays in memory;
/// until it is ready the Orb stays Blob. Metal keeps compiled pipelines in its shader cache, so later launches find
/// them almost at once.
final class OrbPipelines {
    /// The Blob's pipeline, always ready.
    let blob: MTLRenderPipelineState

    /// Loads the Blob's pipeline, from the bundle's archive if it has one.
    ///
    /// - Throws: An error if the Blob's pipeline cannot be built.
    init(device: MTLDevice, library: MTLLibrary, bundle: Bundle = .main) throws {
        self.library = library
        functionNames = Set(library.functionNames)
        compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        // An archive finds a pipeline only through the very library it was built from, and archiving from the
        // default library would compile every Forma into it: the archive has its own library, Orb.metal alone.
        do {
            blob = try Self.makeArchivedBlob(device: device, bundle: bundle)
        } catch {
            #if !DEBUG
            // The Release build always ships the archive: without it the launch compiles on the main thread.
            Logger.orb.fault("Blob missing from the Metal 4 archive: \(error.localizedDescription, privacy: .public)")
            #endif
            blob = try compiler.makeRenderPipelineState(descriptor: Self.makeDescriptor(for: .blob, library: library))
        }
    }

    private let library: MTLLibrary
    /// The library's function names, read once: `functionNames` builds a new array on every call.
    private let functionNames: Set<String>
    private let compiler: MTL4Compiler
    private var ready: [Forma: MTLRenderPipelineState] = [:]
    private var loads: [Forma: Task<MTLRenderPipelineState?, Never>] = [:]
    /// The Forme whose compilation failed: they wait for `prepare(_:)` to try again, not for the next frame.
    private var failures: Set<Forma> = []

    /// Whether the shader library has the fragment function of `forma`; without it the Orb draws the Blob.
    func canDraw(_ forma: Forma) -> Bool {
        functionNames.contains(forma.fragmentFunctionName)
    }

    /// Starts loading `forma` for a new request, trying again if it failed to compile before.
    func prepare(_ forma: Forma) {
        guard forma != .blob, ready[forma] == nil else { return }
        failures.remove(forma)
        load(forma)
    }

    /// The pipeline of `forma` if it is ready; otherwise `nil`, after starting to load it unless it failed.
    func pipeline(for forma: Forma) -> MTLRenderPipelineState? {
        if forma == .blob { return blob }
        if let pipeline = ready[forma] { return pipeline }
        if !failures.contains(forma) { load(forma) }
        return nil
    }

    /// The pipeline of `forma`, waiting for it to load if needed; `nil` if it fails to build.
    func loadedPipeline(for forma: Forma) async -> MTLRenderPipelineState? {
        if forma == .blob { return blob }
        if let pipeline = ready[forma] { return pipeline }
        return await load(forma).value
    }

    /// Starts loading `forma` unless it already started, and returns that load.
    @discardableResult
    private func load(_ forma: Forma) -> Task<MTLRenderPipelineState?, Never> {
        if let load = loads[forma] { return load }
        // Without its fragment function Metal would still build a pipeline, one that draws nothing.
        // A Forma without one keeps its load, so the Orb stays Blob instead of retrying every frame.
        let isDrawn = canDraw(forma)
        let load = Task { [library, compiler] () -> MTLRenderPipelineState? in
            guard isDrawn else { return nil }
            do {
                let pipeline = try await Signposts.measure(.formaCompilation) {
                    try await Self.compilePipeline(for: forma, library: library, compiler: compiler)
                }
                ready[forma] = pipeline
                return pipeline
            } catch {
                Logger.orb.error(
                    "Forma \(forma.rawValue, privacy: .public) failed to compile: \(error.localizedDescription, privacy: .public)")
                loads[forma] = nil
                failures.insert(forma)
                return nil
            }
        }
        loads[forma] = load
        return load
    }

    @concurrent
    private static func compilePipeline(for forma: Forma, library: MTLLibrary,
                                        compiler: MTL4Compiler) async throws -> MTLRenderPipelineState {
        try await compiler.makeRenderPipelineState(descriptor: makeDescriptor(for: forma, library: library))
    }

    /// The Blob's pipeline from the archive the Release build makes with `scripts/metal-archive.sh`.
    ///
    /// - Throws: An error if the bundle has no archive or its library, or the archive lacks the pipeline.
    private static func makeArchivedBlob(device: MTLDevice, bundle: Bundle) throws -> MTLRenderPipelineState {
        guard let libraryURL = bundle.url(forResource: "Orb", withExtension: "metallib"),
              let archiveURL = bundle.url(forResource: "Orb", withExtension: "mtl4archive")
        else { throw CocoaError(.fileNoSuchFile) }
        let library = try device.makeLibrary(URL: libraryURL)
        let archive = try device.makeArchive(url: archiveURL)
        return try archive.makeRenderPipelineState(descriptor: makeDescriptor(for: .blob, library: library))
    }

    /// The pipeline of `forma`; `scripts/metal-archive.sh` describes the Blob's the same way for the archive.
    private nonisolated static func makeDescriptor(for forma: Forma, library: MTLLibrary) -> MTL4RenderPipelineDescriptor {
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "orbVertex"
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = forma.fragmentFunctionName

        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = fragment
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

private extension Logger {
    static let orb = Logger(subsystem: "com.mgiuditta.bubo", category: "orb")
}
