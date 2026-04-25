import MetalKit
import simd

struct MandelbrotUniforms {
    var centerHi: SIMD2<Float>
    var centerLo: SIMD2<Float>
    var scaleHi: Float
    var scaleLo: Float
    var aspect: Float
    var maxIterations: UInt32
}

@inline(__always)
private func splitDouble(_ d: Double) -> (hi: Float, lo: Float) {
    let hi = Float(d)
    let lo = Float(d - Double(hi))
    return (hi, lo)
}

final class MandelbrotRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!

    var center = SIMD2<Double>(-0.5, 0.0)
    var scale: Double = 1.5
    var maxIterations: UInt32 = 512
    var aspect: Float = 1.0

    init?(metalView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        super.init()

        metalView.device = device
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let library = device.makeDefaultLibrary(),
              let vfn = library.makeFunction(name: "vertexShader"),
              let ffn = library.makeFunction(name: "fragmentShader") else {
            return nil
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = metalView.colorPixelFormat

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("Pipeline creation failed: \(error)")
            return nil
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        aspect = size.height > 0 ? Float(size.width / size.height) : 1.0
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        let cx = splitDouble(center.x)
        let cy = splitDouble(center.y)
        let s  = splitDouble(scale)

        var u = MandelbrotUniforms(
            centerHi: SIMD2<Float>(cx.hi, cy.hi),
            centerLo: SIMD2<Float>(cx.lo, cy.lo),
            scaleHi: s.hi,
            scaleLo: s.lo,
            aspect: aspect,
            maxIterations: maxIterations
        )

        enc.setRenderPipelineState(pipelineState)
        enc.setFragmentBytes(&u, length: MemoryLayout<MandelbrotUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }
}
