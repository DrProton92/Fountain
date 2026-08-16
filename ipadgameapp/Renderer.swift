//
//  Renderer.swift
//  ipadgameapp
//
//  Created by Dave Schmid on 8/15/26.
//

import Metal
import MetalKit
import simd

// The size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100
let maxBuffersInFlight = 3
let particleCount = 10000

enum RendererError: Error {
    case pipelineCreationFailed
}

class Renderer: NSObject, MTKViewDelegate {
    
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    // Particle System Resources
    let particleBuffer: MTLBuffer
    let computePipelineState: MTLComputePipelineState
    let renderPipelineState: MTLRenderPipelineState
    
    var dynamicUniformBuffer: MTLBuffer
    let uniformBufferRawPointer: UnsafeMutableRawPointer
    
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    var uniformBufferOffset = 0
    var uniformBufferIndex = 0
    
    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    
    @MainActor
    init?(metalKitView: MTKView) {
        guard let device = metalKitView.device else { return nil }
        self.device = device
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        // 1. Setup Uniform Buffer
        let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
        guard let uBuffer = self.device.makeBuffer(length: uniformBufferSize, options: .storageModeShared) else { return nil }
        self.dynamicUniformBuffer = uBuffer
        self.uniformBufferRawPointer = uBuffer.contents()
        
        // 2. Setup Particle Buffer
        let particleBufferSize = particleCount * MemoryLayout<Particle>.stride
        guard let pBuffer = self.device.makeBuffer(length: particleBufferSize, options: .storageModeShared) else { return nil }
        self.particleBuffer = pBuffer
        
        // Initialize particles using direct property assignment
        let particlesPtr = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
        for i in 0..<particleCount {
            let angle = Float(i) / 1000.0 * 2.0 * Float.pi
            
            particlesPtr[i].position = SIMD2<Float>(0, 0)
            particlesPtr[i].velocity = SIMD2<Float>(cos(angle), sin(angle)) * 0.01
            particlesPtr[i].color = SIMD4<Float>(0.2, 0.6, 1.0, 1.0)
            particlesPtr[i].life = Float.random(in: 0.1...1.0)
        }
        
        // 3. Setup Pipelines
        let library = device.makeDefaultLibrary()
        guard let computeFunc = library?.makeFunction(name: "particle_compute"),
              let vertexFunc = library?.makeFunction(name: "particle_vertex"),
              let fragmentFunc = library?.makeFunction(name: "fragmentShader") else { return nil }
        
        // Compute Pipeline
        guard let cState = try? device.makeComputePipelineState(function: computeFunc) else { return nil }
        self.computePipelineState = cState
        
        // Render Pipeline
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunc
        pipelineDescriptor.fragmentFunction = fragmentFunc
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        
        guard let rState = try? device.makeRenderPipelineState(descriptor: pipelineDescriptor) else { return nil }
        self.renderPipelineState = rState
        
        super.init()
    }
    
    func updateDynamicBufferState() {
        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
        uniformBufferOffset = alignedUniformsSize * uniformBufferIndex
    }
    
    func updateGameState() {
        var frameUniforms = Uniforms()
        frameUniforms.projectionMatrix = projectionMatrix
        frameUniforms.modelViewMatrix = matrix4x4_translation(0, 0, -1)

        // Write one frame's uniforms into the ring-buffer slot.
        let destination = uniformBufferRawPointer.advanced(by: uniformBufferOffset)
        withUnsafeBytes(of: frameUniforms) { rawBytes in
            destination.copyMemory(from: rawBytes.baseAddress!, byteCount: MemoryLayout<Uniforms>.stride)
        }
    }
    
    func draw(in view: MTKView) {
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            return
        }
        
        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }
        
        self.updateDynamicBufferState()
        self.updateGameState()
        
        // --- Step 1: Compute Pass (Update Particles) ---
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(computePipelineState)
            // Buffer index values are defined in ShaderTypes.h as integer constants.
            // Use the integer indices directly to avoid C enum name-mapping issues.
            computeEncoder.setBuffer(particleBuffer, offset: 0, index: 0) // BufferIndexParticles
            computeEncoder.setBuffer(dynamicUniformBuffer, offset: uniformBufferOffset, index: 1) // BufferIndexUniforms
            
            let threadsPerGroup = MTLSize(width: 64, height: 1, depth: 1)
            let threadgroups = MTLSize(
                width: (particleCount + threadsPerGroup.width - 1) / threadsPerGroup.width,
                height: 1,
                depth: 1
            )
            computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerGroup)
            computeEncoder.endEncoding()
        }
        
        // --- Step 2: Render Pass (Draw Particles) ---
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            commandBuffer.commit()
            return
        }
            
            renderEncoder.setRenderPipelineState(renderPipelineState)
            renderEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset: uniformBufferOffset, index: 1) // BufferIndexUniforms
            
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        
        commandBuffer.commit()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard size.height > 0 else { return }
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(
            fovyRadians: radians_from_degrees(65),
            aspectRatio: aspect,
            nearZ: 0.1,
            farZ: 100.0
        )
    }
}

// Matrix math utilities
func matrix4x4_translation(_ translationX: Float, _ translationY: Float, _ translationZ: Float) -> matrix_float4x4 {
    return matrix_float4x4.init(columns:(vector_float4(1, 0, 0, 0),
                                         vector_float4(0, 1, 0, 0),
                                         vector_float4(0, 0, 1, 0),
                                         vector_float4(translationX, translationY, translationZ, 1)))
}

func matrix_perspective_right_hand(fovyRadians fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovy * 0.5)
    let xs = ys / aspectRatio
    let zs = farZ / (nearZ - farZ)
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, ys, 0,   0),
                                         vector_float4( 0,  0, zs, -1),
                                         vector_float4( 0,  0, zs * nearZ, 0)))
}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}
