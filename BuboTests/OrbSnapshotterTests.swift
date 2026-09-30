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

    @Test func aSecondRequestReturnsTheCachedStill() async throws {
        let first = try #require(await snapshotter.snapshot(of: lente, pixelSize: Self.size))
        let second = try #require(await snapshotter.snapshot(of: lente, pixelSize: Self.size))
        #expect(first === second)
    }
}
