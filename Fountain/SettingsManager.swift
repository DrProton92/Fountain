import Foundation
import simd

// MARK: - Persisted settings model

struct AppSettings: Codable {
    var schemaVersion = 1
    var general = GeneralSettings()
    var color = ColorSettings()
    var size = SizeSettings()
    var velocity = VelocitySettings()
    var camera = CameraSettings()

    static let defaults = AppSettings()
}

struct GeneralSettings: Codable {
    var particleCount = defaultParticleCount
    var launchAngleDegrees: Float = 0
    var angleVarianceDegrees: Float = 12
    var velocityVariancePercent: Float = 0
    var trailsEnabled = false
    var trailLength: Float = 2
    var showAxis = false
}

struct ColorSettings: Codable {
    var style: ParticleColorStyle = .rainbow
    var spectrum = ColorSpectrum()

    init() {
        spectrum.applyPreset(style)
    }
}

struct SizeSettings: Codable {
    var mode: ParticleSizeMode = .constant
    var constantSize: Float = 5
    var distribution = SizeDistribution()
    var preset: SizeDistributionPreset = .flat
    var variancePercent: Float = 50
    var minRange: Float = 5
    var maxRange: Float = 30
}

struct VelocitySettings: Codable {
    var mode: ParticleSizeMode = .random
    var constantVelocity: Float = 0.04
    var distribution = SizeDistribution()
    var preset: SizeDistributionPreset = .gaussian
    var variancePercent: Float = 50
    var minRange: Float = 0.02
    var maxRange: Float = 0.08

    init() {
        distribution.applyPreset(preset, variancePercent: variancePercent)
    }
}

struct CameraSettings: Codable {
    var controlMode: CameraControlMode = .touchControlled
    var motionModel: CameraMotionModel = .orbit
    var inclinationDegrees: Float = 22
}

extension SizeDistributionPoint: Codable {
    private enum CodingKeys: String, CodingKey { case x, y }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try values.decode(Float.self, forKey: .x),
                  y: try values.decode(Float.self, forKey: .y))
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(x, forKey: .x)
        try values.encode(y, forKey: .y)
    }
}

extension ColorSpectrumPoint: Codable {
    private enum CodingKeys: String, CodingKey { case x, y, r, g, b, a }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try values.decode(Float.self, forKey: .x),
            y: try values.decode(Float.self, forKey: .y),
            color: SIMD4<Float>(
                try values.decode(Float.self, forKey: .r),
                try values.decode(Float.self, forKey: .g),
                try values.decode(Float.self, forKey: .b),
                try values.decode(Float.self, forKey: .a)
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(x, forKey: .x)
        try values.encode(y, forKey: .y)
        try values.encode(color.x, forKey: .r)
        try values.encode(color.y, forKey: .g)
        try values.encode(color.z, forKey: .b)
        try values.encode(color.w, forKey: .a)
    }
}

extension SizeDistribution: Codable {
    private enum CodingKeys: String, CodingKey { case controlPoints }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        controlPoints = try values.decode([SizeDistributionPoint].self, forKey: .controlPoints)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(controlPoints, forKey: .controlPoints)
    }
}

extension ColorSpectrum: Codable {
    private enum CodingKeys: String, CodingKey { case controlPoints, preset, singleColor }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        controlPoints = try values.decode([ColorSpectrumPoint].self, forKey: .controlPoints)
        preset = try values.decode(ParticleColorStyle.self, forKey: .preset)
        let components = try values.decode([Float].self, forKey: .singleColor)
        guard components.count == 4 else {
            throw DecodingError.dataCorruptedError(forKey: .singleColor, in: values, debugDescription: "Expected four color components")
        }
        singleColor = SIMD4<Float>(components[0], components[1], components[2], components[3])
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(controlPoints, forKey: .controlPoints)
        try values.encode(preset, forKey: .preset)
        try values.encode([singleColor.x, singleColor.y, singleColor.z, singleColor.w], forKey: .singleColor)
    }
}

// MARK: - Settings manager

@MainActor
final class SettingsManager {
    static let shared = SettingsManager()

    let defaults: AppSettings = .defaults
    private(set) var settings: AppSettings
    private weak var renderer: Renderer?
    private let fileURL: URL
    private var hasPersistedSettings = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.settings = .defaults
        try? load()
    }

    func bind(to renderer: Renderer) {
        self.renderer = renderer
        // Renderer initializes to the same defaults. Avoid repeating all
        // particle work on a first launch when there is no file to restore.
        if hasPersistedSettings {
            applyAllSettingsToRenderer()
        }
    }

    func resetToDefaults() {
        settings = defaults
        applyAllSettingsToRenderer()
        try? save()
    }

    func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        settings = try Self.decoder.decode(AppSettings.self, from: data)
        normalize()
        hasPersistedSettings = true
    }

    func save() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(settings)
        try data.write(to: fileURL, options: [.atomic])
    }

    func export(to url: URL) throws {
        try Self.encoder.encode(settings).write(to: url, options: [.atomic])
    }

    func `import`(from url: URL) throws {
        settings = try Self.decoder.decode(AppSettings.self, from: Data(contentsOf: url))
        normalize()
        applyAllSettingsToRenderer()
        try save()
    }

    // Public read access used by configuration screens.
    var activeParticleCount: Int { settings.general.particleCount }
    var launchAngleDegrees: Float { settings.general.launchAngleDegrees }
    var angleVarianceDegrees: Float { settings.general.angleVarianceDegrees }
    var velocityVariancePercent: Float { settings.general.velocityVariancePercent }
    var trailsEnabled: Bool { settings.general.trailsEnabled }
    var trailLength: Float { settings.general.trailLength }
    var showAxis: Bool { settings.general.showAxis }
    var particleColorStyle: ParticleColorStyle { settings.color.style }
    var colorSpectrum: ColorSpectrum { settings.color.spectrum }
    var particleSizeMode: ParticleSizeMode { settings.size.mode }
    var constantParticleSize: Float { settings.size.constantSize }
    var sizeDistribution: SizeDistribution { settings.size.distribution }
    var sizeDistributionPreset: SizeDistributionPreset { settings.size.preset }
    var sizeSpectrumVariancePercent: Float { settings.size.variancePercent }
    var minSizeRange: Float { settings.size.minRange }
    var maxSizeRange: Float { settings.size.maxRange }
    var particleVelocityMode: ParticleSizeMode { settings.velocity.mode }
    var constantParticleVelocity: Float { settings.velocity.constantVelocity }
    var velocityDistribution: SizeDistribution { settings.velocity.distribution }
    var velocityDistributionPreset: SizeDistributionPreset { settings.velocity.preset }
    var velocitySpectrumVariancePercent: Float { settings.velocity.variancePercent }
    var minVelocityRange: Float { settings.velocity.minRange }
    var maxVelocityRange: Float { settings.velocity.maxRange }
    var cameraControlMode: CameraControlMode { settings.camera.controlMode }
    var cameraMotionModel: CameraMotionModel { settings.camera.motionModel }
    var cameraInclinationDegrees: Float { settings.camera.inclinationDegrees }

    func setParticleCount(_ value: Int) { settings.general.particleCount = value; commit() }
    func setLaunchAngle(_ value: Float) { settings.general.launchAngleDegrees = value; commit() }
    func setAngleVariance(_ value: Float) { settings.general.angleVarianceDegrees = value; commit() }
    func setVelocityVariance(_ value: Float) { settings.general.velocityVariancePercent = value; commit() }
    func setTrailsEnabled(_ value: Bool) { settings.general.trailsEnabled = value; commit() }
    func setTrailLength(_ value: Float) { settings.general.trailLength = value; commit() }
    func setShowAxis(_ value: Bool) { settings.general.showAxis = value; commit() }
    func setParticleColorStyle(_ value: ParticleColorStyle) { settings.color.style = value; settings.color.spectrum.preset = value; commit() }
    func setColorSpectrum(_ value: ColorSpectrum) { settings.color.spectrum = value; settings.color.style = value.preset; commit() }
    func setSingleColor(_ value: SIMD4<Float>) { settings.color.spectrum.singleColor = value; commit() }
    func setParticleSizeMode(_ value: ParticleSizeMode) { settings.size.mode = value; commit() }
    func setConstantParticleSize(_ value: Float) { settings.size.constantSize = value; commit() }
    func setSizeRange(_ minValue: Float, _ maxValue: Float) { settings.size.minRange = minValue; settings.size.maxRange = maxValue; commit() }
    func setSizeDistribution(_ value: SizeDistribution) { settings.size.distribution = value; commit() }
    func setSizeDistributionPreset(_ value: SizeDistributionPreset) { settings.size.preset = value; commit() }
    func setSizeSpectrumVariance(_ value: Float) { settings.size.variancePercent = value; commit() }
    func setParticleVelocityMode(_ value: ParticleSizeMode) { settings.velocity.mode = value; commit() }
    func setConstantParticleVelocity(_ value: Float) { settings.velocity.constantVelocity = value; commit() }
    func setVelocityRange(_ minValue: Float, _ maxValue: Float) { settings.velocity.minRange = minValue; settings.velocity.maxRange = maxValue; commit() }
    func setVelocityDistribution(_ value: SizeDistribution) { settings.velocity.distribution = value; commit() }
    func setVelocityDistributionPreset(_ value: SizeDistributionPreset) { settings.velocity.preset = value; commit() }
    func setVelocitySpectrumVariance(_ value: Float) { settings.velocity.variancePercent = value; commit() }
    func setCameraControlMode(_ value: CameraControlMode) { settings.camera.controlMode = value; commit() }
    func setCameraMotionModel(_ value: CameraMotionModel) { settings.camera.motionModel = value; commit() }
    func setCameraInclination(_ value: Float) { settings.camera.inclinationDegrees = value; commit() }

    private func commit() {
        normalize()
        applyAllSettingsToRenderer()
        try? save()
    }

    private func normalize() {
        settings.general.particleCount = min(max(settings.general.particleCount, 100), maxParticleCount)
        settings.general.launchAngleDegrees = min(max(settings.general.launchAngleDegrees, 0), 90)
        settings.general.angleVarianceDegrees = min(max(settings.general.angleVarianceDegrees, 0), 90)
        settings.general.velocityVariancePercent = min(max(settings.general.velocityVariancePercent, 0), 100)
        settings.general.trailLength = min(max(settings.general.trailLength, 1), Float(maxTrailHistorySamples))
        settings.size.constantSize = min(max(settings.size.constantSize, 0.5), 30)
        settings.size.minRange = min(max(settings.size.minRange, 0.5), 50)
        settings.size.maxRange = min(max(settings.size.maxRange, settings.size.minRange), 50)
        settings.size.variancePercent = min(max(settings.size.variancePercent, 0), 100)
        settings.velocity.constantVelocity = min(max(settings.velocity.constantVelocity, 0.005), 0.2)
        settings.velocity.minRange = min(max(settings.velocity.minRange, 0.005), 0.2)
        settings.velocity.maxRange = min(max(settings.velocity.maxRange, settings.velocity.minRange), 0.2)
        settings.velocity.variancePercent = min(max(settings.velocity.variancePercent, 0), 100)
        settings.camera.inclinationDegrees = min(max(settings.camera.inclinationDegrees, 0), 85)
    }

    private func applyAllSettingsToRenderer() {
        guard let renderer else { return }
        renderer.apply(settings: settings)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Fountain", isDirectory: true).appendingPathComponent("settings.json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}
