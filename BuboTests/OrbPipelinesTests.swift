import Metal
import Testing
@testable import Bubo

@MainActor
struct OrbPipelinesTests {
    private let pipelines: OrbPipelines

    init() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        pipelines = try OrbPipelines(device: device, library: try #require(device.makeDefaultLibrary()))
    }

    @Test func aFormaOfTheCatalogoCompilesOnFirstRequest() async throws {
        let lente = Forma(rawValue: "lente")
        #expect(pipelines.canDraw(lente))
        #expect(await pipelines.loadedPipeline(for: lente) != nil)
        #expect(pipelines.pipeline(for: lente) != nil)
    }

    /// Two requests while the Forma compiles share one compilation, so they get the same pipeline.
    @Test func concurrentRequestsShareOneCompilation() async throws {
        let nuvola = Forma(rawValue: "nuvola")
        async let first = pipelines.loadedPipeline(for: nuvola)
        async let second = pipelines.loadedPipeline(for: nuvola)
        let (a, b) = await (first, second)
        let pipeline = try #require(a)
        #expect(b === pipeline)
    }

    /// The renderer draws the Blob while a Forma has no pipeline.
    @Test func aFormaWithoutItsFileHasNoPipeline() async {
        let drago = Forma(rawValue: "drago")
        #expect(!pipelines.canDraw(drago))
        #expect(await pipelines.loadedPipeline(for: drago) == nil)
        #expect(pipelines.pipeline(for: drago) == nil)
    }
}
