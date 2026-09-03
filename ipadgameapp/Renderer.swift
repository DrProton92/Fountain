import Metal
import MetalKit
import QuartzCore
import simd

class Renderer: NSObject, MTKViewDelegate {
    
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    // Particle System Resources
    let particleBuffer: MTLBuffer
    let computePipelineState: MTLComputePipelineState
    let renderPipelineState: MTLRenderPipelineState
    let axisRenderPipelineState: MTLRenderPipelineState
    
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
    private(set) var sizeDistributionPreset: SizeDistributionPreset = .flat
    private(set) var sizeSpectrumVariancePercent: Float = 50.0
    private(set) var minSizeRange: Float = 5.0
    private(set) var maxSizeRange: Float = 30.0

    // Particle velocity configuration
    private(set) var particleVelocityMode: ParticleSizeMode = .random
    private(set) var constantParticleVelocity: Float = 0.04
    private(set) var velocityDistribution: SizeDistribution = SizeDistribution()
    private(set) var velocityDistributionPreset: SizeDistributionPreset = .gaussian
    private(set) var velocitySpectrumVariancePercent: Float = 50.0
    private(set) var minVelocityRange: Float = 0.02
    private(set) var maxVelocityRange: Float = 0.08

    // Launch configuration
    private(set) var launchAngleDegrees: Float = 0.0
    private(set) var angleVarianceDegrees: Float = 12.0
    private(set) var velocityVariancePercent: Float = 0.0
    private(set) var showAxis: Bool = false

    // Trail rendering configuration
    private(set) var trailsEnabled: Bool = false
    private(set) var trailLength: Float = 2.0
    private var trailHistoryBuffer: MTLBuffer?
    private var trailHistoryCapacity: Int = 0
    private let fallbackTrailHistoryBuffer: MTLBuffer

    // Camera motion configuration
    private(set) var cameraControlMode: CameraControlMode = .touchControlled
    private(set) var cameraMotionModel: CameraMotionModel = .orbit
    private(set) var cameraInclinationDegrees: Float = 22.0
    private var cameraMotionStartTime: CFTimeInterval = CACurrentMediaTime()
    
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
        let fallbackTrailLength = max(1, MemoryLayout<SIMD3<Float>>.stride)
        guard let fallbackTrailBuffer = self.device.makeBuffer(length: fallbackTrailLength, options: .storageModeShared) else { return nil }
        self.fallbackTrailHistoryBuffer = fallbackTrailBuffer
        
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
        var initialSpectrum = ColorSpectrum()
        initialSpectrum.applyPreset(particleColorStyle)
        self.colorSpectrum = initialSpectrum

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

        var initialSizeDistribution = SizeDistribution()
        initialSizeDistribution.applyPreset(sizeDistributionPreset, variancePercent: sizeSpectrumVariancePercent)
        self.sizeDistribution = initialSizeDistribution

        var initialVelocityDistribution = SizeDistribution()
        initialVelocityDistribution.applyPreset(velocityDistributionPreset, variancePercent: velocitySpectrumVariancePercent)
        self.velocityDistribution = initialVelocityDistribution
        
        // Initialize active particles without using self methods before super.init.
        let particlesPtr = particleBuffer.contents().bindMemory(to: Particle.self, capacity: maxRenderableParticleCount)
        for i in 0..<activeParticleCount {
            particlesPtr[i].position = SIMD3<Float>(0, 0, 0)
            let baseSpeed = Renderer.launchSpeedForParticle(
                at: i,
                mode: particleVelocityMode,
                constantVelocity: constantParticleVelocity,
                minVelocityRange: minVelocityRange,
                maxVelocityRange: maxVelocityRange,
                distribution: initialVelocityDistribution
            )
            particlesPtr[i].velocity = Renderer.launchVelocity(for: i,
                                                               launchAngleDegrees: launchAngleDegrees,
                                                               angleVarianceDegrees: angleVarianceDegrees,
                                                               velocityVariancePercent: velocityVariancePercent,
                                                               speed: baseSpeed)
            particlesPtr[i].color = Renderer.spectrumColor(for: i,
                                                           count: maxRenderableParticleCount,
                                                           spectrum: initialSpectrum)
            particlesPtr[i].life = Float.random(in: 0.1...1.0)
            particlesPtr[i].size = constantParticleSize
        }

        // 3. Setup Pipelines
        let library = device.makeDefaultLibrary()
        guard let computeFunc = library?.makeFunction(name: "particle_compute"),
              let vertexFunc = library?.makeFunction(name: "particle_vertex"),
              let fragmentFunc = library?.makeFunction(name: "fragmentShader"),
              let axisVertexFunc = library?.makeFunction(name: "axis_vertex"),
              let axisFragmentFunc = library?.makeFunction(name: "axis_fragment") else { return nil }
        
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

        // Axis Render Pipeline
        let axisPipelineDescriptor = MTLRenderPipelineDescriptor()
        axisPipelineDescriptor.vertexFunction = axisVertexFunc
        axisPipelineDescriptor.fragmentFunction = axisFragmentFunc
        axisPipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        
        guard let axisRState = try? device.makeRenderPipelineState(descriptor: axisPipelineDescriptor) else { return nil }
        self.axisRenderPipelineState = axisRState

        super.init()
        regenerateParticleLaunchVelocities()
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
        frameUniforms.launchAngleRadians = radians_from_degrees(launchAngleDegrees)
        frameUniforms.angleVarianceRadians = radians_from_degrees(angleVarianceDegrees)
        frameUniforms.launchSpeed = constantParticleVelocity
        frameUniforms.velocityVariance = max(0.0, min(velocityVariancePercent, 100.0)) / 100.0
        let requestedTrailSamples = Int(round(max(1.0, min(trailLength, Float(maxTrailHistorySamples)))))
        let hasTrailHistory = trailHistoryBuffer != nil && trailHistoryCapacity >= activeParticleCount
        let effectiveTrailsEnabled = trailsEnabled && hasTrailHistory
        frameUniforms.trailsEnabled = effectiveTrailsEnabled ? 1 : 0
        frameUniforms.trailSampleCount = UInt32(effectiveTrailsEnabled ? requestedTrailSamples : 0)
        frameUniforms.velocityMode = UInt32(particleVelocityMode.rawValue)
        frameUniforms.minVelocityRange = minVelocityRange
        frameUniforms.maxVelocityRange = maxVelocityRange
        let velocityWeights = resampledWeights(from: velocityDistribution)
        frameUniforms.velocityWeight0 = velocityWeights[0]
        frameUniforms.velocityWeight1 = velocityWeights[1]
        frameUniforms.velocityWeight2 = velocityWeights[2]
        frameUniforms.velocityWeight3 = velocityWeights[3]
        frameUniforms.velocityWeight4 = velocityWeights[4]
        frameUniforms.velocityWeight5 = velocityWeights[5]
        frameUniforms.velocityWeight6 = velocityWeights[6]
        frameUniforms.velocityWeight7 = velocityWeights[7]
        frameUniforms.velocityWeight8 = velocityWeights[8]
        frameUniforms.velocityWeight9 = velocityWeights[9]
        frameUniforms.showAxis = showAxis ? 1 : 0

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
        
        // --- Step 1: Compute Pass ---
        if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
            computeEncoder.setComputePipelineState(computePipelineState)
            computeEncoder.setBuffer(particleBuffer, offset: 0, index: 0)
            computeEncoder.setBuffer(dynamicUniformBuffer, offset: uniformBufferOffset, index: 1)
            computeEncoder.setBuffer(trailHistoryBuffer ?? fallbackTrailHistoryBuffer, offset: 0, index: 2)
            
            let threadsPerThreadgroup = MTLSize(width: 64, height: 1, depth: 1)
            let threadgroups = MTLSize(
                width: (activeParticleCount + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
                height: 1,
                depth: 1
            )
            computeEncoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
            computeEncoder.endEncoding()
        }
        
        // --- Step 2: Render Pass ---
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            commandBuffer.commit()
            return
        }
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        // Draw Particles
        renderEncoder.setRenderPipelineState(renderPipelineState)
        renderEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset: uniformBufferOffset, index: 1)
        renderEncoder.setVertexBuffer(trailHistoryBuffer ?? fallbackTrailHistoryBuffer, offset: 0, index: 2)
        
        let trailSamples = (trailsEnabled && trailHistoryBuffer != nil && trailHistoryCapacity >= activeParticleCount)
            ? Int(round(max(1.0, min(trailLength, Float(maxTrailHistorySamples)))))
            : 0
        let vertexCount = activeParticleCount * (trailSamples + 1)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: vertexCount)

        // Draw Axes
        if showAxis {
            renderEncoder.setRenderPipelineState(axisRenderPipelineState)
            renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset: uniformBufferOffset, index: 1)
            renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 6)
        }
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func updateCameraRotation(deltaX: Float, deltaY: Float) {
        guard cameraControlMode == .touchControlled else { return }
        let sensitivity: Float = 0.01
        cameraYaw += deltaX * sensitivity
        cameraPitch += deltaY * sensitivity
        cameraPitch = min(max(cameraPitch, -1.3), 1.3)
    }

    func updateCameraZoom(scaleFactor: Float) {
        guard cameraControlMode == .touchControlled else { return }
        let newDistance = cameraDistance / scaleFactor
        cameraDistance = min(max(newDistance, 1.5), 12.0)
    }

    func setCameraControlMode(_ mode: CameraControlMode) {
        cameraControlMode = mode
        if mode == .motionModel {
            cameraMotionStartTime = CACurrentMediaTime()
        }
    }

    func setCameraMotionModel(_ model: CameraMotionModel) {
        cameraMotionModel = model
        cameraMotionStartTime = CACurrentMediaTime()
    }

    func setCameraInclination(_ degrees: Float) {
        cameraInclinationDegrees = max(0.0, min(degrees, 85.0))
    }

    func setParticleVelocityMode(_ mode: ParticleSizeMode) {
        particleVelocityMode = mode
        regenerateParticleLaunchVelocities()
    }

    func setConstantParticleVelocity(_ velocity: Float) {
        constantParticleVelocity = max(0.005, min(velocity, 0.20))
        if particleVelocityMode == .constant {
            regenerateParticleLaunchVelocities()
        }
    }

    func setVelocityRange(_ minValue: Float, _ maxValue: Float) {
        let minClamped = max(0.005, min(minValue, 0.20))
        let maxClamped = max(0.005, min(maxValue, 0.20))
        minVelocityRange = min(minClamped, maxClamped)
        maxVelocityRange = max(minClamped, maxClamped)
        if particleVelocityMode == .random {
            regenerateParticleLaunchVelocities()
        }
    }

    func setVelocityDistribution(_ distribution: SizeDistribution) {
        velocityDistribution = distribution
        if particleVelocityMode == .random {
            regenerateParticleLaunchVelocities()
        }
    }

    func applyVelocityDistributionPreset(_ preset: SizeDistributionPreset) {
        velocityDistributionPreset = preset
        velocityDistribution.applyPreset(preset, variancePercent: velocitySpectrumVariancePercent)
        if particleVelocityMode == .random {
            regenerateParticleLaunchVelocities()
        }
    }

    func setVelocityDistributionPreset(_ preset: SizeDistributionPreset) {
        velocityDistributionPreset = preset
    }

    func setVelocitySpectrumVariance(_ percent: Float) {
        velocitySpectrumVariancePercent = max(0.0, min(percent, 100.0))
        velocityDistribution.applyPreset(velocityDistributionPreset, variancePercent: velocitySpectrumVariancePercent)
        if particleVelocityMode == .random {
            regenerateParticleLaunchVelocities()
        }
    }

    func setParticleCount(_ count: Int) {
        let previousCount = activeParticleCount
        let clamped = min(max(count, 1), maxRenderableParticleCount)
         if clamped > previousCount {
             initializeParticles(in: previousCount..<clamped)
         }
         activeParticleCount = clamped
         if trailsEnabled && !ensureTrailHistoryCapacity(requiredCount: activeParticleCount) {
             trailsEnabled = false
         }
         applyColorStyle(in: 0..<activeParticleCount)
         regenerateParticleSizes()
         regenerateParticleLaunchVelocities()
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
        let clamped = max(0.5, min(size, 30.0))
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
        sizeDistributionPreset = preset
        sizeDistribution.applyPreset(preset, variancePercent: sizeSpectrumVariancePercent)
        if particleSizeMode == .random {
            regenerateParticleSizes()
        }
    }

    func setSizeDistributionPreset(_ preset: SizeDistributionPreset) {
        sizeDistributionPreset = preset
    }

    func setSizeSpectrumVariance(_ percent: Float) {
        sizeSpectrumVariancePercent = max(0.0, min(percent, 100.0))
        sizeDistribution.applyPreset(sizeDistributionPreset, variancePercent: sizeSpectrumVariancePercent)
        if particleSizeMode == .random {
            regenerateParticleSizes()
        }
    }

    func setSizeRange(_ minValue: Float, _ maxValue: Float) {
        let minClamped = max(0.5, min(minValue, 50.0))
        let maxClamped = max(0.0, min(maxValue, 50.0))
        minSizeRange = min(minClamped, maxClamped)
        maxSizeRange = max(minClamped, maxClamped)
        if particleSizeMode == .random {
            regenerateParticleSizes()
        }
    }

    func setLaunchAngle(_ degrees: Float) {
        launchAngleDegrees = max(0.0, min(degrees, 90.0))
        regenerateParticleLaunchVelocities()
    }

    func setAngleVariance(_ degrees: Float) {
        angleVarianceDegrees = max(0.0, min(degrees, 90.0))
        regenerateParticleLaunchVelocities()
    }

    func setVelocityVariance(_ percent: Float) {
        velocityVariancePercent = max(0.0, min(percent, 100.0))
        regenerateParticleLaunchVelocities()
    }

    func setTrailsEnabled(_ enabled: Bool) {
        if enabled {
            if !ensureTrailHistoryCapacity(requiredCount: activeParticleCount) {
                trailsEnabled = false
            } else {
                trailsEnabled = true
            }
        } else {
            trailsEnabled = false
        }
    }

    func setTrailLength(_ length: Float) {
        trailLength = max(1.0, min(length, Float(maxTrailHistorySamples)))
    }

    func setShowAxis(_ enabled: Bool) {
        showAxis = enabled
    }

    private func ensureTrailHistoryCapacity(requiredCount: Int) -> Bool {
        guard requiredCount > 0 else { return true }
        if let _ = trailHistoryBuffer, trailHistoryCapacity >= requiredCount {
            return true
        }

        let stride = MemoryLayout<SIMD3<Float>>.stride
        let requiredLength = requiredCount * maxTrailHistorySamples * stride
        guard let buffer = device.makeBuffer(length: requiredLength, options: .storageModeShared) else {
            return false
        }

        let trailPtr = buffer.contents().bindMemory(to: SIMD3<Float>.self,
                                                    capacity: requiredCount * maxTrailHistorySamples)
        let particlePtr = particleBuffer.contents().bindMemory(to: Particle.self, capacity: maxRenderableParticleCount)
        for particleIndex in 0..<requiredCount {
            let base = particleIndex * maxTrailHistorySamples
            let position = particlePtr[particleIndex].position
            for sample in 0..<maxTrailHistorySamples {
                trailPtr[base + sample] = position
            }
        }

        trailHistoryBuffer = buffer
        trailHistoryCapacity = requiredCount
        return true
    }

    private func regenerateParticleLaunchVelocities() {
        let particlesPtr = particleBuffer.contents().bindMemory(to: Particle.self, capacity: maxRenderableParticleCount)
        for i in 0..<activeParticleCount {
            let baseSpeed = Renderer.launchSpeedForParticle(
                at: i,
                mode: particleVelocityMode,
                constantVelocity: constantParticleVelocity,
                minVelocityRange: minVelocityRange,
                maxVelocityRange: maxVelocityRange,
                distribution: velocityDistribution
            )
            particlesPtr[i].velocity = Renderer.launchVelocity(for: i,
                                                               launchAngleDegrees: launchAngleDegrees,
                                                               angleVarianceDegrees: angleVarianceDegrees,
                                                               velocityVariancePercent: velocityVariancePercent,
                                                               speed: baseSpeed)
        }
    }

    private func launchSpeedForParticle(at index: Int) -> Float {
        Renderer.launchSpeedForParticle(
            at: index,
            mode: particleVelocityMode,
            constantVelocity: constantParticleVelocity,
            minVelocityRange: minVelocityRange,
            maxVelocityRange: maxVelocityRange,
            distribution: velocityDistribution
        )
    }

    private func initializeParticles(in range: Range<Int>,
                                     spectrum: ColorSpectrum? = nil,
                                     velocityDistribution: SizeDistribution? = nil) {
        guard !range.isEmpty else { return }
        let lower = max(0, range.lowerBound)
        let upper = min(range.upperBound, maxRenderableParticleCount)
        guard lower < upper else { return }

        let particlesPtr = particleBuffer.contents().bindMemory(to: Particle.self, capacity: maxRenderableParticleCount)
        let colorSource = spectrum ?? colorSpectrum
        let velocitySource = velocityDistribution ?? self.velocityDistribution

        for i in lower..<upper {
            particlesPtr[i].position = SIMD3<Float>(0, 0, 0)
            let baseSpeed = Renderer.launchSpeedForParticle(
                at: i,
                mode: particleVelocityMode,
                constantVelocity: constantParticleVelocity,
                minVelocityRange: minVelocityRange,
                maxVelocityRange: maxVelocityRange,
                distribution: velocitySource
            )
            particlesPtr[i].velocity = Renderer.launchVelocity(for: i,
                                                               launchAngleDegrees: launchAngleDegrees,
                                                               angleVarianceDegrees: angleVarianceDegrees,
                                                               velocityVariancePercent: velocityVariancePercent,
                                                               speed: baseSpeed)
            particlesPtr[i].color = Renderer.spectrumColor(for: i,
                                                           count: maxRenderableParticleCount,
                                                           spectrum: colorSource)
            particlesPtr[i].life = Float.random(in: 0.1...1.0)
            particlesPtr[i].size = constantParticleSize
        }
    }

    private static func launchSpeedForParticle(at index: Int,
                                               mode: ParticleSizeMode,
                constantVelocity: Float,
                minVelocityRange: Float,
                maxVelocityRange: Float,
                distribution: SizeDistribution) -> Float {
        switch mode {
        case .constant:
            return constantVelocity
        case .random:
            let randomValue = Renderer.stableUnitRandom(for: index &* 2654435761)
            let weights = SizeDistribution.resample(points: distribution.controlPoints, count: 10)
                .map { max(0.0, min($0.y, 1.0)) }
            let normalized = Renderer.weightedPositionFromUniformWeights(for: randomValue, weights: weights)
            return minVelocityRange + ((maxVelocityRange - minVelocityRange) * normalized)
        }
    }

    private static func weightedPositionFromUniformWeights(for unitRandom: Float, weights: [Float]) -> Float {
        guard weights.count >= 2 else { return max(0, min(unitRandom, 1.0)) }

        let epsilon: Float = 0.000001
        let clampedRandom = max(0, min(unitRandom, 1.0))
        let dx: Float = 1.0 / Float(weights.count - 1)

        var segmentAreas: [Float] = []
        segmentAreas.reserveCapacity(weights.count - 1)
        var totalArea: Float = 0

        for i in 0..<(weights.count - 1) {
            let w0 = max(0, weights[i])
            let w1 = max(0, weights[i + 1])
            let area = 0.5 * (w0 + w1) * dx
            segmentAreas.append(area)
            totalArea += area
        }

        guard totalArea > epsilon else { return clampedRandom }

        let targetArea = clampedRandom * totalArea
        var accumulated: Float = 0

        for i in 0..<(weights.count - 1) {
            let segmentArea = segmentAreas[i]
            if segmentArea <= epsilon { continue }

            let nextAccumulated = accumulated + segmentArea
            if targetArea <= nextAccumulated || i == weights.count - 2 {
                let w0 = max(0, weights[i])
                let w1 = max(0, weights[i + 1])
                let dw = w1 - w0
                let localArea = max(0, targetArea - accumulated)

                let t: Float
                if abs(dw) <= epsilon {
                    let denom = max(epsilon, w0 * dx)
                    t = max(0, min(localArea / denom, 1.0))
                } else {
                    let a = 0.5 * dw * dx
                    let b = w0 * dx
                    let c = -localArea
                    let discriminant = max(0.0, (b * b) - (4 * a * c))
                    let sqrtDiscriminant = sqrt(discriminant)
                    let t1 = (-b + sqrtDiscriminant) / (2 * a)
                    let t2 = (-b - sqrtDiscriminant) / (2 * a)
                    if (0.0...1.0).contains(t1) {
                        t = t1
                    } else if (0.0...1.0).contains(t2) {
                        t = t2
                    } else {
                        t = max(0, min(t1, 1.0))
                    }
                }

                return (Float(i) + t) / Float(weights.count - 1)
            }

            accumulated = nextAccumulated
        }

        return 1.0
    }

    private func resampledWeights(from distribution: SizeDistribution) -> [Float] {
        let points = SizeDistribution.resample(points: distribution.controlPoints, count: 10)
        var weights = points.map { max(0.0, min($0.y, 1.0)) }
        if weights.count < 10 {
            let fill = weights.last ?? 1.0
            weights.append(contentsOf: repeatElement(fill, count: 10 - weights.count))
        } else if weights.count > 10 {
            weights = Array(weights.prefix(10))
        }
        return weights
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
                let randomValue = Renderer.stableUnitRandom(for: i)
                let normalizedSize = Renderer.weightedSizePosition(for: randomValue, distribution: sizeDistribution)
                particlesPtr[i].size = minSizeRange + (sizeRange * normalizedSize)
            }
        }
    }

    private static func weightedSizePosition(for unitRandom: Float, distribution: SizeDistribution) -> Float {
        let points = distribution.controlPoints.sorted { $0.x < $1.x }
        guard points.count > 1 else { return max(0, min(unitRandom, 1.0)) }

        let epsilon: Float = 0.000001
        let clampedRandom = max(0, min(unitRandom, 1.0))

        var segmentAreas: [Float] = []
        segmentAreas.reserveCapacity(points.count - 1)
        var totalArea: Float = 0

        for i in 0..<(points.count - 1) {
            let x0 = points[i].x
            let x1 = points[i + 1].x
            let dx = max(0, x1 - x0)
            let w0 = max(0, points[i].y)
            let w1 = max(0, points[i + 1].y)
            let area = 0.5 * (w0 + w1) * dx
            segmentAreas.append(area)
            totalArea += area
        }

        guard totalArea > epsilon else { return clampedRandom }

        let targetArea = clampedRandom * totalArea
        var accumulated: Float = 0

        for i in 0..<(points.count - 1) {
            if segmentAreas[i] <= epsilon {
                continue
            }

            let nextAccumulated = accumulated + segmentAreas[i]
            if targetArea <= nextAccumulated || i == points.count - 2 {
                let x0 = points[i].x
                let x1 = points[i + 1].x
                let dx = max(epsilon, x1 - x0)
                let w0 = max(0, points[i].y)
                let w1 = max(0, points[i + 1].y)
                let dw = w1 - w0
                let localArea = max(0, targetArea - accumulated)

                let t: Float
                if abs(dw) <= epsilon {
                    let denom = max(epsilon, w0 * dx)
                    t = max(0, min(localArea / denom, 1.0))
                } else {
                    let a = 0.5 * dw * dx
                    let b = w0 * dx
                    let c = -localArea
                    let discriminant = max(0.0, (b * b) - (4 * a * c))
                    let sqrtDiscriminant = sqrt(discriminant)
                    let t1 = (-b + sqrtDiscriminant) / (2 * a)
                    let t2 = (-b - sqrtDiscriminant) / (2 * a)
                    if (0.0...1.0).contains(t1) {
                        t = t1
                    } else if (0.0...1.0).contains(t2) {
                        t = t2
                    } else {
                        t = max(0, min(t1, 1.0))
                    }
                }

                return x0 + ((x1 - x0) * t)
            }

            accumulated = nextAccumulated
        }

        return points.last?.x ?? 1.0
    }

    private static func stableUnitRandom(for index: Int) -> Float {
        var x = UInt32(bitPattern: Int32(truncatingIfNeeded: index))
        x ^= x >> 16
        x = x &* 0x7feb_352d
        x ^= x >> 15
        x = x &* 0x846c_a68b
        x ^= x >> 16
        return Float(x) / Float(UInt32.max)
    }

    private static func launchVelocity(for index: Int,
                                       launchAngleDegrees: Float,
                                       angleVarianceDegrees: Float,
                                       velocityVariancePercent: Float,
                                       speed: Float) -> SIMD3<Float> {
        let launchRadians = radians_from_degrees(max(0.0, min(launchAngleDegrees, 90.0)))
        let coneHalfRadians = radians_from_degrees(max(0.0, min(angleVarianceDegrees, 90.0))) * 0.5
        let velocityVariance = max(0.0, min(velocityVariancePercent, 100.0)) / 100.0

        let axis = simd_normalize(SIMD3<Float>(sin(launchRadians), cos(launchRadians), 0))
        let u = stableUnitRandom(for: index &* 1664525 &+ 1013904223)
        let v = stableUnitRandom(for: index &* 22695477 &+ 1)
        let w = stableUnitRandom(for: index &* 1103515245 &+ 12345)

        let cosAlpha = ((1 - u) * cos(coneHalfRadians)) + u
        let sinAlpha = sqrt(max(0.0, 1 - (cosAlpha * cosAlpha)))
        let phi = 2 * Float.pi * v

        let helper = abs(axis.y) < 0.99 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
        let tangent = simd_normalize(simd_cross(helper, axis))
        let bitangent = simd_cross(axis, tangent)
        let direction = simd_normalize(axis * cosAlpha + tangent * (cos(phi) * sinAlpha) + bitangent * (sin(phi) * sinAlpha))

        let speedScale = (1 - velocityVariance) + velocityVariance * (1 + ((2 * w) - 1))
        return direction * (speed * max(0.0, speedScale))
    }

    private func makeViewMatrix() -> matrix_float4x4 {
        let target = SIMD3<Float>(0, 0, 0)
        let eye: SIMD3<Float>

        switch cameraControlMode {
        case .touchControlled:
            let x = cameraDistance * cos(cameraPitch) * sin(cameraYaw)
            let y = cameraDistance * sin(cameraPitch)
            let z = cameraDistance * cos(cameraPitch) * cos(cameraYaw)
            eye = SIMD3<Float>(x, y, z)
        case .motionModel:
            let elapsed = Float(CACurrentMediaTime() - cameraMotionStartTime)
            let radius = max(1.0, cameraDistance)
            let inclination = radians_from_degrees(max(0.0, min(cameraInclinationDegrees, 85.0)))
            switch cameraMotionModel {
            case .orbit:
                let angle = elapsed * 0.45
                eye = SIMD3<Float>(
                    radius * sin(angle),
                    radius * cos(angle) * sin(inclination),
                    radius * cos(angle) * cos(inclination)
                )
            case .figureEight:
                let angle = elapsed * 0.55
                let radius_ee = max(0.05, radius * cos(inclination))
                let baseY_ee = radius * sin(inclination)
                eye = SIMD3<Float>(
                    radius_ee * sin(2 * angle),
                    baseY_ee + (0.10 * radius_ee * cos(angle)),
                    0.5 * radius_ee * sin(2 * angle)
                )
            }
        }

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

        let visibleCount = upperBound - lowerBound
        for offset in 0..<visibleCount {
            let i = lowerBound + offset
            particlesPtr[i].color = Renderer.weightedSpectrumColor(for: offset, count: visibleCount, spectrum: colorSpectrum)
        }
    }

    private static func spectrumColor(for index: Int, count: Int, spectrum: ColorSpectrum) -> SIMD4<Float> {
        guard count > 1 else { return spectrum.sampleColor(at: 0.5) }
        let normalized = Float(index) / Float(count - 1)
        return spectrum.sampleColor(at: normalized)
    }

    private static func weightedSpectrumColor(for index: Int, count: Int, spectrum: ColorSpectrum) -> SIMD4<Float> {
        guard count > 1 else { return spectrum.controlPoints.first?.color ?? spectrum.sampleColor(at: 0.5) }
        let points = spectrum.controlPoints
        guard !points.isEmpty else { return spectrum.sampleColor(at: 0.5) }

        let weights = points.map { max(0, $0.y) }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0.000001 else {
            return spectrum.sampleColor(at: Float(index) / Float(count - 1))
        }

        let quantile = Float(index) / Float(count - 1)
        let target = quantile * totalWeight
        var cumulative: Float = 0

        for i in 0..<points.count {
            cumulative += weights[i]
            if target <= cumulative || i == points.count - 1 {
                return points[i].color
            }
        }

        return points.last?.color ?? spectrum.sampleColor(at: 1)
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
