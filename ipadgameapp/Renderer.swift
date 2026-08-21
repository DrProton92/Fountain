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
let maxParticleCount = 100_000_000
let defaultParticleCount = 10000
let preferredParticleBufferBudgetBytes = 256 * 1024 * 1024

enum RendererError: Error {
    case pipelineCreationFailed
}

enum ParticleColorStyle: Int, CaseIterable {
    case singleColor
    case rainbow
    case fire
    case pastel
    case neon

    var displayName: String {
        switch self {
        case .singleColor: return "Single Color"
        case .rainbow: return "Rainbow"
        case .fire: return "Fire"
        case .pastel: return "Pastel"
        case .neon: return "Neon"
        }
    }
}

enum ParticleSizeMode: Int, CaseIterable {
    case constant
    case random

    var displayName: String {
        switch self {
        case .constant: return "Constant"
        case .random: return "Random Distribution"
        }
    }
}

enum SizeDistributionPreset: Int, CaseIterable {
    case gaussian
    case skewedLeft
    case skewedRight

    var displayName: String {
        switch self {
        case .gaussian: return "Gaussian (Center)"
        case .skewedLeft: return "Skewed Left"
        case .skewedRight: return "Skewed Right"
        }
    }
}

struct SizeDistribution {
    var controlPoints: [SizeDistributionPoint] = []
    
    init() {
        // Initialize with a uniform distribution
        self.controlPoints = [
            SizeDistributionPoint(x: 0.0, y: 1.0),
            SizeDistributionPoint(x: 1.0, y: 1.0)
        ]
    }
    
    mutating func applyPreset(_ preset: SizeDistributionPreset) {
        switch preset {
        case .gaussian:
            // Bell curve centered
            self.controlPoints = [
                SizeDistributionPoint(x: 0.0, y: 0.0),
                SizeDistributionPoint(x: 0.25, y: 0.5),
                SizeDistributionPoint(x: 0.5, y: 1.0),
                SizeDistributionPoint(x: 0.75, y: 0.5),
                SizeDistributionPoint(x: 1.0, y: 0.0)
            ]
        case .skewedLeft:
            // More weight on the left
            self.controlPoints = [
                SizeDistributionPoint(x: 0.0, y: 1.0),
                SizeDistributionPoint(x: 0.3, y: 0.8),
                SizeDistributionPoint(x: 0.7, y: 0.3),
                SizeDistributionPoint(x: 1.0, y: 0.0)
            ]
        case .skewedRight:
            // More weight on the right
            self.controlPoints = [
                SizeDistributionPoint(x: 0.0, y: 0.0),
                SizeDistributionPoint(x: 0.3, y: 0.3),
                SizeDistributionPoint(x: 0.7, y: 0.8),
                SizeDistributionPoint(x: 1.0, y: 1.0)
            ]
        }
    }
    
    func sampleValue(at normalized: Float) -> Float {
        guard !controlPoints.isEmpty else { return 0.5 }
        guard controlPoints.count > 1 else { return controlPoints[0].y }
        
        let clamped = max(0, min(normalized, 1.0))
        
        // Find the two control points to interpolate between
        var left = controlPoints[0]
        var right = controlPoints[1]
        
        for i in 0..<(controlPoints.count - 1) {
            if controlPoints[i].x <= clamped && clamped <= controlPoints[i + 1].x {
                left = controlPoints[i]
                right = controlPoints[i + 1]
                break
            }
        }
        
        // Linear interpolation
        let range = right.x - left.x
        if range < 0.0001 {
            return left.y
        }
        let t = (clamped - left.x) / range
        return left.y + (right.y - left.y) * t
    }
}

struct SizeDistributionPoint {
    var x: Float // 0.0 to 1.0
    var y: Float // 0.0 to 1.0 (probability/weight)
}

struct ColorSpectrumPoint {
    var x: Float // 0.0 to 1.0
    var y: Float // 0.0 to 1.0 (graph height)
    var color: SIMD4<Float>
}

struct ColorSpectrum {
    var controlPoints: [ColorSpectrumPoint] = []
    var preset: ParticleColorStyle = .singleColor
    var singleColor: SIMD4<Float> = SIMD4<Float>(0.95, 0.95, 0.95, 1.0)

    init() {
        applyPreset(.singleColor)
    }

    init(controlPoints: [ColorSpectrumPoint], preset: ParticleColorStyle) {
        self.controlPoints = controlPoints
        self.preset = preset
        self.singleColor = controlPoints.first?.color ?? self.singleColor
    }

    mutating func applyPreset(_ preset: ParticleColorStyle) {
        self.preset = preset
        func points(from values: [(Float, Float, SIMD4<Float>)]) -> [ColorSpectrumPoint] {
            let raw = values.map { ColorSpectrumPoint(x: $0.0, y: $0.1, color: $0.2) }
            return ColorSpectrum.resample(points: raw, count: 10)
        }

        switch preset {
        case .singleColor:
            let color = singleColor
            controlPoints = ColorSpectrum.resample(points: [
                ColorSpectrumPoint(x: 0.0, y: 0.5, color: color),
                ColorSpectrumPoint(x: 1.0, y: 0.5, color: color)
            ], count: 10)
        case .rainbow:
            controlPoints = points(from: [
                (0.0, 0.5, SIMD4<Float>(0.6, 0.0, 1.0, 1.0)),
                (0.25, 0.7, SIMD4<Float>(0.1, 0.3, 1.0, 1.0)),
                (0.5, 0.9, SIMD4<Float>(0.1, 1.0, 0.25, 1.0)),
                (0.75, 0.7, SIMD4<Float>(1.0, 0.85, 0.1, 1.0)),
                (1.0, 0.5, SIMD4<Float>(1.0, 0.1, 0.1, 1.0))
            ])
        case .fire:
            controlPoints = points(from: [
                (0.0, 0.1, SIMD4<Float>(0.12, 0.0, 0.0, 1.0)),
                (0.3, 0.35, SIMD4<Float>(0.85, 0.05, 0.0, 1.0)),
                (0.6, 0.75, SIMD4<Float>(1.0, 0.35, 0.0, 1.0)),
                (1.0, 1.0, SIMD4<Float>(1.0, 0.95, 0.45, 1.0))
            ])
        case .pastel:
            controlPoints = points(from: [
                (0.0, 0.7, SIMD4<Float>(1.0, 0.75, 0.82, 1.0)),
                (0.33, 0.78, SIMD4<Float>(0.78, 0.92, 1.0, 1.0)),
                (0.66, 0.82, SIMD4<Float>(0.8, 1.0, 0.84, 1.0)),
                (1.0, 0.74, SIMD4<Float>(1.0, 0.9, 0.72, 1.0))
            ])
        case .neon:
            controlPoints = points(from: [
                (0.0, 0.55, SIMD4<Float>(1.0, 0.05, 0.75, 1.0)),
                (0.25, 0.8, SIMD4<Float>(0.2, 1.0, 0.95, 1.0)),
                (0.5, 0.95, SIMD4<Float>(0.85, 1.0, 0.1, 1.0)),
                (0.75, 0.82, SIMD4<Float>(0.15, 0.55, 1.0, 1.0)),
                (1.0, 0.55, SIMD4<Float>(0.95, 0.1, 1.0, 1.0))
            ])
        }
    }

    static func resample(points: [ColorSpectrumPoint], count: Int) -> [ColorSpectrumPoint] {
        guard count > 1, !points.isEmpty else { return points }
        let sorted = points.sorted { $0.x < $1.x }
        return (0..<count).map { i in
            let x = Float(i) / Float(count - 1)
            return ColorSpectrumPoint(x: x,
                                      y: sampleValue(at: x, points: sorted, keyPath: \ColorSpectrumPoint.y),
                                      color: sampleColor(at: x, points: sorted))
        }
    }

    private static func sampleValue(at normalized: Float, points: [ColorSpectrumPoint], keyPath: KeyPath<ColorSpectrumPoint, Float>) -> Float {
        let clamped = max(0, min(normalized, 1.0))
        guard points.count > 1 else { return points.first?[keyPath: keyPath] ?? 0.5 }
        var left = points[0]
        var right = points[1]
        for i in 0..<(points.count - 1) {
            if points[i].x <= clamped && clamped <= points[i + 1].x {
                left = points[i]
                right = points[i + 1]
                break
            }
        }
        let range = right.x - left.x
        if range < 0.0001 { return left[keyPath: keyPath] }
        let t = (clamped - left.x) / range
        return left[keyPath: keyPath] + (right[keyPath: keyPath] - left[keyPath: keyPath]) * t
    }

    private static func sampleColor(at normalized: Float, points: [ColorSpectrumPoint]) -> SIMD4<Float> {
        let clamped = max(0, min(normalized, 1.0))
        guard points.count > 1 else { return points.first?.color ?? SIMD4<Float>(1, 1, 1, 1) }
        var left = points[0]
        var right = points[1]
        for i in 0..<(points.count - 1) {
            if points[i].x <= clamped && clamped <= points[i + 1].x {
                left = points[i]
                right = points[i + 1]
                break
            }
        }
        let range = right.x - left.x
        if range < 0.0001 { return left.color }
        let t = (clamped - left.x) / range
        return left.color + (right.color - left.color) * t
    }

    func sampleColor(at normalized: Float) -> SIMD4<Float> {
        if preset == .singleColor {
            return singleColor
        }
        guard !controlPoints.isEmpty else { return singleColor }
        guard controlPoints.count > 1 else { return controlPoints[0].color }

        let clamped = max(0, min(normalized, 1.0))
        var left = controlPoints[0]
        var right = controlPoints[1]

        for i in 0..<(controlPoints.count - 1) {
            if controlPoints[i].x <= clamped && clamped <= controlPoints[i + 1].x {
                left = controlPoints[i]
                right = controlPoints[i + 1]
                break
            }
        }

        let range = right.x - left.x
        if range < 0.0001 {
            return left.color
        }

        let t = (clamped - left.x) / range
        return left.color + (right.color - left.color) * t
    }
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
    private(set) var maxRenderableParticleCount = defaultParticleCount
    private(set) var activeParticleCount = defaultParticleCount
    private(set) var particleColorStyle: ParticleColorStyle = .rainbow
    private(set) var colorSpectrum: ColorSpectrum = ColorSpectrum()
    
    // Particle size configuration
    private(set) var particleSizeMode: ParticleSizeMode = .constant
    private(set) var constantParticleSize: Float = 5.0
    private(set) var sizeDistribution: SizeDistribution = SizeDistribution()
    private(set) var minSizeRange: Float = 1.0
    private(set) var maxSizeRange: Float = 10.0
    
    var projectionMatrix: matrix_float4x4 = matrix_float4x4()
    var cameraYaw: Float = 0
    var cameraPitch: Float = 0.35
    var cameraDistance: Float = 3.5
    
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
        let particleStride = MemoryLayout<Particle>.stride
        let deviceCapByLength = Int(self.device.maxBufferLength) / particleStride
        let preferredCapByBudget = preferredParticleBufferBudgetBytes / particleStride
        var capacity = min(maxParticleCount, deviceCapByLength, preferredCapByBudget)
        capacity = max(capacity, defaultParticleCount)
        let initialSpectrum = ColorSpectrum()

        var allocatedBuffer: MTLBuffer?
        var allocatedCapacity = capacity
        while allocatedBuffer == nil && allocatedCapacity >= defaultParticleCount {
            allocatedBuffer = self.device.makeBuffer(length: allocatedCapacity * particleStride, options: .storageModeShared)
            if allocatedBuffer == nil {
                allocatedCapacity /= 2
            }
        }

        guard let pBuffer = allocatedBuffer else { return nil }
        self.particleBuffer = pBuffer
        self.maxRenderableParticleCount = allocatedCapacity
        self.activeParticleCount = min(defaultParticleCount, allocatedCapacity)
        
        // Initialize particles using direct property assignment
        let particlesPtr = particleBuffer.contents().bindMemory(to: Particle.self, capacity: maxRenderableParticleCount)
        for i in 0..<maxRenderableParticleCount {
            let angle = Float(i) / 1000.0 * 2.0 * Float.pi
            
            let radial = Float.random(in: 0.008...0.012)
            let upward = Float.random(in: 0.03...0.05)
            particlesPtr[i].position = SIMD3<Float>(0, 0, 0)
            particlesPtr[i].velocity = SIMD3<Float>(cos(angle) * radial, upward, sin(angle) * radial)
            particlesPtr[i].color = Renderer.spectrumColor(for: i, count: maxRenderableParticleCount, spectrum: initialSpectrum)
            particlesPtr[i].life = Float.random(in: 0.1...1.0)
            particlesPtr[i].size = constantParticleSize
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
        frameUniforms.viewMatrix = makeViewMatrix()
        frameUniforms.particleCount = UInt32(activeParticleCount)
        frameUniforms._padding0 = 0
        frameUniforms._padding1 = 0
        frameUniforms._padding2 = 0

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
                width: (activeParticleCount + threadsPerGroup.width - 1) / threadsPerGroup.width,
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
            
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: activeParticleCount)
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        
        commandBuffer.commit()
    }

    func updateCameraRotation(deltaX: Float, deltaY: Float) {
        let sensitivity: Float = 0.01
        cameraYaw += deltaX * sensitivity
        cameraPitch += deltaY * sensitivity
        cameraPitch = min(max(cameraPitch, -1.3), 1.3)
    }

    func updateCameraZoom(scaleFactor: Float) {
        // scaleFactor is the delta scale from the last frame
        // > 1.0 means spreading/zooming in, < 1.0 means pinching/zooming out
        // Apply the scale factor to the distance
        let newDistance = cameraDistance / scaleFactor
        cameraDistance = min(max(newDistance, 1.5), 12.0)
    }

    func setParticleCount(_ count: Int) {
        let clamped = min(max(count, 1), maxRenderableParticleCount)
         activeParticleCount = clamped
         applyColorStyle(in: 0..<activeParticleCount)
         regenerateParticleSizes()  // Assign sizes to new particles
     }

    func setParticleColorStyle(_ style: ParticleColorStyle) {
        guard style != particleColorStyle else { return }
        particleColorStyle = style
        colorSpectrum.applyPreset(style)
        applyColorStyle(in: 0..<activeParticleCount)
     }

    func setColorSpectrum(_ spectrum: ColorSpectrum) {
        colorSpectrum = spectrum
        particleColorStyle = spectrum.preset
        applyColorStyle(in: 0..<activeParticleCount)
    }

    func setSingleColor(_ color: SIMD4<Float>) {
        colorSpectrum.singleColor = color
        if particleColorStyle == .singleColor {
            colorSpectrum.applyPreset(.singleColor)
            applyColorStyle(in: 0..<activeParticleCount)
        }
    }

    func setParticleSizeMode(_ mode: ParticleSizeMode) {
        particleSizeMode = mode
        regenerateParticleSizes()
    }

    func setConstantParticleSize(_ size: Float) {
        let clamped = max(0.5, min(size, 50.0))
        constantParticleSize = clamped
        if particleSizeMode == .constant {
            regenerateParticleSizes()
        }
    }

    func setSizeDistribution(_ distribution: SizeDistribution) {
        sizeDistribution = distribution
        if particleSizeMode == .random {
            regenerateParticleSizes()
        }
    }

    func applySizeDistributionPreset(_ preset: SizeDistributionPreset) {
        sizeDistribution.applyPreset(preset)
        if particleSizeMode == .random {
            regenerateParticleSizes()
        }
    }

    func setSizeRange(_ minValue: Float, _ maxValue: Float) {
        let minClamped = max(0.5, min(minValue, 50.0))
        let maxClamped = max(0.5, min(maxValue, 50.0))
        minSizeRange = min(minClamped, maxClamped)
        maxSizeRange = max(minClamped, maxClamped)
        if particleSizeMode == .random {
            regenerateParticleSizes()
        }
    }

    private func regenerateParticleSizes() {
        let particlesPtr = particleBuffer.contents().bindMemory(to: Particle.self, capacity: maxRenderableParticleCount)
        
        switch particleSizeMode {
        case .constant:
            for i in 0..<activeParticleCount {
                particlesPtr[i].size = constantParticleSize
            }
        case .random:
            let sizeRange = maxSizeRange - minSizeRange
            for i in 0..<activeParticleCount {
                let randomValue = Float.random(in: 0.0...1.0)
                let distributionWeight = sizeDistribution.sampleValue(at: randomValue)
                particlesPtr[i].size = minSizeRange + (sizeRange * distributionWeight)
            }
        }
    }

    private func makeViewMatrix() -> matrix_float4x4 {
        // Orbit the camera around the origin and always look back at the fountain source.
        let target = SIMD3<Float>(0, 0, 0)
        let x = cameraDistance * cos(cameraPitch) * sin(cameraYaw)
        let y = cameraDistance * sin(cameraPitch)
        let z = cameraDistance * cos(cameraPitch) * cos(cameraYaw)
        let eye = SIMD3<Float>(x, y, z)
        return matrix_look_at_right_hand(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))
    }

    private func applyColorStyle(in range: Range<Int>) {
        guard !range.isEmpty else { return }
        let lowerBound = max(0, range.lowerBound)
        let upperBound = min(range.upperBound, maxRenderableParticleCount)
        guard lowerBound < upperBound else { return }

        let particlesPtr = particleBuffer.contents().bindMemory(to: Particle.self, capacity: maxRenderableParticleCount)
        if particleColorStyle == .singleColor {
            let uniformColor = colorSpectrum.singleColor
            for i in lowerBound..<upperBound {
                particlesPtr[i].color = uniformColor
            }
            return
        }

        for i in lowerBound..<upperBound {
            particlesPtr[i].color = Renderer.spectrumColor(for: i, count: maxRenderableParticleCount, spectrum: colorSpectrum)
        }
    }

    private static func spectrumColor(for index: Int, count: Int, spectrum: ColorSpectrum) -> SIMD4<Float> {
        guard count > 1 else { return spectrum.sampleColor(at: 0.5) }
        let normalized = Float(index) / Float(count - 1)
        return spectrum.sampleColor(at: normalized)
    }

    @MainActor
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

func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
    let normalizedAxis = simd_normalize(axis)
    let x = normalizedAxis.x
    let y = normalizedAxis.y
    let z = normalizedAxis.z
    let c = cos(radians)
    let s = sin(radians)
    let mc = 1.0 - c

    return matrix_float4x4(columns: (
        SIMD4<Float>(c + x * x * mc, x * y * mc + z * s, x * z * mc - y * s, 0),
        SIMD4<Float>(y * x * mc - z * s, c + y * y * mc, y * z * mc + x * s, 0),
        SIMD4<Float>(z * x * mc + y * s, z * y * mc - x * s, c + z * z * mc, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ))
}

func matrix_look_at_right_hand(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> matrix_float4x4 {
    let zAxis = simd_normalize(eye - target)
    let xAxis = simd_normalize(simd_cross(up, zAxis))
    let yAxis = simd_cross(zAxis, xAxis)

    let translation = SIMD3<Float>(
        -simd_dot(xAxis, eye),
        -simd_dot(yAxis, eye),
        -simd_dot(zAxis, eye)
    )

    return matrix_float4x4(columns: (
        SIMD4<Float>(xAxis.x, yAxis.x, zAxis.x, 0),
        SIMD4<Float>(xAxis.y, yAxis.y, zAxis.y, 0),
        SIMD4<Float>(xAxis.z, yAxis.z, zAxis.z, 0),
        SIMD4<Float>(translation.x, translation.y, translation.z, 1)
    ))

}

func radians_from_degrees(_ degrees: Float) -> Float {
    return (degrees / 180) * .pi
}
