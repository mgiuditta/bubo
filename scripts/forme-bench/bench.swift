// Runtime measurements of ADR 0010 (#378). Prints TSV rows: what, value, unit.
// Usage:
//   bench compile <metallib> <fragment>...            per-function pipelines (C), Blob first
//   bench fc <metallib> <index>...                    FORMA function constant pipelines (B)
//   bench archive <metallib> <archive> <index>...     FC pipelines from the Metal 4 archive (A)
//   bench blobarchive <metallib> <Orb.metallib> <archive> <fragment>...  Blob from its own archive, then C
//   bench gpu <metallib> <fragment> <index> <frames>  GPU time of one pipeline, morph 1
import Foundation
import Metal

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

func footprint() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

func row(_ what: String, _ value: Double, _ unit: String) { print("\(what)\t\(String(format: "%.2f", value))\t\(unit)") }

func descriptor(library: MTLLibrary, fragment: String, constant: Int32?) -> MTL4RenderPipelineDescriptor {
    let vertex = MTL4LibraryFunctionDescriptor()
    vertex.library = library
    vertex.name = "orbVertex"
    let base = MTL4LibraryFunctionDescriptor()
    base.library = library
    base.name = fragment
    let d = MTL4RenderPipelineDescriptor()
    d.vertexFunctionDescriptor = vertex
    if var value = constant {
        let constants = MTLFunctionConstantValues()
        constants.setConstantValue(&value, type: .int, index: 0)
        let specialized = MTL4SpecializedFunctionDescriptor()
        specialized.functionDescriptor = base
        specialized.constantValues = constants
        d.fragmentFunctionDescriptor = specialized
    } else {
        d.fragmentFunctionDescriptor = base
    }
    let color = d.colorAttachments[0]!
    color.pixelFormat = .bgra8Unorm
    color.blendingState = .enabled
    color.sourceRGBBlendFactor = .one
    color.sourceAlphaBlendFactor = .one
    color.destinationRGBBlendFactor = .oneMinusSourceAlpha
    color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    return d
}

let args = CommandLine.arguments
let device = MTLCreateSystemDefaultDevice()!
let mode = args[1]
let m0 = footprint()
var t = now()
let library = try device.makeLibrary(URL: URL(filePath: args[2]))
row("library load", (now() - t) * 1000, "ms")
let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
let m1 = footprint()
row("footprint after library+compiler", m1 - m0, "MB")
var keep: [MTLRenderPipelineState] = []

switch mode {
case "compile", "fc":
    let isFC = mode == "fc"
    let blob = descriptor(library: library, fragment: isFC ? "orbFragment" : "forma_blob", constant: isFC ? 0 : nil)
    t = now()
    keep.append(try compiler.makeRenderPipelineState(descriptor: blob))
    row("blob compile", (now() - t) * 1000, "ms")
    var times: [Double] = []
    for item in args[3...] {
        let d = isFC ? descriptor(library: library, fragment: "orbFragment", constant: Int32(item)!)
                     : descriptor(library: library, fragment: item, constant: nil)
        t = now()
        keep.append(try compiler.makeRenderPipelineState(descriptor: d))
        times.append((now() - t) * 1000)
    }
    times.sort()
    row("forma compile median", times[times.count / 2], "ms")
    row("forma compile max", times.last!, "ms")
    row("footprint per forma pipeline", (footprint() - m1) / Double(keep.count), "MB")
case "archive":
    t = now()
    let archive = try device.makeArchive(url: URL(filePath: args[3]))
    row("archive open", (now() - t) * 1000, "ms")
    row("footprint after archive open", footprint() - m1, "MB")
    var times: [Double] = []
    for item in args[4...] {
        let d = descriptor(library: library, fragment: "orbFragment", constant: Int32(item)!)
        t = now()
        keep.append(try archive.makeRenderPipelineState(descriptor: d))
        times.append((now() - t) * 1000)
    }
    times.sort()
    row("archive pipeline median", times[times.count / 2], "ms")
    row("archive pipeline max", times.last!, "ms")
    row("footprint after archive pipelines", footprint() - m1, "MB")
case "blobarchive":
    t = now()
    let blobLibrary = try device.makeLibrary(URL: URL(filePath: args[3]))
    let archive = try device.makeArchive(url: URL(filePath: args[4]))
    row("blob library + archive open", (now() - t) * 1000, "ms")
    t = now()
    let blob = try archive.makeRenderPipelineState(descriptor: descriptor(library: blobLibrary, fragment: "forma_blob", constant: nil))
    keep.append(blob)
    row("blob from archive", (now() - t) * 1000, "ms")
    var times: [Double] = []
    for item in args[5...] {
        t = now()
        keep.append(try compiler.makeRenderPipelineState(descriptor: descriptor(library: library, fragment: item, constant: nil)))
        times.append((now() - t) * 1000)
    }
    row("first forma compile (compiler not warmed by the Blob)", times[0], "ms")
    times.sort()
    row("forma compile median", times[times.count / 2], "ms")
    row("footprint after blob + formas", footprint() - m1, "MB")
case "gpu":
    let fragment = args[3], index = Float(args[4])!, frames = Int(args[5])!
    let constant: Int32? = fragment == "orbFragment" && args.count > 6 ? Int32(args[6])! : nil
    t = now()
    let pipeline = try compiler.makeRenderPipelineState(descriptor: descriptor(library: library, fragment: fragment, constant: constant))
    row("pipeline compile", (now() - t) * 1000, "ms")
    let queue = device.makeCommandQueue()!
    let side = 600 // the Panel's Orb at 300 pt on a 2x display
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: side, height: side, mipmapped: false)
    td.usage = .renderTarget
    td.storageMode = .private
    let texture = device.makeTexture(descriptor: td)!
    // Uniforms laid out as in OrbShading.h: res, t, amp, freq, speed, swirl, spike, glow, audio, frame,
    // morph, grain, bands, gloss, opacity, diagramTime (the uber index), pad, a, b.
    var gpu: [Double] = []
    for frame in 0..<frames {
        var u = [Float](repeating: 0, count: 28)
        u[0] = Float(side); u[1] = Float(side); u[2] = Float(frame) / 60; u[3] = 0.07; u[4] = 1.5; u[5] = 0.3
        u[8] = 0.9; u[10] = 1.3; u[11] = 1; u[15] = 1; u[16] = index
        u[20] = 0.6; u[21] = 0.6; u[22] = 0.6; u[24] = 0.92; u[25] = 0.92; u[26] = 0.92
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let commands = queue.makeCommandBuffer()!
        let encoder = commands.makeRenderCommandEncoder(descriptor: pass)!
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&u, length: u.count * 4, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        if frame >= 100 { gpu.append((commands.gpuEndTime - commands.gpuStartTime) * 1000) }
    }
    gpu.sort()
    row("gpu median", gpu[gpu.count / 2], "ms")
    row("gpu p95", gpu[gpu.count * 95 / 100], "ms")
default:
    fatalError("mode")
}
