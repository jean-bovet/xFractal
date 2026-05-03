import MetalKit
import simd

struct FractalUniforms {
    var centerHi: SIMD2<Float>
    var centerLo: SIMD2<Float>
    var scaleHi: Float
    var scaleLo: Float
    var aspect: Float
    var maxIterations: UInt32
    var usePerturbation: UInt32
    var refOrbitLength: UInt32
    var refOffset: SIMD2<Float>
    var fractalType: UInt32
    var palette: UInt32
    var smooth: UInt32
    var multibrotExponent: UInt32
    var newtonFlavor: UInt32
    var juliaC: SIMD2<Float>
}

private struct OrbitCache {
    var center: SIMD2<Double>
    var scale: Double
    var aspect: Float
    var maxIter: UInt32
    var buffer: MTLBuffer
    var length: UInt32
    var refOffset: SIMD2<Float>
}

final class FractalRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineState: MTLRenderPipelineState!

    var state: ViewState = .defaultState
    var aspect: Float = 1.0

    private var orbitCache: OrbitCache?
    private let dummyOrbit: MTLBuffer

    init?(metalView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue

        var zero = SIMD2<Float>(0, 0)
        guard let dummy = device.makeBuffer(bytes: &zero,
                                            length: MemoryLayout<SIMD2<Float>>.stride,
                                            options: .storageModeShared) else { return nil }
        self.dummyOrbit = dummy

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

    private func ensureOrbit() -> (MTLBuffer, UInt32, SIMD2<Float>) {
        guard state.type == .mandelbrot, state.usePerturbation else {
            return (dummyOrbit, 0, .zero)
        }

        if let c = orbitCache,
           c.center == state.center,
           c.scale == state.scale,
           c.aspect == aspect,
           c.maxIter == state.maxIterations {
            return (c.buffer, c.length, c.refOffset)
        }

        let refC = pickMandelbrotReference(center: state.center,
                                           scale: state.scale,
                                           aspect: Double(aspect),
                                           maxIterations: Int(state.maxIterations))
        let refOffset = SIMD2<Float>(Float(state.centerX - refC.x),
                                     Float(state.centerY - refC.y))

        let orbit = mandelbrotOrbit(referenceC: refC,
                                    maxIterations: Int(state.maxIterations))
        let length = orbit.count * MemoryLayout<SIMD2<Float>>.stride
        let buf = orbit.withUnsafeBytes { raw -> MTLBuffer? in
            guard let base = raw.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: length, options: .storageModeShared)
        }
        guard let buf else { return (dummyOrbit, 0, .zero) }

        orbitCache = OrbitCache(center: state.center,
                                scale: state.scale,
                                aspect: aspect,
                                maxIter: state.maxIterations,
                                buffer: buf,
                                length: UInt32(orbit.count),
                                refOffset: refOffset)
        return (buf, UInt32(orbit.count), refOffset)
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        let (orbitBuf, orbitLen, refOffset) = ensureOrbit()

        let cx = splitDouble(state.centerX)
        let cy = splitDouble(state.centerY)
        let s  = splitDouble(state.scale)

        var u = FractalUniforms(
            centerHi: SIMD2<Float>(cx.hi, cy.hi),
            centerLo: SIMD2<Float>(cx.lo, cy.lo),
            scaleHi: s.hi,
            scaleLo: s.lo,
            aspect: aspect,
            maxIterations: state.maxIterations,
            usePerturbation: (state.type == .mandelbrot && state.usePerturbation) ? 1 : 0,
            refOrbitLength: orbitLen,
            refOffset: refOffset,
            fractalType: UInt32(state.type.rawValue),
            palette: UInt32(state.palette.rawValue),
            smooth: state.smooth ? 1 : 0,
            multibrotExponent: state.multibrotExponent,
            newtonFlavor: state.newtonFlavor,
            juliaC: SIMD2<Float>(Float(state.juliaCx), Float(state.juliaCy))
        )

        enc.setRenderPipelineState(pipelineState)
        enc.setFragmentBytes(&u, length: MemoryLayout<FractalUniforms>.stride, index: 0)
        enc.setFragmentBuffer(orbitBuf, offset: 0, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()

        cmd.present(drawable)
        cmd.commit()
    }
}
