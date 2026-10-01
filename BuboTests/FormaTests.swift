import Foundation
import Metal
import simd
import Testing
@testable import Bubo

/// The Forme's SDFs, read through `FormaProbe.metal`: right inside and outside, and nearly exact outside,
/// since the halo reads the ray's closest distance and an underestimate shows up as streaks.
@MainActor
struct FormaTests {
    /// Every Forma of the Catalogo.
    private nonisolated static let forme = Forma.allCases.filter { $0 != .blob }
    /// Shader times to check, still and mid-motion: the Forme with their own motion change over time.
    private nonisolated static let times: [Float] = [0, 0.72, 3.55, 7.5]
    /// The step of the finite differences.
    private static let step: Float = 0.002

    private let probe: SDFProbe

    init() throws {
        probe = try SDFProbe()
    }

    /// Points on a regular grid across the box that holds every Forma, with margin.
    private static let grid: [SIMD3<Float>] = {
        let count = 24, side: Float = 2.8
        var points: [SIMD3<Float>] = []
        for i in 0..<count {
            for j in 0..<count {
                for k in 0..<count {
                    points.append(SIMD3(Float(i), Float(j), Float(k)) / Float(count - 1) * side - side / 2)
                }
            }
        }
        return points
    }()

    /// Each grid point followed by its six neighbours one step away along ±x, ±y, ±z.
    private static func withNeighbours(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let offsets: [SIMD3<Float>] = [.zero, [step, 0, 0], [-step, 0, 0], [0, step, 0], [0, -step, 0], [0, 0, step], [0, 0, -step]]
        return points.flatMap { point in offsets.map { point + $0 } }
    }

    /// The central differences along x, y and z from seven distances laid out as `withNeighbours` lays out points.
    private static func gradient(_ d: ArraySlice<Float>) -> SIMD3<Float> {
        let i = d.startIndex
        return SIMD3(d[i + 1] - d[i + 2], d[i + 3] - d[i + 4], d[i + 5] - d[i + 6]) / (2 * step)
    }

    @Test(arguments: forme, times)
    func isFiniteEverywhere(forma: Forma, time: Float) throws {
        let distances = try probe.distances(of: forma, at: Self.grid, time: time)
        #expect(distances.allSatisfy { $0.isFinite })
    }

    /// No difference grows faster than the distance: an overestimate would let the ray step through the surface.
    @Test(arguments: forme, times)
    func neverOverestimates(forma: Forma, time: Float) throws {
        let distances = try probe.distances(of: forma, at: Self.withNeighbours(Self.grid), time: time)
        let steepest = stride(from: 0, to: distances.count, by: 7).map { (start: Int) -> Float in
            let g = Self.gradient(distances[start..<start + 7])
            return max(abs(g.x), abs(g.y), abs(g.z))
        }.max() ?? 0
        #expect(steepest <= 1.01)
    }

    /// Outside the solid the gradient is about 1, and stepping back by the distance along it lands on the
    /// surface. A few points sit on a crease of the field, where the differences mix two pieces; nowhere more.
    @Test(arguments: forme, times)
    func isNearlyExactOutside(forma: Forma, time: Float) throws {
        let distances = try probe.distances(of: forma, at: Self.withNeighbours(Self.grid), time: time)
        var outside: [(point: SIMD3<Float>, distance: Float, gradient: SIMD3<Float>)] = []
        for (index, point) in Self.grid.enumerated() where distances[index * 7] > 0.02 {
            outside.append((point, distances[index * 7], Self.gradient(distances[index * 7..<index * 7 + 7])))
        }
        let unit = outside.filter { (0.95...1.03).contains(length($0.gradient)) }
        let landings = try probe.distances(
            of: forma, at: unit.map { $0.point - normalize($0.gradient) * $0.distance }, time: time)
        let exact = zip(unit, landings).filter { abs($1) <= 0.01 + 0.03 * $0.distance }.count
        #expect(outside.count > Self.grid.count / 2)
        #expect(Double(exact) >= 0.98 * Double(outside.count), "\(exact) of \(outside.count)")
    }

    /// Points the silhouette must cover, and gaps it must leave, with the Forma still (time 0).
    @Test(arguments: forme)
    func coversItsSilhouette(forma: Forma) throws {
        let (inside, outside) = Self.samples(of: forma)
        let distances = try probe.distances(of: forma, at: inside + outside, time: 0)
        for (point, distance) in zip(inside, distances.prefix(inside.count)) {
            #expect(distance < 0, "\(point) should be inside")
        }
        for (point, distance) in zip(outside, distances.dropFirst(inside.count)) {
            #expect(distance > 0, "\(point) should be outside")
        }
    }

    @Test func theHeartSwellsOnTheBeat() throws {
        let belowTheTip: [SIMD3<Float>] = [[0, -0.8, 0]]  // on the axis the sway turns around
        let rest = try probe.distances(of: .cuore, at: belowTheTip, time: 0)[0]
        let beat = try probe.distances(of: .cuore, at: belowTheTip, time: 0.72)[0]
        #expect(beat < rest - 0.02)
    }

    @Test func theSandRunsOutOfTheTopCone() throws {
        let inTheTopCone: [SIMD3<Float>] = [[0, 0.45, 0]]
        let early = try probe.distances(of: .clessidra, at: inTheTopCone, time: 6.24)[0]
        let halfway = try probe.distances(of: .clessidra, at: inTheTopCone, time: 0)[0]
        #expect(early < 0 && halfway > 0)
    }

    /// Inside and outside points of each Forma at rest; y is up and the camera looks down -z.
    private static func samples(of forma: Forma) -> (inside: [SIMD3<Float>], outside: [SIMD3<Float>]) {
        switch forma {
        case .blob: ([.zero], [[0, 1.2, 0]])
        case .lente: ([[-0.17, 0.19, 0], [0.31, 0.19, 0]], [[0.6, 0.6, 0], [-0.17, 0.19, 0.2]])
        case .nuvola: ([[0.06, 0.13, 0], [0, -0.33, 0]], [[0, 0.8, 0], [0.75, 0.5, 0]])
        case .cuore: ([.zero, [0.33, 0.25, 0]], [[0, 0.72, 0], [0, -0.85, 0]])
        case .busta: ([.zero, [0.6, -0.4, 0]], [[0, 0.7, 0], [0, 0, 0.25]])
        case .clessidra: ([[0, 0.8, 0], [0.44, 0, 0], [0, 0.15, 0], [0, -0.6, 0]], [[0, 0.55, 0], [0.22, 0, 0]])
        case .parentesi: ([[-0.4, 0.4, 0], [-0.62, 0, 0], [0.4, -0.4, 0]], [.zero, [-0.4, 0.4, 0.15]])
        case .nota: ([[-0.38, -0.52, 0], [0.34, -0.4, 0], [0.14, 0.62, 0]], [[0.14, 0.1, 0], [-0.6, 0.5, 0]])
        case .pennello: ([[-0.51, -0.51, 0], [0.34, 0.34, 0]], [[0.5, -0.5, 0], [-0.5, 0.5, 0]])
        case .moneta: ([.zero, [0, 0.6, 0]], [[0, 0.9, 0], [0.75, 0.75, 0]])
        case .aereo: ([.zero, [0.35, 0.35, 0], [-0.35, 0.35, 0]], [[0.707, 0, 0], [0, 0.707, 0], [0, 0, 0.3]])
        case .fumetto: ([[0, 0.12, 0], [-0.46, -0.45, 0]], [[0.5, -0.5, 0], [0, 0.8, 0]])
        case .robot: ([[0, -0.19, 0], [0, 0.63, 0], [0.64, -0.18, 0], [0.24, -0.1, 0.36]], [[0.4, 0.5, 0], [0, -0.1, 0.4]])
        case .orbite: ([.zero], [[0, 0.3, 0]])
        }
    }
}

/// Reads a Forma's distance at many points at once, on the GPU, through the test bundle's `formaProbe` kernel.
@MainActor
private final class SDFProbe {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary
    private var pipelines: [Forma: MTLComputePipelineState] = [:]

    init() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        self.device = device
        queue = try #require(device.makeCommandQueue())
        library = try device.makeDefaultLibrary(bundle: Bundle(for: SDFProbe.self))
    }

    /// The distance of `forma` at each of `points`, at shader time `time`.
    func distances(of forma: Forma, at points: [SIMD3<Float>], time: Float) throws -> [Float] {
        guard !points.isEmpty else { return [] }
        let pipeline = try pipeline(for: forma)
        let input = points.map { SIMD4($0, time) }
        let inputBuffer = try #require(device.makeBuffer(bytes: input, length: input.count * MemoryLayout<SIMD4<Float>>.stride))
        let outputBuffer = try #require(device.makeBuffer(length: points.count * MemoryLayout<Float>.stride))
        let commands = try #require(queue.makeCommandBuffer())
        let encoder = try #require(commands.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.dispatchThreads(MTLSize(width: points.count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(64, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return Array(UnsafeBufferPointer(start: outputBuffer.contents().assumingMemoryBound(to: Float.self), count: points.count))
    }

    private func pipeline(for forma: Forma) throws -> MTLComputePipelineState {
        if let pipeline = pipelines[forma] { return pipeline }
        let constants = MTLFunctionConstantValues()
        var value = forma.functionConstant
        constants.setConstantValue(&value, type: .int, index: 0)
        let function = try library.makeFunction(name: "formaProbe", constantValues: constants)
        let pipeline = try device.makeComputePipelineState(function: function)
        pipelines[forma] = pipeline
        return pipeline
    }
}
