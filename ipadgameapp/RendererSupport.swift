import simd

// The size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 0xFF) & -0x100
let maxBuffersInFlight = 3
let maxParticleCount = 100_000_000
let defaultParticleCount = 10000
let preferredParticleBufferBudgetBytes = 256 * 1024 * 1024
let maxTrailHistorySamples = 8

enum RendererError: Error {
    case pipelineCreationFailed
}

enum ParticleColorStyle: Int, CaseIterable {
    case singleColor
    case rainbow
    case fire
    case reddish
    case bluish
    case greenField
    case neonNight

    var displayName: String {
        switch self {
        case .singleColor: return "Single Color"
        case .rainbow: return "Rainbow"
        case .fire: return "Fire"
        case .reddish: return "Red-ish"
        case .bluish: return "Blue-ish"
        case .greenField: return "Green-ish"
        case .neonNight: return "Neon Night"
        }
    }
}

enum ParticleSizeMode: Int, CaseIterable {
    case constant
    case random

    var displayName: String {
        switch self {
        case .constant: return "Single Value"
        case .random: return "Spectrum"
        }
    }
}

enum CameraControlMode: Int, CaseIterable {
    case touchControlled
    case motionModel

    var displayName: String {
        switch self {
        case .touchControlled: return "Touch Controlled"
        case .motionModel: return "Motion Model"
        }
    }
}

enum CameraMotionModel: Int, CaseIterable {
    case orbit
    case figureEight

    var displayName: String {
        switch self {
        case .orbit: return "Orbit"
        case .figureEight: return "Figure Eight"
        }
    }
}

enum SizeDistributionPreset: Int, CaseIterable {
    case gaussian
    case skewedLeft
    case skewedRight
    case flat
    case bigAndSmall

    var displayName: String {
        switch self {
        case .gaussian: return "Gaussian"
        case .skewedLeft: return "Smallish"
        case .skewedRight: return "Largish"
        case .flat: return "Flat"
        case .bigAndSmall: return "Big&Small"
        }
    }
}

struct SizeDistribution {
    var controlPoints: [SizeDistributionPoint] = []
    private let presetPointCount = 10
    
    init() {
        self.controlPoints = [
            SizeDistributionPoint(x: 0.0, y: 1.0),
            SizeDistributionPoint(x: 1.0, y: 1.0)
        ]
    }
    
    mutating func applyPreset(_ preset: SizeDistributionPreset, variancePercent: Float = 50.0) {
        func points(from values: [(Float, Float)]) -> [SizeDistributionPoint] {
            let raw = values.map { SizeDistributionPoint(x: $0.0, y: max(0, min($0.1, 1.0))) }
            return SizeDistribution.resample(points: raw, count: presetPointCount)
        }

        let normalizedVariance = max(0.0, min(variancePercent, 100.0)) / 100.0
        let varianceBias = (normalizedVariance - 0.5) * 2.0
        let peakExponent = varianceBias >= 0
            ? (1.0 + (varianceBias * 2.0))
            : (1.0 + (varianceBias * 0.6))

        func remapForVariance(_ x: Float) -> Float {
            let centered = max(-1.0, min((x * 2.0) - 1.0, 1.0))
            let magnitude = pow(abs(centered), peakExponent)
            let signed = centered < 0 ? -magnitude : magnitude
            return max(0.0, min(0.5 + (0.5 * signed), 1.0))
        }

        func withVariance(_ values: [(Float, Float)]) -> [(Float, Float)] {
            values
                .map { (x, y) in
                    (remapForVariance(x), y)
                }
                .sorted { $0.0 < $1.0 }
        }

        switch preset {
        case .gaussian:
            self.controlPoints = points(from: withVariance([
                (0.0, 0.0),
                (0.12, 0.06),
                (0.25, 0.28),
                (0.40, 0.78),
                (0.50, 1.0),
                (0.60, 0.78),
                (0.75, 0.28),
                (0.88, 0.06),
                (1.0, 0.0)
            ]))
        case .skewedLeft:
            self.controlPoints = points(from: withVariance([
                (0.0, 1.0),
                (0.3, 0.8),
                (0.7, 0.3),
                (1.0, 0.0)
            ]))
        case .skewedRight:
            self.controlPoints = points(from: withVariance([
                (0.0, 0.0),
                (0.3, 0.3),
                (0.7, 0.8),
                (1.0, 1.0)
            ]))
        case .flat:
            self.controlPoints = points(from: [
                (0.0, 1.0),
                (1.0, 1.0)
            ])
        case .bigAndSmall:
            self.controlPoints = points(from: withVariance([
                (0.0, 1.0),
                (0.1, 0.0),
                (0.9, 0.0),
                (1.0, 1.0)
            ]))
        }
    }

    static func resample(points: [SizeDistributionPoint], count: Int) -> [SizeDistributionPoint] {
        guard count > 1, !points.isEmpty else { return points }
        let sorted = points.sorted { $0.x < $1.x }
        return (0..<count).map { i in
            let x = Float(i) / Float(count - 1)
            let y = sampleValue(at: x, points: sorted)
            return SizeDistributionPoint(x: x, y: y)
        }
    }

    private static func sampleValue(at normalized: Float, points: [SizeDistributionPoint]) -> Float {
        let clamped = max(0, min(normalized, 1.0))
        guard points.count > 1 else { return points.first?.y ?? 0.5 }
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
        if range < 0.0001 { return left.y }
        let t = (clamped - left.x) / range
        return left.y + (right.y - left.y) * t
    }
    
    func sampleValue(at normalized: Float) -> Float {
        guard !controlPoints.isEmpty else { return 0.5 }
        guard controlPoints.count > 1 else { return controlPoints[0].y }
        
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

        func colorForSpectrumX(_ x: Float) -> SIMD4<Float> {
            let t = max(0, min(x, 1))
            let stops: [(Float, SIMD3<Float>)] = [
                (0.0, SIMD3<Float>(0.58, 0.0, 0.83)),
                (0.2, SIMD3<Float>(0.15, 0.35, 1.0)),
                (0.45, SIMD3<Float>(0.0, 0.9, 0.65)),
                (0.7, SIMD3<Float>(1.0, 0.9, 0.1)),
                (0.88, SIMD3<Float>(1.0, 0.45, 0.0)),
                (1.0, SIMD3<Float>(0.9, 0.05, 0.05))
            ]
            var left = stops[0]
            var right = stops[1]
            for i in 0..<(stops.count - 1) {
                if stops[i].0 <= t && t <= stops[i + 1].0 {
                    left = stops[i]
                    right = stops[i + 1]
                    break
                }
            }
            let range = right.0 - left.0
            let localT = range < 0.0001 ? 0 : (t - left.0) / range
            let rgb = left.1 + (right.1 - left.1) * localT
            return SIMD4<Float>(rgb.x, rgb.y, rgb.z, 1.0)
        }

        func fixedTenPointPreset(weights: [Float]) -> [ColorSpectrumPoint] {
            guard weights.count == 10 else { return [] }
            return (0..<10).map { i in
                let x = Float(i) / 9.0
                return ColorSpectrumPoint(x: x,
                                          y: max(0, min(weights[i], 1)),
                                          color: colorForSpectrumX(x))
            }
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
                (1.0, 0.5, SIMD4<Float>(1.0, 0.1, 1.0, 1.0))
            ])
        case .fire:
            controlPoints = points(from: [
                (0.0, 0.0, SIMD4<Float>(0.18, 0.0, 0.0, 1.0)),
                (0.18, 0.06, SIMD4<Float>(0.45, 0.02, 0.0, 1.0)),
                (0.32, 0.45, SIMD4<Float>(0.88, 0.04, 0.0, 1.0)),
                (0.55, 1.0, SIMD4<Float>(1.0, 0.12, 0.0, 1.0)),
                (0.74, 0.92, SIMD4<Float>(1.0, 0.86, 0.0, 0.1)),
                (1.0, 0.10, SIMD4<Float>(1.0, 0.92, 0.18, 1.0))
            ])
        case .reddish:
            controlPoints = fixedTenPointPreset(weights: [0, 0, 0, 0, 0, 0, 0, 0.7, 1.0, 0.85])
        case .bluish:
            controlPoints = fixedTenPointPreset(weights: [0.85, 1.0, 0.7, 0, 0, 0, 0, 0, 0, 0])
        case .greenField:
            controlPoints = points(from: [
                (0.0, 0.06, SIMD4<Float>(0.1, 0.32, 0.08, 1.0)),
                (0.25, 0.42, SIMD4<Float>(0.2, 0.55, 0.16, 1.0)),
                (0.5, 1.0, SIMD4<Float>(0.35, 0.85, 0.28, 1.0)),
                (0.75, 0.42, SIMD4<Float>(0.2, 0.55, 0.16, 1.0)),
                (1.0, 0.06, SIMD4<Float>(0.1, 0.32, 0.08, 1.0))
            ])
        case .neonNight:
            controlPoints = points(from: [
                (0.0, 0.12, SIMD4<Float>(0.22, 0.0, 0.55, 1.0)),
                (0.18, 1.0, SIMD4<Float>(0.05, 0.30, 1.0, 1.0)),
                (0.32, 0.82, SIMD4<Float>(0.0, 0.52, 1.0, 1.0)),
                (0.55, 0.18, SIMD4<Float>(0.2, 0.95, 1.0, 1.0)),
                (1.0, 0.03, SIMD4<Float>(0.52, 0.0, 0.85, 1.0))
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
        guard !points.isEmpty else { return SIMD4<Float>(1, 1, 1, 1) }
        guard points.count > 1 else { return points[0].color }

        let clamped = max(0, min(normalized, 1.0))
        var left = points[0]
        var right = points[1]

        for i in 0..<(points.count - 1) {
            if points[i].x <= clamped && points[i + 1].x >= clamped {
                left = points[i]
                right = points[i + 1]
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
