//
//  ParticleSizeConfigView.swift
//  ipadgameapp
//
//  Created by Dave Schmid on 8/19/26.
//

import UIKit

/// A custom view for graphically editing particle size distribution
class DistributionEditorView: UIView {
    
    var distribution: SizeDistribution {
        didSet {
            setNeedsDisplay()
        }
    }
    
    var onDistributionChanged: ((SizeDistribution) -> Void)?
    
    private let gridColor = UIColor.gray.withAlphaComponent(0.3)
    private let curveColor = UIColor.systemBlue
    private let pointColor = UIColor.systemBlue
    private let pointRadius: CGFloat = 8
    private let gridSize: CGFloat = 20
    private let pointCount = 10
    
    private var selectedPointIndex: Int?
    
    init(distribution: SizeDistribution) {
        self.distribution = distribution
        super.init(frame: .zero)
        self.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        self.layer.cornerRadius = 8
        self.layer.masksToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ensureTenPoints()
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Draw grid
        drawGrid(in: rect, context: context)
        
        // Draw curve
        drawCurve(in: rect, context: context)
        
        // Draw control points
        drawControlPoints(in: rect, context: context)
    }
    
    private func drawGrid(in rect: CGRect, context: CGContext) {
        gridColor.setStroke()
        context.setLineWidth(0.5)
        
        let inset: CGFloat = 10
        let drawRect = rect.insetBy(dx: inset, dy: inset)
        
        // Draw vertical grid lines
        var x = drawRect.minX
        while x <= drawRect.maxX {
            context.move(to: CGPoint(x: x, y: drawRect.minY))
            context.addLine(to: CGPoint(x: x, y: drawRect.maxY))
            x += gridSize
        }
        
        // Draw horizontal grid lines
        var y = drawRect.minY
        while y <= drawRect.maxY {
            context.move(to: CGPoint(x: drawRect.minX, y: y))
            context.addLine(to: CGPoint(x: drawRect.maxX, y: y))
            y += gridSize
        }
        
        context.strokePath()
        
        // Draw axis labels
        UIColor.gray.setFill()
        let labelFont = UIFont.systemFont(ofSize: 10)
        let axisAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: UIColor.gray]
        
        NSString(string: "0").draw(at: CGPoint(x: inset - 8, y: drawRect.maxY - 5), withAttributes: axisAttrs)
        NSString(string: "1").draw(at: CGPoint(x: inset - 8, y: drawRect.minY - 5), withAttributes: axisAttrs)
    }
    
    private func drawCurve(in rect: CGRect, context: CGContext) {
        let inset: CGFloat = 10
        let drawRect = rect.insetBy(dx: inset, dy: inset)
        
        guard distribution.controlPoints.count > 1 else { return }
        
        curveColor.setStroke()
        context.setLineWidth(2)
        
        // Sample the curve at many points
        let samples = 100
        let path = UIBezierPath()
        
        for i in 0...samples {
            let t = Float(i) / Float(samples)
            let value = distribution.sampleValue(at: t)
            
            let x = drawRect.minX + CGFloat(t) * drawRect.width
            let y = drawRect.maxY - CGFloat(value) * drawRect.height
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        path.stroke()
    }
    
    private func drawControlPoints(in rect: CGRect, context: CGContext) {
        let inset: CGFloat = 10
        let drawRect = rect.insetBy(dx: inset, dy: inset)
        
        for (index, point) in distribution.controlPoints.enumerated() {
            let x = drawRect.minX + CGFloat(point.x) * drawRect.width
            let y = drawRect.maxY - CGFloat(point.y) * drawRect.height
            
            let isSelected = index == selectedPointIndex
            let color = isSelected ? UIColor.systemGreen : pointColor
            
            let circle = UIBezierPath(arcCenter: CGPoint(x: x, y: y),
                                     radius: pointRadius,
                                     startAngle: 0,
                                     endAngle: 2 * .pi,
                                     clockwise: true)
            color.setFill()
            circle.fill()
            
            UIColor.white.setStroke()
            circle.lineWidth = 1.5
            circle.stroke()
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        
        let inset: CGFloat = 10
        let drawRect = bounds.insetBy(dx: inset, dy: inset)
        
        // Find closest control point
        var closestIndex = -1
        var closestDistance = CGFloat.infinity
        
        for (index, controlPoint) in distribution.controlPoints.enumerated() {
            let x = drawRect.minX + CGFloat(controlPoint.x) * drawRect.width
            let y = drawRect.maxY - CGFloat(controlPoint.y) * drawRect.height
            
            let distance = hypot(point.x - x, point.y - y)
            if distance < closestDistance && distance <= pointRadius * 2 {
                closestDistance = distance
                closestIndex = index
            }
        }
        
        selectedPointIndex = closestIndex >= 0 ? closestIndex : nil
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let index = selectedPointIndex else { return }
        let point = touch.location(in: self)
        
        let inset: CGFloat = 10
        let drawRect = bounds.insetBy(dx: inset, dy: inset)
        
        // Convert screen coordinates to distribution coordinates
        let normalizedX = Float((point.x - drawRect.minX) / drawRect.width)
        let normalizedY = Float((drawRect.maxY - point.y) / drawRect.height)
        
        let clampedX: Float
        if index == 0 {
            clampedX = 0.0
        } else if index == distribution.controlPoints.count - 1 {
            clampedX = 1.0
        } else {
            let epsilon: Float = 0.001
            let minX = distribution.controlPoints[index - 1].x + epsilon
            let maxX = distribution.controlPoints[index + 1].x - epsilon
            clampedX = max(minX, min(maxX, max(0, min(1, normalizedX))))
        }
        let clampedY = max(0, min(1, normalizedY))
        
        distribution.controlPoints[index].x = clampedX
        distribution.controlPoints[index].y = clampedY
        
        onDistributionChanged?(distribution)
        setNeedsDisplay()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        selectedPointIndex = nil
    }

    private func ensureTenPoints() {
        guard distribution.controlPoints.count != pointCount else { return }
        let existing = distribution.controlPoints.isEmpty
            ? [SizeDistributionPoint(x: 0, y: 0.5)]
            : distribution.controlPoints.sorted { $0.x < $1.x }

        distribution.controlPoints = (0..<pointCount).map { i in
            let x = Float(i) / Float(pointCount - 1)
            let y = interpolate(points: existing, at: x)
            return SizeDistributionPoint(x: x, y: y)
        }

        onDistributionChanged?(distribution)
        setNeedsDisplay()
    }

    private func interpolate(points: [SizeDistributionPoint], at normalized: Float) -> Float {
        guard points.count > 1 else { return points.first?.y ?? 0.5 }
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
        if range < 0.0001 { return left.y }
        let t = (clamped - left.x) / range
        return left.y + (right.y - left.y) * t
    }
}

/// View controller for particle size configuration
class ParticleSizeConfigViewController: UIViewController {
    
    var renderer: Renderer!
    
    private var sizeMode: ParticleSizeMode = .constant
    private var constantSize: Float = 5.0
    private var minSize: Float = 5.0
    private var maxSize: Float = 30.0
    private var distribution: SizeDistribution = SizeDistribution()
    
    private var sizeModeControl: UISegmentedControl!
    private var constantModeContainer: UIStackView!
    private var constantSizeSlider: UISlider!
    private var constantSizeField: UITextField!
    private var randomModeContainer: UIStackView!
    private var minSizeSlider: UISlider!
    private var maxSizeSlider: UISlider!
    private var minSizeField: UITextField!
    private var maxSizeField: UITextField!
    private var distributionEditor: DistributionEditorView!
    private var presetButtonRow: UIStackView!
    private var presetButtons: [UIButton] = []

    private enum PresetButtonLayoutMode {
        case singleRow
        case wrappedRows
    }
    private var currentPresetButtonLayoutMode: PresetButtonLayoutMode?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sizeMode = renderer.particleSizeMode
        constantSize = renderer.constantParticleSize
        minSize = renderer.minSizeRange
        maxSize = renderer.maxSizeRange
        distribution = renderer.sizeDistribution
        
        view.backgroundColor = .systemBackground
        
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        let mainStack = UIStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .vertical
        mainStack.spacing = 18
        contentView.addSubview(mainStack)
        
        let sizeModeLabel = UILabel()
        sizeModeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeModeLabel.text = "Size Mode"
        sizeModeLabel.font = .boldSystemFont(ofSize: 16)
        mainStack.addArrangedSubview(sizeModeLabel)
        
        sizeModeControl = UISegmentedControl(items: ParticleSizeMode.allCases.map(\.displayName))
        sizeModeControl.translatesAutoresizingMaskIntoConstraints = false
        sizeModeControl.selectedSegmentIndex = sizeMode.rawValue
        sizeModeControl.addTarget(self, action: #selector(sizeModeChanged), for: .valueChanged)
        mainStack.addArrangedSubview(sizeModeControl)
        
        constantModeContainer = UIStackView()
        constantModeContainer.axis = .vertical
        constantModeContainer.spacing = 8
        mainStack.addArrangedSubview(constantModeContainer)

        let constantRow = UIStackView()
        constantRow.axis = .horizontal
        constantRow.spacing = 12
        constantRow.alignment = .center
        constantRow.translatesAutoresizingMaskIntoConstraints = false
        constantModeContainer.addArrangedSubview(constantRow)

        let constantLabel = UILabel()
        constantLabel.translatesAutoresizingMaskIntoConstraints = false
        constantLabel.text = "Single Size"
        constantLabel.font = .systemFont(ofSize: 13, weight: .medium)
        constantLabel.widthAnchor.constraint(equalToConstant: 96).isActive = true
        constantRow.addArrangedSubview(constantLabel)

        constantSizeSlider = UISlider()
        constantSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        constantSizeSlider.minimumValue = 0.5
        constantSizeSlider.maximumValue = 30
        constantSizeSlider.value = constantSize
        constantSizeSlider.addTarget(self, action: #selector(constantSizeChanged), for: .valueChanged)
        constantRow.addArrangedSubview(constantSizeSlider)

        constantSizeField = UITextField()
        constantSizeField.translatesAutoresizingMaskIntoConstraints = false
        constantSizeField.borderStyle = .roundedRect
        constantSizeField.keyboardType = .decimalPad
        constantSizeField.textAlignment = .center
        constantSizeField.text = String(format: "%.1f", constantSize)
        constantSizeField.widthAnchor.constraint(equalToConstant: 96).isActive = true
        constantSizeField.addAction(UIAction { [weak self] _ in
            self?.constantSizeEdited()
        }, for: .editingDidEnd)
        constantRow.addArrangedSubview(constantSizeField)
        
        randomModeContainer = UIStackView()
        randomModeContainer.axis = .vertical
        randomModeContainer.spacing = 10
        mainStack.addArrangedSubview(randomModeContainer)

        let distributionSectionLabel = UILabel()
        distributionSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        distributionSectionLabel.text = "Size Range & Spectrum"
        distributionSectionLabel.font = .boldSystemFont(ofSize: 14)
        randomModeContainer.addArrangedSubview(distributionSectionLabel)

        let minRow = makeSliderValueRow(title: "Min Size", value: minSize, min: 0.5, max: 25, action: #selector(minSizeChanged))
        minSizeSlider = minRow.slider
        minSizeField = minRow.valueField
        randomModeContainer.addArrangedSubview(minRow.container)

        let maxRow = makeSliderValueRow(title: "Max Size", value: maxSize, min: 0.5, max: 30, action: #selector(maxSizeChanged))
        maxSizeSlider = maxRow.slider
        maxSizeField = maxRow.valueField
        randomModeContainer.addArrangedSubview(maxRow.container)

        minSizeField.addAction(UIAction { [weak self] _ in
            self?.minSizeEdited()
        }, for: .editingDidEnd)

        maxSizeField.addAction(UIAction { [weak self] _ in
            self?.maxSizeEdited()
        }, for: .editingDidEnd)

        let editableSpectrumLabel = UILabel()
        editableSpectrumLabel.translatesAutoresizingMaskIntoConstraints = false
        editableSpectrumLabel.text = "Editable Spectrum"
        editableSpectrumLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        editableSpectrumLabel.textColor = .secondaryLabel
        randomModeContainer.addArrangedSubview(editableSpectrumLabel)

        distributionEditor = DistributionEditorView(distribution: distribution)
        distributionEditor.translatesAutoresizingMaskIntoConstraints = false
        distributionEditor.heightAnchor.constraint(equalToConstant: 240).isActive = true
        distributionEditor.onDistributionChanged = { [weak self] newDist in
            self?.distribution = newDist
        }
        randomModeContainer.addArrangedSubview(distributionEditor)

        let presetRow = UIStackView()
        presetRow.axis = .vertical
        presetRow.spacing = 8
        presetRow.alignment = .fill
        randomModeContainer.addArrangedSubview(presetRow)

        let presetLabel = UILabel()
        presetLabel.text = "Reset Spectrum to Preset:"
        presetLabel.font = .systemFont(ofSize: 14, weight: .medium)
        presetLabel.textColor = .secondaryLabel
        presetRow.addArrangedSubview(presetLabel)

        presetButtonRow = UIStackView()
        presetButtonRow.axis = .vertical
        presetButtonRow.spacing = 8
        presetButtonRow.alignment = .fill
        presetRow.addArrangedSubview(presetButtonRow)

        let orderedPresets: [SizeDistributionPreset] = [.flat, .skewedLeft, .gaussian, .skewedRight, .bigAndSmall]
        for preset in orderedPresets {
            let button = UIButton(type: .system)
            button.setTitle(preset.displayName, for: .normal)
            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = .secondarySystemBackground
            config.baseForegroundColor = .label
            config.cornerStyle = .medium
            config.titleAlignment = .center
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
            button.configuration = config
            button.addTarget(self, action: #selector(presetTapped(_:)), for: .touchUpInside)
            button.tag = preset.rawValue
            presetButtons.append(button)
        }

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

            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            constantSizeSlider.heightAnchor.constraint(equalToConstant: 31)
        ])

        updateUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePresetButtonLayout()
    }
    
    @objc private func sizeModeChanged() {
        sizeMode = ParticleSizeMode(rawValue: sizeModeControl.selectedSegmentIndex) ?? .constant
        updateUI()
    }
    
    @objc private func constantSizeChanged() {
        constantSize = constantSizeSlider.value
        constantSizeField.text = String(format: "%.1f", constantSize)
    }

    private func constantSizeEdited() {
        guard let text = constantSizeField.text, let value = Float(text) else {
            constantSizeField.text = String(format: "%.1f", constantSize)
            return
        }
        constantSize = min(max(value, 0.5), 30)
        constantSizeSlider.value = constantSize
        constantSizeField.text = String(format: "%.1f", constantSize)
    }
    
    @objc private func minSizeChanged() {
        minSize = minSizeSlider.value
        minSizeField.text = String(format: "%.1f", minSize)
        if minSize > maxSize {
            maxSize = minSize
            maxSizeSlider.value = maxSize
            maxSizeField.text = String(format: "%.1f", maxSize)
        }
    }
    
    @objc private func maxSizeChanged() {
        maxSize = maxSizeSlider.value
        maxSizeField.text = String(format: "%.1f", maxSize)
        if maxSize < minSize {
            minSize = maxSize
            minSizeSlider.value = minSize
            minSizeField.text = String(format: "%.1f", minSize)
        }
    }

    private func minSizeEdited() {
        guard let text = minSizeField.text, let value = Float(text) else {
            minSizeField.text = String(format: "%.1f", minSize)
            return
        }
        minSize = min(max(value, 0.5), 25.0)
        if minSize > maxSize {
            maxSize = minSize
            maxSizeSlider.value = maxSize
            maxSizeField.text = String(format: "%.1f", maxSize)
        }
        minSizeSlider.value = minSize
        minSizeField.text = String(format: "%.1f", minSize)
    }

    private func maxSizeEdited() {
        guard let text = maxSizeField.text, let value = Float(text) else {
            maxSizeField.text = String(format: "%.1f", maxSize)
            return
        }
        maxSize = min(max(value, 0.5), 30.0)
        if maxSize < minSize {
            minSize = maxSize
            minSizeSlider.value = minSize
            minSizeField.text = String(format: "%.1f", minSize)
        }
        maxSizeSlider.value = maxSize
        maxSizeField.text = String(format: "%.1f", maxSize)
    }
    
    @objc private func presetTapped(_ sender: UIButton) {
        let preset = SizeDistributionPreset(rawValue: sender.tag) ?? .gaussian
        distribution.applyPreset(preset)
        distributionEditor.distribution = distribution
    }

    private func updatePresetButtonLayout() {
        let availableWidth = randomModeContainer.bounds.width
        guard availableWidth > 0 else { return }

        let shouldWrap = availableWidth < 680
        let desiredMode: PresetButtonLayoutMode = shouldWrap ? .wrappedRows : .singleRow
        guard desiredMode != currentPresetButtonLayoutMode else { return }
        currentPresetButtonLayoutMode = desiredMode

        while let arranged = presetButtonRow.arrangedSubviews.first {
            presetButtonRow.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }

        let rows: [[UIButton]]
        switch desiredMode {
        case .singleRow:
            rows = [presetButtons]
        case .wrappedRows:
            rows = stride(from: 0, to: presetButtons.count, by: 3).map { start in
                let end = min(start + 3, presetButtons.count)
                return Array(presetButtons[start..<end])
            }
        }

        for rowButtons in rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.distribution = .fillEqually
            row.alignment = .fill
            for button in rowButtons {
                row.addArrangedSubview(button)
            }
            presetButtonRow.addArrangedSubview(row)
        }
    }
    
    private func updateUI() {
        constantModeContainer.isHidden = sizeMode != .constant
        randomModeContainer.isHidden = sizeMode != .random
        if sizeMode == .constant {
            constantSizeSlider.value = constantSize
            constantSizeField.text = String(format: "%.1f", constantSize)
        } else {
            minSizeSlider.value = minSize
            maxSizeSlider.value = maxSize
            minSizeField.text = String(format: "%.1f", minSize)
            maxSizeField.text = String(format: "%.1f", maxSize)
        }
    }
    
    func applyConfiguration() {
        guard isViewLoaded else { return }
        renderer.setParticleSizeMode(sizeMode)
        switch sizeMode {
        case .constant:
            renderer.setConstantParticleSize(constantSize)
        case .random:
            renderer.setSizeRange(minSize, maxSize)
            renderer.setSizeDistribution(distribution)
        }
    }

    private struct SliderValueRow {
        let container: UIStackView
        let slider: UISlider
        let valueField: UITextField
    }

    private func makeSliderValueRow(title: String, value: Float, min: Float, max: Float, action: Selector) -> SliderValueRow {
        let container = UIStackView()
        container.axis = .horizontal
        container.spacing = 12
        container.alignment = .center

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 96).isActive = true
        container.addArrangedSubview(label)

        let newSlider = UISlider()
        newSlider.translatesAutoresizingMaskIntoConstraints = false
        newSlider.minimumValue = min
        newSlider.maximumValue = max
        newSlider.value = value
        newSlider.addTarget(self, action: action, for: .valueChanged)
        container.addArrangedSubview(newSlider)

        let newValueField = UITextField()
        newValueField.translatesAutoresizingMaskIntoConstraints = false
        newValueField.borderStyle = .roundedRect
        newValueField.keyboardType = .decimalPad
        newValueField.textAlignment = .center
        newValueField.text = String(format: "%.1f", value)
        newValueField.widthAnchor.constraint(equalToConstant: 96).isActive = true
        container.addArrangedSubview(newValueField)

        return SliderValueRow(container: container, slider: newSlider, valueField: newValueField)
    }
}
