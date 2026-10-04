import CoreGraphics
import Foundation
import Testing
@testable import Bubo

@MainActor
struct OrbSnapshotterTests {
    private static let size = 128

    private let snapshotter: OrbSnapshotter
    private let lente: Variante

    init() throws {
        snapshotter = try OrbSnapshotter()
        lente = try #require(try Catalogo(bundle: .main).variante(named: "lente"))
    }

    /// The premultiplied BGRA bytes of `image`.
    private func pixels(of image: CGImage) throws -> [UInt8] {
        let data = try #require(image.dataProvider?.data as Data?)
        return [UInt8](data)
    }

    /// The pixel at `x`, `y` from the top left, as blue, green, red, alpha.
    private func pixel(_ bytes: [UInt8], x: Int, y: Int) -> [UInt8] {
        let start = (y * Self.size + x) * 4
        return Array(bytes[start..<start + 4])
    }

    @Test func drawsAStillOfTheRequestedSize() async throws {
        let image = try #require(await snapshotter.snapshot(of: lente, pixelSize: Self.size))
        #expect(image.width == Self.size && image.height == Self.size)
    }

    @Test func aVarianteWithoutAFormaIsDrawnAsTheBlob() async throws {
        let assente = Variante(nome: "fenice-di-prova", forma: "fenice_di_prova", categoria: .creativo, descrizione: "", parole: [])
        let bytes = try pixels(of: try #require(await snapshotter.snapshot(of: assente, pixelSize: Self.size)))
        #expect(pixel(bytes, x: Self.size / 2, y: Self.size / 2)[3] == 255)
        #expect(pixel(bytes, x: 0, y: 0)[3] < 8)
    }

    @Test func theLenteIsSolidAtItsGlassAndClearAtTheCorner() async throws {
        let bytes = try pixels(of: try #require(await snapshotter.snapshot(of: lente, pixelSize: Self.size)))
        #expect(pixel(bytes, x: Self.size / 2, y: Self.size / 2)[3] == 255)
        #expect(pixel(bytes, x: 0, y: 0)[3] < 8)
    }

    @Test func theHaloIsGreyAndFadesOutsideTheSilhouette() async throws {
        let bytes = try pixels(of: try #require(await snapshotter.snapshot(of: lente, pixelSize: Self.size)))
        // Along the row through the centre, the first pixels hit from the left edge are halo: partly transparent.
        let row = (0..<Self.size).map { pixel(bytes, x: $0, y: Self.size / 2) }
        let halo = try #require(row.first { (16..<255).contains($0[3]) })
        #expect(abs(Int(halo[0]) - Int(halo[2])) <= 1 && abs(Int(halo[1]) - Int(halo[2])) <= 1)
    }

    // The Orbite's pipeline builds, and its diagram is light strokes on a dark disc: a point of light at the centre,
    // ink between the strokes, nothing at the corner.
    @Test func theOrbiteDrawsItsDiagram() async throws {
        let image = try #require(await snapshotter.snapshot(of: Orbite.variante, pixelSize: Self.size))
        let bytes = try pixels(of: image)
        #expect(pixel(bytes, x: Self.size / 2, y: Self.size / 2).allSatisfy { $0 > 200 })
        let ground = pixel(bytes, x: Self.size / 2 + 5, y: Self.size / 2 - 30)
        #expect(ground[3] > 200 && ground[2] < 60)
        #expect(pixel(bytes, x: 0, y: 0)[3] < 8)
    }

    /// #400: once its Forma's pipeline is built, a cell's still is drawn on the main actor; it stays well under a hang
    /// (100 ms, spec 25), so the Galleria scrolls through 480 Varianti.
    @Test func aStillOnTheMainActorStaysUnderAHang() async throws {
        let varianti = try Catalogo(bundle: .main).varianti.prefix(24)
        let clock = ContinuousClock()
        for variante in varianti {
            _ = await snapshotter.snapshot(of: variante, pixelSize: 64) // builds the pipeline, waited for asynchronously
            let elapsed = await clock.measure { _ = await snapshotter.snapshot(of: variante, pixelSize: Self.size) }
            #expect(elapsed < .milliseconds(100), "\(variante.nome): \(elapsed)")
        }
    }

    @Test func aSecondRequestReturnsTheCachedStill() async throws {
        let first = try #require(await snapshotter.snapshot(of: lente, pixelSize: Self.size))
        let second = try #require(await snapshotter.snapshot(of: lente, pixelSize: Self.size))
        #expect(first === second)
    }
}
