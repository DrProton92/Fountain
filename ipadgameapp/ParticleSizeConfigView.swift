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
        
        // Only allow dragging interior points, not endpoints
        if closestIndex > 0 && closestIndex < distribution.controlPoints.count - 1 {
            selectedPointIndex = closestIndex
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let index = selectedPointIndex else { return }
        let point = touch.location(in: self)
        
        let inset: CGFloat = 10
        let drawRect = bounds.insetBy(dx: inset, dy: inset)
        
        // Convert screen coordinates to distribution coordinates
        let normalizedX = Float((point.x - drawRect.minX) / drawRect.width)
        let normalizedY = Float((drawRect.maxY - point.y) / drawRect.height)
        
        // Clamp values but allow free X movement between neighbors
        let clampedX = max(0, min(1, normalizedX))
        let clampedY = max(0, min(1, normalizedY))
        
        distribution.controlPoints[index].x = clampedX
        distribution.controlPoints[index].y = clampedY
        
        onDistributionChanged?(distribution)
        setNeedsDisplay()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        selectedPointIndex = nil
    }
}

/// View controller for particle size configuration
class ParticleSizeConfigViewController: UIViewController {
    
    var renderer: Renderer!
    
    private var sizeMode: ParticleSizeMode = .constant
    private var constantSize: Float = 5.0
    private var minSize: Float = 1.0
    private var maxSize: Float = 10.0
    private var distribution: SizeDistribution = SizeDistribution()
    
    private var sizeModeControl: UISegmentedControl!
    private var constantModeContainer: UIStackView!
    private var constantSizeSlider: UISlider!
    private var constantSizeField: UITextField!
    private var randomModeContainer: UIStackView!
    private var minSizeSlider: UISlider!
    private var maxSizeSlider: UISlider!
    private var minSizeLabel: UILabel!
    private var maxSizeLabel: UILabel!
    private var distributionEditor: DistributionEditorView!
    private var presetStackView: UIStackView!
    
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

        let constantSectionLabel = UILabel()
        constantSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        constantSectionLabel.text = "Constant Size"
        constantSectionLabel.font = .boldSystemFont(ofSize: 14)
        constantModeContainer.addArrangedSubview(constantSectionLabel)

        let constantRow = UIStackView()
        constantRow.axis = .horizontal
        constantRow.spacing = 12
        constantRow.alignment = .center
        constantRow.translatesAutoresizingMaskIntoConstraints = false
        constantModeContainer.addArrangedSubview(constantRow)

        constantSizeSlider = UISlider()
        constantSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        constantSizeSlider.minimumValue = 0.5
        constantSizeSlider.maximumValue = 50
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
        distributionSectionLabel.text = "Size Range & Distribution"
        distributionSectionLabel.font = .boldSystemFont(ofSize: 14)
        randomModeContainer.addArrangedSubview(distributionSectionLabel)

        let minRow = makeSliderValueRow(title: "Min Size", value: minSize, min: 0.5, max: 25, action: #selector(minSizeChanged))
        minSizeSlider = minRow.slider
        minSizeLabel = minRow.valueLabel
        randomModeContainer.addArrangedSubview(minRow.container)

        let maxRow = makeSliderValueRow(title: "Max Size", value: maxSize, min: 0.5, max: 50, action: #selector(maxSizeChanged))
        maxSizeSlider = maxRow.slider
        maxSizeLabel = maxRow.valueLabel
        randomModeContainer.addArrangedSubview(maxRow.container)

        distributionEditor = DistributionEditorView(distribution: distribution)
        distributionEditor.translatesAutoresizingMaskIntoConstraints = false
        distributionEditor.heightAnchor.constraint(equalToConstant: 150).isActive = true
        distributionEditor.onDistributionChanged = { [weak self] newDist in
            self?.distribution = newDist
        }
        randomModeContainer.addArrangedSubview(distributionEditor)

        let presetLabel = UILabel()
        presetLabel.translatesAutoresizingMaskIntoConstraints = false
        presetLabel.text = "Presets"
        presetLabel.font = .boldSystemFont(ofSize: 14)
        randomModeContainer.addArrangedSubview(presetLabel)

        presetStackView = UIStackView()
        presetStackView.translatesAutoresizingMaskIntoConstraints = false
        presetStackView.axis = .vertical
        presetStackView.spacing = 8
        randomModeContainer.addArrangedSubview(presetStackView)
        
        for preset in SizeDistributionPreset.allCases {
            let button = UIButton(type: .system)
            button.setTitle(preset.displayName, for: .normal)
            button.addTarget(self, action: #selector(presetTapped(_:)), for: .touchUpInside)
            button.tag = preset.rawValue
            button.titleLabel?.font = .systemFont(ofSize: 14)
            presetStackView.addArrangedSubview(button)
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
        constantSize = min(max(value, 0.5), 50)
        constantSizeSlider.value = constantSize
        constantSizeField.text = String(format: "%.1f", constantSize)
    }
    
    @objc private func minSizeChanged() {
        minSize = minSizeSlider.value
        minSizeLabel.text = String(format: "%.1f", minSize)
        if minSize > maxSize {
            maxSize = minSize
            maxSizeSlider.value = maxSize
            maxSizeLabel.text = String(format: "%.1f", maxSize)
        }
    }
    
    @objc private func maxSizeChanged() {
        maxSize = maxSizeSlider.value
        maxSizeLabel.text = String(format: "%.1f", maxSize)
        if maxSize < minSize {
            minSize = maxSize
            minSizeSlider.value = minSize
            minSizeLabel.text = String(format: "%.1f", minSize)
        }
    }
    
    @objc private func presetTapped(_ sender: UIButton) {
        let preset = SizeDistributionPreset(rawValue: sender.tag) ?? .gaussian
        distribution.applyPreset(preset)
        distributionEditor.distribution = distribution
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
            minSizeLabel.text = String(format: "%.1f", minSize)
            maxSizeLabel.text = String(format: "%.1f", maxSize)
        }
    }
    
    func applyConfiguration() {
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
        let valueLabel: UILabel
    }

    private func makeSliderValueRow(title: String, value: Float, min: Float, max: Float, action: Selector) -> SliderValueRow {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 4

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = .systemFont(ofSize: 12)
        container.addArrangedSubview(label)

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(row)

        let newSlider = UISlider()
        newSlider.translatesAutoresizingMaskIntoConstraints = false
        newSlider.minimumValue = min
        newSlider.maximumValue = max
        newSlider.value = value
        newSlider.addTarget(self, action: action, for: .valueChanged)
        row.addArrangedSubview(newSlider)

        let newValueLabel = UILabel()
        newValueLabel.translatesAutoresizingMaskIntoConstraints = false
        newValueLabel.text = String(format: "%.1f", value)
        newValueLabel.font = .systemFont(ofSize: 12)
        newValueLabel.textAlignment = .center
        newValueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        row.addArrangedSubview(newValueLabel)

        return SliderValueRow(container: container, slider: newSlider, valueLabel: newValueLabel)
    }
}
