import Foundation
import Metal
import simd
import Testing
@testable import Bubo

/// The Forme's SDFs, read on the GPU through the probe kernel each Forma's file adds to the test bundle
/// (`FORMA_PROBE`): right inside and outside, and nearly exact outside, since the halo reads the ray's closest
/// distance and an underestimate shows up as streaks.
@MainActor
struct FormaTests {
    /// Every Forma with a file in `Orb/Forme`, read from the probe kernels of the test bundle's library.
    private nonisolated static let forme: [Forma] = {
        let library = try? MTLCreateSystemDefaultDevice()?.makeDefaultLibrary(bundle: Bundle(for: SDFProbe.self))
        return (library?.functionNames ?? [])
            .filter { $0.hasPrefix(SDFProbe.kernelPrefix) }
            .map { Forma(rawValue: String($0.dropFirst(SDFProbe.kernelPrefix.count))) }
            .sorted { $0.rawValue < $1.rawValue }
    }()
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
    /// Every Forma has its file and its samples, and no sample is left without its Forma.
    @Test func everyFormaHasItsSamples() {
        #expect(!Self.forme.isEmpty)
        #expect(Set(Self.forme.map(\.rawValue)) == Set(Self.samples.keys))
    }

    @Test(arguments: forme)
    func coversItsSilhouette(forma: Forma) throws {
        let (inside, outside) = try #require(Self.samples[forma.rawValue], "\(forma.rawValue) has no samples")
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
        let rest = try probe.distances(of: Forma(rawValue: "cuore"), at: belowTheTip, time: 0)[0]
        let beat = try probe.distances(of: Forma(rawValue: "cuore"), at: belowTheTip, time: 0.72)[0]
        #expect(beat < rest - 0.02)
    }

    @Test func theSandRunsOutOfTheTopCone() throws {
        let inTheTopCone: [SIMD3<Float>] = [[0, 0.45, 0]]
        let early = try probe.distances(of: Forma(rawValue: "clessidra"), at: inTheTopCone, time: 6.24)[0]
        let halfway = try probe.distances(of: Forma(rawValue: "clessidra"), at: inTheTopCone, time: 0)[0]
        #expect(early < 0 && halfway > 0)
    }

    /// Inside and outside points of each Forma at rest, by name; y is up and the camera looks down -z.
    /// A new Forma adds its own here.
    private static let samples: [String: (inside: [SIMD3<Float>], outside: [SIMD3<Float>])] = [
        "lente": ([[-0.17, 0.19, 0], [0.31, 0.19, 0]], [[0.6, 0.6, 0], [-0.17, 0.19, 0.2]]),
        "nuvola": ([[0.06, 0.13, 0], [0, -0.33, 0]], [[0, 0.8, 0], [0.75, 0.5, 0]]),
        "cuore": ([.zero, [0.33, 0.25, 0]], [[0, 0.72, 0], [0, -0.85, 0]]),
        "busta": ([.zero, [0.6, -0.4, 0]], [[0, 0.7, 0], [0, 0, 0.25]]),
        "clessidra": ([[0, 0.8, 0], [0.44, 0, 0], [0, 0.15, 0], [0, -0.6, 0]], [[0, 0.55, 0], [0.22, 0, 0]]),
        "parentesi": ([[-0.4, 0.4, 0], [-0.62, 0, 0], [0.4, -0.4, 0]], [.zero, [-0.4, 0.4, 0.15]]),
        "nota": ([[-0.38, -0.52, 0], [0.34, -0.4, 0], [0.14, 0.62, 0]], [[0.14, 0.1, 0], [-0.6, 0.5, 0]]),
        "pennello": ([[-0.51, -0.51, 0], [0.34, 0.34, 0]], [[0.5, -0.5, 0], [-0.5, 0.5, 0]]),
        "moneta": ([.zero, [0, 0.6, 0]], [[0, 0.9, 0], [0.75, 0.75, 0]]),
        "aereo": ([.zero, [0.35, 0.35, 0], [-0.35, 0.35, 0]], [[0.707, 0, 0], [0, 0.707, 0], [0, 0, 0.3]]),
        "fumetto": ([[0, 0.12, 0], [-0.46, -0.45, 0]], [[0.5, -0.5, 0], [0, 0.8, 0]]),
        "robot": ([[0, -0.19, 0], [0, 0.63, 0], [0.64, -0.18, 0], [0.24, -0.1, 0.36]], [[0.4, 0.5, 0], [0, -0.1, 0.4]]),
        "orbite": ([.zero], [[0, 0.3, 0]]),
        "gufo": ([[0, -0.3, 0], [0.44, 0.58, 0], [-0.22, 0.08, 0.31], [0, -0.15, 0.31]],
                 [[0, 0.75, 0], [0.75, -0.6, 0], [0, 0.08, 0.33]]),
        "terminale": ([.zero, [0.7, -0.5, 0], [0.1, -0.24, 0.14]], [[0, 0.9, 0], [0, 0, 0.3], [0.1, 0, 0.14]]),
        "matita": ([[-0.06, -0.06, 0], [0.47, 0.47, 0]], [[0.5, -0.5, 0], [-0.5, 0.5, 0]]),
        "insetto": ([[0, -0.1, 0], [0, 0.43, 0], [0.55, -0.1, 0]], [[0, 0.75, 0], [0.75, 0.1, 0]]),
        "provetta": ([[0, -0.3, 0]], [[0, 0.3, 0], [0.6, 0.6, 0]]),
        "ramo": ([[-0.32, 0, 0], [0.3, 0.4, 0]], [[0, -0.5, 0], [0.4, -0.5, 0]]),
        "globo": ([[0, 0.12, 0], [0, -0.8, 0]], [[0.75, -0.4, 0], [0.6, 0.8, 0]]),
        "punto_interrogativo": ([[0, -0.58, 0], [0, 0.66, 0], [0, -0.05, 0]], [[0, 0.36, 0], [-0.3, 0, 0]]),
        "imbuto": ([[0, 0.32, 0], [0, -0.12, 0]], [[0.5, -0.3, 0], [0, 0.9, 0]]),
        "cervello": ([[0, 0.3, 0], [0.18, -0.49, 0]], [[-0.6, -0.6, 0], [0, 0, 0.45]]),
        "gomma": ([.zero], [[0, 0.6, 0], [0, 0, 0.4]]),
        "calendario": ([.zero], [[0, 0.9, 0], [0.9, 0, 0]]),
        "fulmine": ([[-0.08, 0.3, 0], [0.05, -0.3, 0]], [[0.4, 0.6, 0], [-0.4, -0.6, 0]]),
        "giraffa": ([[-0.15, -0.1, 0], [0.3, 0.62, 0]], [[-0.5, 0.5, 0], [0.6, -0.5, 0]]),
        "boccale": ([[-0.1, -0.1, 0], [0.56, -0.12, 0]], [[0.36, -0.12, 0], [0, 0.95, 0], [-0.1, -0.8, 0]]),
        "evidenziatore": ([.zero, [0.17, 0.25, 0]], [[0.7, -0.7, 0], [-0.7, 0.7, 0]]),
        "pinguino": ([.zero, [0, 0.55, 0]], [[0.6, 0.5, 0], [0.5, -0.5, 0]]),
        "carte": ([[0, -0.3, 0], [0, 0.05, 0]], [[0, 0.3, 0], [0.8, -0.5, 0], [0, 0, 0.2]]),
        "tartaruga": ([.zero, [-0.5, 0, 0]], [[0, 0.6, 0], [0.7, -0.5, 0]]),
        "joystick": ([[0, -0.4, 0], [0, 0.35, 0]], [[0.7, -0.4, 0], [0.6, 0.3, 0], [0, 0.8, 0]]),
        "rana": ([[0, -0.2, 0], [0.2, 0.5, 0]], [[0.9, -0.2, 0], [0, 0.8, 0], [0.5, 0.2, 0]]),
        "cacciavite": ([[0.198, 0.289, 0], [-0.141, -0.206, 0]], [[-0.6, 0.6, 0], [0.6, -0.6, 0]]),
        "pappagallo": ([[0, 0.04, 0], [0.02, 0.54, 0], [0.5, -0.43, 0]], [[0.7, 0.5, 0], [-0.6, 0.5, 0]]),
        "nodo": ([[0, -0.138, 0], [0, -0.658, 0]], [[0.8, 0.7, 0], [-0.8, 0.7, 0], [0, 0.9, 0]]),
        "scimmia": ([[-0.15, 0.45, 0], [-0.15, -0.15, 0], [0.55, -0.35, 0]], [[-0.9, 0, 0], [0.1, 0.9, 0], [0.8, 0.6, 0]]),
        "elmo": ([.zero, [0, -0.5, 0], [0, 0.7, 0]], [[0.7, 0.3, 0], [0.6, -0.5, 0], [0.3, 0.7, 0]]),
        "cervo": ([[-0.09, -0.11, 0], [0.45, 0.27, 0], [0.24, 0.15, 0]], [[0.6, -0.5, 0], [-0.5, 0.5, 0]]),
        "scoiattolo": ([[0.2, -0.25, 0], [0.25, 0.25, 0], [-0.3, -0.05, 0]], [[0.7, 0, 0], [0.2, 0.8, 0], [0, 0.95, 0]]),
        "cavalluccio_marino": ([[0, 0.55, 0], [0, 0.1, 0], [0.25, 0.525, 0]], [[0.5, 0, 0], [-0.5, 0.5, 0], [0.3, -0.4, 0]]),
        "conchiglia": ([[-0.31, 0, 0], [0.457, 0, 0]], [[0.19, 0, 0], [0.9, 0.9, 0], [0, -0.9, 0]]),
        "ragno": ([[0, -0.25, 0], [0, 0.2, 0], [0.25, 0.39, 0]], [[0.4, 0.08, 0], [0, 0.9, 0], [0.9, -0.9, 0]]),
        "borsa_ghiaccio": ([.zero, [0, 0.61, 0], [0, 0.39, 0]], [[0.6, 0, 0], [0.3, 0.6, 0]]),
        "pinne": ([[0.33, 0.2, 0], [-0.33, 0.2, 0]], [[0, 0.2, 0], [0.8, 0, 0], [0, 0.9, 0]]),
        "zanzara": ([[-0.1, 0.12, 0], [-0.35, 0, 0], [0.07, 0.17, 0], [-0.27, 0.455, 0]], [[0.5, 0.5, 0], [-0.7, 0.4, 0], [0.4, -0.6, 0]]),
        "corda": ([[0, 0.8, 0], [0.62, -0.4, 0]], [[0, 0.3, 0], [0, -0.2, 0], [0.9, 0.5, 0]]),
        "sfigmomanometro": ([[0, 0.3, 0], [-0.25, -0.4, 0], [0.5, -0.15, 0]], [[0, 0.9, 0], [0.7, 0.6, 0], [0.1, -0.1, 0]]),
        "tappetino": ([[-0.3, 0, 0], [-0.3, 0.3, 0], [-0.1, -0.42, 0]], [[0.3, 0.3, 0], [0.3, -0.2, 0], [0, 0.8, 0]]),
        "telecomando": ([[0, 0.4, 0], [0.22, 0.0, 0.0]], [[0, 0.23, 0], [0.6, 0, 0], [0, 0.4, 0.2]]),
        "castello": ([[0, 0.4, 0], [0.62, 0.1, 0], [0.3, -0.4, 0], [0.14, 0.81, 0]], [[0, 0.81, 0], [0.3, 0.1, 0], [0.9, 0.6, 0]]),
        "cavallo_scacchi": ([[0, -0.3, 0], [0.1, 0.4, 0], [-0.2, 0.4, 0]], [[-0.6, -0.4, 0], [0.7, 0.5, 0], [0, 0, 0.3]]),
        "pallino_notifica": ([[0, 0, 0], [0.02, 0, 0.15], [0.5, 0.3, 0]], [[0.3, 0, 0.15], [0.9, 0, 0], [0, 0.8, 0]]),
        "uovo": ([[0, 0, 0], [0.5, -0.25, 0], [0, 0.6, 0]], [[0.5, 0.5, 0], [0.7, -0.3, 0], [0, 0.85, 0]]),
        "metro": ([[0.28, 0.18, 0], [-0.22, 0.18, 0], [0.5, -0.32, 0]], [[-0.22, 0.51, 0], [0.7, 0.5, 0], [-0.22, 0.18, 0.2]]),
        "podio": ([[0, 0, 0], [-0.52, -0.3, 0], [0.52, -0.5, 0], [0, 0.8, 0]], [[0.52, 0, 0], [-0.52, 0.2, 0], [0, 0.55, 0]]),
        "percentuale": ([[-0.22, 0.45, 0], [0, 0, 0], [0.62, -0.45, 0]], [[-0.42, 0.45, 0], [0.8, 0.5, 0], [0, 0.9, 0]]),
        "origami": ([[0.05, -0.1, 0], [-0.25, 0.35, 0], [0.55, 0.2, 0]], [[0.6, 0.8, 0], [-0.7, -0.5, 0]]),
        "gerarchia": ([[0, 0.55, 0], [-0.6, -0.55, 0], [0.6, -0.55, 0], [0.3, 0, 0]], [[0.3, 0.4, 0], [0.3, -0.5, 0]]),
        "pala_eolica": ([[0, 0.28, 0], [0, 0.6, 0], [0, -0.4, 0]], [[0.5, 0.6, 0], [0.4, -0.5, 0]]),
        "impronta": ([[0, 0, 0], [0.26, 0, 0], [0, 0.84, 0]], [[0.16, 0, 0], [0.9, 0, 0]]),
        "ventaglio": ([[0, 0.2, 0], [0.7, -0.15, 0], [0, -0.8, 0]], [[0, 0.6, 0], [0.9, -0.6, 0]]),
        "sassofono": ([[-0.28, 0.05, 0], [0.05, -0.75, 0], [0.4, 0.2, 0], [-0.42, 0.685, 0]], [[0, 0.2, 0], [-0.7, -0.3, 0]]),
        "zucca": ([[0, -0.15, 0], [0.7, -0.15, 0], [0.06, 0.53, 0]], [[0.8, 0.5, 0], [0, 0.7, 0], [0.85, -0.55, 0]]),
        "satellite": ([[0, 0, 0], [0.544, -0.297, 0], [-0.544, 0.297, 0], [0.12, 0.219, 0]], [[0, 0.6, 0], [0.5, 0.3, 0], [0, 0, 0.3]]),
        "ombrellone": ([[0.118, 0.382, 0], [-0.148, -0.478, 0], [0.698, -0.111, 0]], [[0.389, -0.434, 0], [0.654, -0.255, 0]]),
        "virgolette": ([[0.42, 0.35, 0], [-0.42, 0.35, 0], [0.25, -0.3, 0]], [[0, 0, 0], [0.42, -0.4, 0]]),
        "amo": ([[0.3, 0.0, 0], [0.0, -0.68, 0]], [[0.3, 0.59, 0], [0.0, 0.2, 0]]),
        "loto": ([[0, 0.4, 0], [0, -0.1, 0], [0.27, -0.2, 0]], [[0.4, 0.6, 0], [-0.9, 0.5, 0], [0.3, 0.5, 0]]),
        "germoglio": ([[0, -0.4, 0], [0.375, 0.35, 0], [-0.375, 0.35, 0]], [[0, 0.5, 0], [0.3, -0.4, 0]]),
        "stretta_di_mano": ([[0, 0, 0], [-0.4, 0.025, 0], [0.88, -0.06, 0]], [[0, 0.6, 0], [0.4, -0.5, 0]]),
        "vaso": ([[0, -0.25, 0], [0, 0.4, 0], [0.54, 0.34, 0]], [[0.3, 0.7, 0], [0.4, -0.8, 0], [0.3, 0.34, 0]]),
        "barbecue": ([[0, 0.2, 0], [0.49, -0.55, 0], [0, -0.5, 0]], [[0.25, -0.5, 0], [0.8, 0.2, 0]]),
    ]
}

/// Reads a Forma's distance at many points at once, on the GPU, through its probe kernel in the test bundle.
@MainActor
private final class SDFProbe {
    /// The prefix of every Forma's probe kernel: `probe_<name>`, made by `ORB_FORMA` with `FORMA_PROBE` defined.
    nonisolated static let kernelPrefix = "probe_"

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
        let function = try #require(library.makeFunction(name: Self.kernelPrefix + forma.rawValue))
        let pipeline = try device.makeComputePipelineState(function: function)
        pipelines[forma] = pipeline
        return pipeline
    }
}
