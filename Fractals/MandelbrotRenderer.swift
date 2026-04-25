import MetalKit
import simd

struct MandelbrotUniforms {
    var center: SIMD2<Float>
    var scale: Float
    var aspect: Float
    var maxIterations: UInt32
}

final class MandelbrotRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!

    var center = SIMD2<Float>(-0.5, 0.0)
    var scale: Float = 1.5
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

        var u = MandelbrotUniforms(center: center,
                                   scale: scale,
                                   aspect: aspect,
                                   maxIterations: maxIterations)

        enc.setRenderPipelineState(pipelineState)
        enc.setFragmentBytes(&u, length: MemoryLayout<MandelbrotUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }
}
