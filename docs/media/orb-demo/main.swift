// Renders the Orb off screen into PNG frames for docs/media/bubo-orb.gif, with the app's own shaders and
// motion code (OrbAnimation, OrbUniforms, Tinte). Built and run by render.sh; no window, no permissions.
// Usage: orb-demo <orb.metallib> <output dir>
import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

let width = 960, height = 540, fps = 25.0
/// `ink`, the design system's background.
let ink = MTLClearColor(red: 0x0A / 255.0, green: 0x0B / 255.0, blue: 0x0D / 255.0, alpha: 1)

/// One stretch of the demo: a Stato, a Tinta, and the Forma the Orb turns into and back from.
struct Beat {
    var seconds: Double
    var state: OrbState
    var tinta: Tinta
    /// The Forma shown during the beat; `.blob` for none.
    var forma: Forma = .blob
}

// Every change of Forma goes through the Blob, as the Regia del Morph does: the morph eases in over
// MorphDirector.morphDuration (1.1 s) and out again before the next Forma.
let script: [Beat] = [
    Beat(seconds: 1.0, state: .idle, tinta: .anthropic),
    Beat(seconds: 0.9, state: .listening, tinta: .anthropic),
    Beat(seconds: 0.9, state: .thinking, tinta: .anthropic),
    Beat(seconds: 2.5, state: .speaking, tinta: .anthropic, forma: Forma(rawValue: "cuore")),
    Beat(seconds: 2.5, state: .working, tinta: .openAI, forma: Forma(rawValue: "robot")),
    Beat(seconds: 2.5, state: .speaking, tinta: .google, forma: Forma(rawValue: "nota")),
    Beat(seconds: 0.9, state: .idle, tinta: .anthropic),
]
let morphDuration = 1.1

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: orb-demo <orb.metallib> <output dir>\n".utf8))
    exit(64)
}
let output = URL(filePath: arguments[2], directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    fatalError("No Metal device")
}
let library = try device.makeLibrary(URL: URL(filePath: arguments[1]))

var pipelines: [Forma: MTLRenderPipelineState] = [:]
func pipeline(for forma: Forma) throws -> MTLRenderPipelineState {
    if let ready = pipelines[forma] { return ready }
    // The same blending as OrbPipelines: premultiplied source over what is already there.
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "orbVertex")
    descriptor.fragmentFunction = library.makeFunction(name: forma.fragmentFunctionName)
    let color = descriptor.colorAttachments[0]!
    color.pixelFormat = .bgra8Unorm
    color.isBlendingEnabled = true
    color.sourceRGBBlendFactor = .one
    color.sourceAlphaBlendFactor = .one
    color.destinationRGBBlendFactor = .oneMinusSourceAlpha
    color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    let state = try device.makeRenderPipelineState(descriptor: descriptor)
    pipelines[forma] = state
    return state
}

let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
textureDescriptor.usage = [.renderTarget, .shaderRead]
textureDescriptor.storageMode = .shared
let target = device.makeTexture(descriptor: textureDescriptor)!

func smoothstep(_ x: Double) -> Float {
    let x = min(1, max(0, x))
    return Float(x * x * (3 - 2 * x))
}

/// How far the Orb has turned into the beat's Forma `elapsed` seconds into a beat of `length`.
func morph(elapsed: Double, length: Double) -> Float {
    smoothstep(elapsed / morphDuration) * smoothstep((length - elapsed) / morphDuration)
}

func writePNG(_ texture: MTLTexture, to url: URL) {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    let context = CGContext(
        data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

var animation = OrbAnimation(tinta: .anthropic)
var uniforms = OrbUniforms()
uniforms.resolution = SIMD2(Float(width), Float(height))
let step = 1 / fps
var frameIndex = 0

for beat in script {
    let frames = Int((beat.seconds * fps).rounded())
    for index in 0..<frames {
        animation.state = beat.state
        animation.targetTinta = beat.tinta
        animation.advance(by: step)
        uniforms.apply(animation)
        let shown = beat.forma == .blob ? 0 : morph(elapsed: Double(index) * step, length: beat.seconds)
        uniforms.morph = shown
        let forma = shown > 0 ? beat.forma : .blob

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = ink
        pass.colorAttachments[0].storeAction = .store
        let commands = queue.makeCommandBuffer()!
        let encoder = commands.makeRenderCommandEncoder(descriptor: pass)!
        encoder.setRenderPipelineState(try pipeline(for: forma))
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OrbUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        writePNG(target, to: output.appending(path: String(format: "frame-%04d.png", frameIndex)))
        frameIndex += 1
    }
}
print("\(frameIndex) frames in \(output.path)")
