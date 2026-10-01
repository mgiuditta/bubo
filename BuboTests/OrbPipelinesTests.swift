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
        #expect(pipelines.draws(lente))
        #expect(await pipelines.loadedPipeline(for: lente) != nil)
        #expect(pipelines.pipeline(for: lente) != nil)
    }

    /// The renderer draws the Blob while a Forma has no pipeline.
    @Test func aFormaWithoutItsFileHasNoPipeline() async {
        let drago = Forma(rawValue: "drago")
        #expect(!pipelines.draws(drago))
        #expect(await pipelines.loadedPipeline(for: drago) == nil)
        #expect(pipelines.pipeline(for: drago) == nil)
    }
}
