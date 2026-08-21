//
//  ParticleColorSettingsViewController.swift
//  ipadgameapp
//
//  Created by GitHub Copilot on 8/20/26.
//

import UIKit

final class ColorWheelView: UIControl {
    var color: UIColor = .white {
        didSet { setNeedsDisplay() }
    }
    var onColorChanged: ((UIColor) -> Void)?
    private let knobRadius: CGFloat = 10
    
    override func draw(_ rect: CGRect) {
        let insetRect = rect.insetBy(dx: 8, dy: 8)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let center = CGPoint(x: insetRect.midX, y: insetRect.midY)
        let radius = min(insetRect.width, insetRect.height) / 2

        for i in stride(from: 0, to: 360, by: 2) {
            let startAngle = CGFloat(i) * .pi / 180
            let endAngle = CGFloat(i + 2) * .pi / 180
            let hue = CGFloat(i) / 360.0
            let segmentColor = UIColor(hue: hue, saturation: 1, brightness: 1, alpha: 1)
            context.setFillColor(segmentColor.cgColor)
            context.move(to: center)
            context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
            context.closePath()
            context.fillPath()
        }

        UIColor.black.withAlphaComponent(0.08).setFill()
        UIBezierPath(ovalIn: insetRect).fill()

        let hueSat = color.hsbComponents
        let markerAngle = CGFloat(hueSat.h) * 2 * .pi
        let markerRadius = radius * CGFloat(hueSat.s)
        let markerPoint = CGPoint(x: center.x + cos(markerAngle) * markerRadius,
                                  y: center.y + sin(markerAngle) * markerRadius)
        let marker = UIBezierPath(arcCenter: markerPoint, radius: knobRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
        UIColor.white.setStroke()
        marker.lineWidth = 2
        marker.stroke()
        UIColor.black.setStroke()
        marker.lineWidth = 1
        marker.stroke()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateColor(from: touch.location(in: self))
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateColor(from: touch.location(in: self))
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let point = touch?.location(in: self) {
            updateColor(from: point)
        }
    }

    private func updateColor(from point: CGPoint) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let angle = atan2(dy, dx)
        let hue = (angle < 0 ? angle + 2 * .pi : angle) / (2 * .pi)
        let distance = sqrt(dx * dx + dy * dy)
        let radius = min(bounds.width, bounds.height) / 2 - 8
        let saturation = min(max(distance / radius, 0), 1)
        let brightness: CGFloat = 1
        color = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        onColorChanged?(color)
        sendActions(for: .valueChanged)
    }
}

private extension UIColor {
    var hsbComponents: (h: CGFloat, s: CGFloat, b: CGFloat, a: CGFloat) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (h, s, b, a)
    }
    
    func toSIMD4Float() -> SIMD4<Float> {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
    }
}

final class SpectrumEditorView: UIView {
    var spectrum: ColorSpectrum {
        didSet { setNeedsDisplay() }
    }
    var onSpectrumChanged: ((ColorSpectrum) -> Void)?

    private let gridColor = UIColor.gray.withAlphaComponent(0.25)
    private let pointRadius: CGFloat = 8
    private let inset: CGFloat = 12
    private var selectedPointIndex: Int?
    private let pointCount = 10

    init(spectrum: ColorSpectrum) {
        self.spectrum = spectrum
        super.init(frame: .zero)
        backgroundColor = UIColor.black.withAlphaComponent(0.82)
        layer.cornerRadius = 8
        layer.masksToBounds = true
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let drawRect = rect.insetBy(dx: inset, dy: inset)

        drawSpectrumBackground(in: drawRect, context: context)

        gridColor.setStroke()
        context.setLineWidth(0.5)
        var x = drawRect.minX
        while x <= drawRect.maxX {
            context.move(to: CGPoint(x: x, y: drawRect.minY))
            context.addLine(to: CGPoint(x: x, y: drawRect.maxY))
            x += 24
        }
        var y = drawRect.minY
        while y <= drawRect.maxY {
            context.move(to: CGPoint(x: drawRect.minX, y: y))
            context.addLine(to: CGPoint(x: drawRect.maxX, y: y))
            y += 24
        }
        context.strokePath()

        if spectrum.controlPoints.count > 1 {
            let path = UIBezierPath()
            let samples = 120
            for i in 0...samples {
                let t = Float(i) / Float(samples)
                let c = sampleColor(at: t)
                let p = CGPoint(x: drawRect.minX + CGFloat(t) * drawRect.width,
                                y: drawRect.maxY - CGFloat(sampleHeight(at: t)) * drawRect.height)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }

                let fill = UIBezierPath(arcCenter: p, radius: 1.5, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
                UIColor(cgColor: CGColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: CGFloat(c.w))).setFill()
                fill.fill()
            }
            UIColor.white.withAlphaComponent(0.85).setStroke()
            path.lineWidth = 2
            path.stroke()
        }

        for (index, point) in spectrum.controlPoints.enumerated() {
            let p = CGPoint(x: drawRect.minX + CGFloat(point.x) * drawRect.width,
                            y: drawRect.maxY - CGFloat(point.y) * drawRect.height)
            let circle = UIBezierPath(arcCenter: p, radius: pointRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            let pointColor = pointColorAtX(point.x)
            UIColor(cgColor: CGColor(red: CGFloat(pointColor.x), green: CGFloat(pointColor.y), blue: CGFloat(pointColor.z), alpha: 1)).setFill()
            circle.fill()
            (index == selectedPointIndex ? UIColor.systemGreen : .white).setStroke()
            circle.lineWidth = 1.5
            circle.stroke()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ensureTenPoints()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        let drawRect = bounds.insetBy(dx: inset, dy: inset)
        selectedPointIndex = nil

        var closestIndex = -1
        var closestDistance = CGFloat.infinity
        for (index, controlPoint) in spectrum.controlPoints.enumerated() {
            let p = CGPoint(x: drawRect.minX + CGFloat(controlPoint.x) * drawRect.width,
                            y: drawRect.maxY - CGFloat(controlPoint.y) * drawRect.height)
            let distance = hypot(point.x - p.x, point.y - p.y)
            if distance < closestDistance && distance <= pointRadius * 2 {
                closestDistance = distance
                closestIndex = index
            }
        }
        selectedPointIndex = closestIndex >= 0 ? closestIndex : nil
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let index = selectedPointIndex else { return }
        let point = touch.location(in: self)
        let drawRect = bounds.insetBy(dx: inset, dy: inset)

        let normalizedX = Float((point.x - drawRect.minX) / drawRect.width)
        let normalizedY = Float((drawRect.maxY - point.y) / drawRect.height)
        if index == 0 {
            spectrum.controlPoints[index].x = 0.0
        } else if index == spectrum.controlPoints.count - 1 {
            spectrum.controlPoints[index].x = 1.0
        } else {
            spectrum.controlPoints[index].x = max(0, min(1, normalizedX))
        }
        spectrum.controlPoints[index].y = max(0, min(1, normalizedY))
        let rgb = pointColorAtX(spectrum.controlPoints[index].x)
        spectrum.controlPoints[index].color = SIMD4<Float>(rgb.x, rgb.y, rgb.z, 1.0)
        onSpectrumChanged?(spectrum)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        selectedPointIndex = nil
    }

    private func sampleColor(at normalized: Float) -> SIMD4<Float> {
        guard !spectrum.controlPoints.isEmpty else { return SIMD4<Float>(1, 1, 1, 1) }
        guard spectrum.controlPoints.count > 1 else { return spectrum.controlPoints[0].color }
        let clamped = max(0, min(normalized, 1.0))
        var left = spectrum.controlPoints[0]
        var right = spectrum.controlPoints[1]
        for i in 0..<(spectrum.controlPoints.count - 1) {
            if spectrum.controlPoints[i].x <= clamped && clamped <= spectrum.controlPoints[i + 1].x {
                left = spectrum.controlPoints[i]
                right = spectrum.controlPoints[i + 1]
                break
            }
        }
        let range = right.x - left.x
        if range < 0.0001 { return left.color }
        let t = (clamped - left.x) / range
        return left.color + (right.color - left.color) * t
    }

    private func sampleHeight(at normalized: Float) -> Float {
        guard !spectrum.controlPoints.isEmpty else { return 0.5 }
        guard spectrum.controlPoints.count > 1 else { return spectrum.controlPoints[0].y }
        let clamped = max(0, min(normalized, 1.0))
        var left = spectrum.controlPoints[0]
        var right = spectrum.controlPoints[1]
        for i in 0..<(spectrum.controlPoints.count - 1) {
            if spectrum.controlPoints[i].x <= clamped && clamped <= spectrum.controlPoints[i + 1].x {
                left = spectrum.controlPoints[i]
                right = spectrum.controlPoints[i + 1]
                break
            }
        }
        let range = right.x - left.x
        if range < 0.0001 { return left.y }
        let t = (clamped - left.x) / range
        return left.y + (right.y - left.y) * t
    }

    private func drawSpectrumBackground(in rect: CGRect, context: CGContext) {
        let colors: [CGColor] = [
            UIColor(red: 0.58, green: 0.0, blue: 0.83, alpha: 1).cgColor,
            UIColor(red: 0.15, green: 0.35, blue: 1.0, alpha: 1).cgColor,
            UIColor(red: 0.0, green: 0.9, blue: 0.65, alpha: 1).cgColor,
            UIColor(red: 1.0, green: 0.9, blue: 0.1, alpha: 1).cgColor,
            UIColor(red: 1.0, green: 0.45, blue: 0.0, alpha: 1).cgColor,
            UIColor(red: 0.9, green: 0.05, blue: 0.05, alpha: 1).cgColor
        ]
        let locations: [CGFloat] = [0.0, 0.2, 0.45, 0.7, 0.88, 1.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations) {
            context.saveGState()
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 8)
            path.addClip()
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: rect.minX, y: rect.midY),
                                       end: CGPoint(x: rect.maxX, y: rect.midY),
                                       options: [])
            context.restoreGState()
        }
    }

    private func pointColorAtX(_ x: Float) -> SIMD3<Float> {
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
        return left.1 + (right.1 - left.1) * localT
    }

    private func ensureTenPoints() {
        let target = pointCount
        guard spectrum.controlPoints.count != target else { return }
        let existing = spectrum.controlPoints.isEmpty ? [ColorSpectrumPoint(x: 0, y: 0.5, color: SIMD4<Float>(0.58, 0.0, 0.83, 1.0))] : spectrum.controlPoints.sorted { $0.x < $1.x }
        let resampled: [ColorSpectrumPoint] = (0..<target).map { i in
            let x = Float(i) / Float(target - 1)
            let y = interpolate(points: existing, at: x, keyPath: \ColorSpectrumPoint.y)
            let rgb = pointColorAtX(x)
            return ColorSpectrumPoint(x: x, y: y, color: SIMD4<Float>(rgb.x, rgb.y, rgb.z, 1.0))
        }
        spectrum.controlPoints = resampled
        onSpectrumChanged?(spectrum)
        setNeedsDisplay()
    }

    private func interpolate(points: [ColorSpectrumPoint], at normalized: Float, keyPath: KeyPath<ColorSpectrumPoint, Float>) -> Float {
        guard points.count > 1 else { return points.first?[keyPath: keyPath] ?? 0.5 }
        let clamped = max(0, min(normalized, 1.0))
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
        let localT = (clamped - left.x) / range
        return left[keyPath: keyPath] + (right[keyPath: keyPath] - left[keyPath: keyPath]) * localT
    }
}

final class ParticleColorSettingsViewController: UIViewController {
    
    var renderer: Renderer!
    private var selectedColorStyle: ParticleColorStyle = .singleColor
    private var selectedSpectrumPreset: ParticleColorStyle = .rainbow
    private var spectrum: ColorSpectrum = ColorSpectrum()
    private var spectrumEditor: SpectrumEditorView!
    private var colorWheelView: ColorWheelView!
    private var spectrumContainer: UIStackView!
    private var wheelContainer: UIStackView!
    private var modeControl: UISegmentedControl!
    private var selectedSingleColor: UIColor = .white
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        selectedColorStyle = renderer.particleColorStyle
        spectrum = renderer.colorSpectrum
        selectedSpectrumPreset = renderer.colorSpectrum.preset == .singleColor ? .rainbow : renderer.colorSpectrum.preset
        selectedSingleColor = UIColor(cgColor: CGColor(red: CGFloat(renderer.colorSpectrum.singleColor.x), green: CGFloat(renderer.colorSpectrum.singleColor.y), blue: CGFloat(renderer.colorSpectrum.singleColor.z), alpha: CGFloat(renderer.colorSpectrum.singleColor.w)))
        view.backgroundColor = .systemBackground
        
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        let styleLabel = UILabel()
        styleLabel.translatesAutoresizingMaskIntoConstraints = false
        styleLabel.text = "Color Mode"
        styleLabel.font = .boldSystemFont(ofSize: 16)
        contentView.addSubview(styleLabel)

        modeControl = UISegmentedControl(items: ["Single Color", "Spectrum"])
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.selectedSegmentIndex = selectedColorStyle == .singleColor ? 0 : 1
        modeControl.addTarget(self, action: #selector(colorModeChanged(_:)), for: .valueChanged)
        contentView.addSubview(modeControl)

        wheelContainer = UIStackView()
        wheelContainer.translatesAutoresizingMaskIntoConstraints = false
        wheelContainer.axis = .vertical
        wheelContainer.spacing = 8
        contentView.addSubview(wheelContainer)

        let wheelLabel = UILabel()
        wheelLabel.translatesAutoresizingMaskIntoConstraints = false
        wheelLabel.text = "Single Color"
        wheelLabel.font = .systemFont(ofSize: 14, weight: .medium)
        wheelLabel.textColor = .secondaryLabel
        wheelContainer.addArrangedSubview(wheelLabel)

        colorWheelView = ColorWheelView()
        colorWheelView.translatesAutoresizingMaskIntoConstraints = false
        colorWheelView.heightAnchor.constraint(equalToConstant: 220).isActive = true
        colorWheelView.onColorChanged = { [weak self] uiColor in
            guard let self else { return }
            self.selectedSingleColor = uiColor
            if self.selectedColorStyle == .singleColor {
                self.renderer.setSingleColor(uiColor.toSIMD4Float())
            }
        }
        wheelContainer.addArrangedSubview(colorWheelView)

        spectrumContainer = UIStackView()
        spectrumContainer.translatesAutoresizingMaskIntoConstraints = false
        spectrumContainer.axis = .vertical
        spectrumContainer.spacing = 8
        contentView.addSubview(spectrumContainer)

        let spectrumLabel = UILabel()
        spectrumLabel.translatesAutoresizingMaskIntoConstraints = false
        spectrumLabel.text = "Editable Spectrum"
        spectrumLabel.font = .systemFont(ofSize: 14, weight: .medium)
        spectrumLabel.textColor = .secondaryLabel
        spectrumContainer.addArrangedSubview(spectrumLabel)

        spectrumEditor = SpectrumEditorView(spectrum: spectrum)
        spectrumEditor.translatesAutoresizingMaskIntoConstraints = false
        spectrumEditor.heightAnchor.constraint(equalToConstant: 240).isActive = true
        spectrumEditor.onSpectrumChanged = { [weak self] newSpectrum in
            self?.spectrum = newSpectrum
            self?.renderer.setColorSpectrum(newSpectrum)
        }
        spectrumContainer.addArrangedSubview(spectrumEditor)

        let presetLabel = UILabel()
        presetLabel.translatesAutoresizingMaskIntoConstraints = false
        presetLabel.text = "Presets"
        presetLabel.font = .systemFont(ofSize: 14, weight: .medium)
        presetLabel.textColor = .secondaryLabel
        spectrumContainer.addArrangedSubview(presetLabel)

        let presetButtonRow = UIStackView()
        presetButtonRow.translatesAutoresizingMaskIntoConstraints = false
        presetButtonRow.axis = .horizontal
        presetButtonRow.spacing = 8
        presetButtonRow.distribution = .fillEqually
        spectrumContainer.addArrangedSubview(presetButtonRow)

        for style in [ParticleColorStyle.rainbow, .fire, .pastel, .neon] {
            let button = UIButton(type: .system)
            button.setTitle(style.displayName, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            button.backgroundColor = .secondarySystemBackground
            button.layer.cornerRadius = 8
            button.clipsToBounds = true
            button.tag = style.rawValue
            button.addTarget(self, action: #selector(spectrumPresetTapped(_:)), for: .touchUpInside)
            presetButtonRow.addArrangedSubview(button)
        }

        let hintLabel = UILabel()
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.text = "Single Color uses the wheel. Other presets use the spectrum graph."
        hintLabel.font = .systemFont(ofSize: 12, weight: .regular)
        hintLabel.textColor = .secondaryLabel
        hintLabel.numberOfLines = 0
        contentView.addSubview(hintLabel)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            styleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            styleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            modeControl.topAnchor.constraint(equalTo: styleLabel.bottomAnchor, constant: 12),
            modeControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            modeControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            wheelContainer.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 20),
            wheelContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            wheelContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            spectrumContainer.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 20),
            spectrumContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            spectrumContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            hintLabel.topAnchor.constraint(equalTo: (selectedColorStyle == .singleColor ? wheelContainer : spectrumContainer).bottomAnchor, constant: 8),
            hintLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            hintLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])

        updateModeVisibility()
    }
    
    @objc private func colorModeChanged(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 0 {
            selectedColorStyle = .singleColor
            renderer.setParticleColorStyle(.singleColor)
            renderer.setSingleColor(selectedSingleColor.toSIMD4Float())
        } else {
            selectedColorStyle = selectedSpectrumPreset
            spectrum.applyPreset(selectedSpectrumPreset)
            spectrumEditor.spectrum = spectrum
            renderer.setColorSpectrum(spectrum)
        }
        updateModeVisibility()
    }

    @objc private func spectrumPresetTapped(_ sender: UIButton) {
        guard let style = ParticleColorStyle(rawValue: sender.tag), style != .singleColor else { return }
        selectedSpectrumPreset = style
        selectedColorStyle = style
        spectrum.applyPreset(style)
        spectrumEditor.spectrum = spectrum
        renderer.setColorSpectrum(spectrum)
    }
    
    func applyConfiguration() {
        if selectedColorStyle == .singleColor {
            renderer.setParticleColorStyle(.singleColor)
            renderer.setSingleColor(selectedSingleColor.toSIMD4Float())
        } else {
            renderer.setColorSpectrum(spectrum)
        }
    }

    private func updateModeVisibility() {
        wheelContainer.isHidden = selectedColorStyle != .singleColor
        spectrumContainer.isHidden = selectedColorStyle == .singleColor
        colorWheelView.color = selectedSingleColor
        modeControl.selectedSegmentIndex = selectedColorStyle == .singleColor ? 0 : 1
        if selectedColorStyle != .singleColor {
            spectrum.applyPreset(selectedColorStyle)
            spectrumEditor.spectrum = spectrum
        }
    }
}
