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
    private var constantSizeSlider: UISlider!
    private var constantSizeLabel: UILabel!
    private var distributionEditor: DistributionEditorView!
    private var minSizeSlider: UISlider!
    private var maxSizeSlider: UISlider!
    private var minSizeLabel: UILabel!
    private var maxSizeLabel: UILabel!
    private var presetStackView: UIStackView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Load current renderer settings
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
        
        // Size Mode Selection
        let sizeModeLabel = UILabel()
        sizeModeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeModeLabel.text = "Size Mode"
        sizeModeLabel.font = .boldSystemFont(ofSize: 16)
        contentView.addSubview(sizeModeLabel)
        
        sizeModeControl = UISegmentedControl(items: ParticleSizeMode.allCases.map(\.displayName))
        sizeModeControl.translatesAutoresizingMaskIntoConstraints = false
        sizeModeControl.selectedSegmentIndex = sizeMode.rawValue
        sizeModeControl.addTarget(self, action: #selector(sizeModeChanged), for: .valueChanged)
        contentView.addSubview(sizeModeControl)
        
        // Constant Size Section
        let constantSectionLabel = UILabel()
        constantSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        constantSectionLabel.text = "Constant Size"
        constantSectionLabel.font = .boldSystemFont(ofSize: 14)
        contentView.addSubview(constantSectionLabel)
        
        constantSizeSlider = UISlider()
        constantSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        constantSizeSlider.minimumValue = 0.5
        constantSizeSlider.maximumValue = 50
        constantSizeSlider.value = constantSize
        constantSizeSlider.addTarget(self, action: #selector(constantSizeChanged), for: .valueChanged)
        contentView.addSubview(constantSizeSlider)
        
        constantSizeLabel = UILabel()
        constantSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        constantSizeLabel.text = String(format: "%.1f px", constantSize)
        constantSizeLabel.font = .systemFont(ofSize: 12)
        constantSizeLabel.textAlignment = .center
        contentView.addSubview(constantSizeLabel)
        
        // Random Distribution Section
        let distributionSectionLabel = UILabel()
        distributionSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        distributionSectionLabel.text = "Size Range & Distribution"
        distributionSectionLabel.font = .boldSystemFont(ofSize: 14)
        contentView.addSubview(distributionSectionLabel)
        
        let minSizeInnerLabel = UILabel()
        minSizeInnerLabel.translatesAutoresizingMaskIntoConstraints = false
        minSizeInnerLabel.text = "Min Size"
        minSizeInnerLabel.font = .systemFont(ofSize: 12)
        contentView.addSubview(minSizeInnerLabel)
        
        minSizeSlider = UISlider()
        minSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        minSizeSlider.minimumValue = 0.5
        minSizeSlider.maximumValue = 25
        minSizeSlider.value = minSize
        minSizeSlider.addTarget(self, action: #selector(minSizeChanged), for: .valueChanged)
        contentView.addSubview(minSizeSlider)
        
        minSizeLabel = UILabel()
        minSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        minSizeLabel.text = String(format: "%.1f", minSize)
        minSizeLabel.font = .systemFont(ofSize: 12)
        minSizeLabel.textAlignment = .center
        minSizeLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        contentView.addSubview(minSizeLabel)
        
        let maxSizeInnerLabel = UILabel()
        maxSizeInnerLabel.translatesAutoresizingMaskIntoConstraints = false
        maxSizeInnerLabel.text = "Max Size"
        maxSizeInnerLabel.font = .systemFont(ofSize: 12)
        contentView.addSubview(maxSizeInnerLabel)
        
        maxSizeSlider = UISlider()
        maxSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        maxSizeSlider.minimumValue = 0.5
        maxSizeSlider.maximumValue = 50
        maxSizeSlider.value = maxSize
        maxSizeSlider.addTarget(self, action: #selector(maxSizeChanged), for: .valueChanged)
        contentView.addSubview(maxSizeSlider)
        
        maxSizeLabel = UILabel()
        maxSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        maxSizeLabel.text = String(format: "%.1f", maxSize)
        maxSizeLabel.font = .systemFont(ofSize: 12)
        maxSizeLabel.textAlignment = .center
        maxSizeLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        contentView.addSubview(maxSizeLabel)
        
        // Distribution Editor
        distributionEditor = DistributionEditorView(distribution: distribution)
        distributionEditor.translatesAutoresizingMaskIntoConstraints = false
        distributionEditor.heightAnchor.constraint(equalToConstant: 150).isActive = true
        distributionEditor.onDistributionChanged = { [weak self] newDist in
            self?.distribution = newDist
        }
        contentView.addSubview(distributionEditor)
        
        // Preset Buttons
        let presetLabel = UILabel()
        presetLabel.translatesAutoresizingMaskIntoConstraints = false
        presetLabel.text = "Presets"
        presetLabel.font = .boldSystemFont(ofSize: 14)
        contentView.addSubview(presetLabel)
        
        presetStackView = UIStackView()
        presetStackView.translatesAutoresizingMaskIntoConstraints = false
        presetStackView.axis = .vertical
        presetStackView.spacing = 8
        contentView.addSubview(presetStackView)
        
        for preset in SizeDistributionPreset.allCases {
            let button = UIButton(type: .system)
            button.setTitle(preset.displayName, for: .normal)
            button.addTarget(self, action: #selector(presetTapped(_:)), for: .touchUpInside)
            button.tag = preset.rawValue
            button.titleLabel?.font = .systemFont(ofSize: 14)
            presetStackView.addArrangedSubview(button)
        }
        
        // Layout constraints
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
            
            // Size Mode
            sizeModeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            sizeModeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            sizeModeControl.topAnchor.constraint(equalTo: sizeModeLabel.bottomAnchor, constant: 8),
            sizeModeControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            sizeModeControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Constant Size Section
            constantSectionLabel.topAnchor.constraint(equalTo: sizeModeControl.bottomAnchor, constant: 20),
            constantSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            constantSizeSlider.topAnchor.constraint(equalTo: constantSectionLabel.bottomAnchor, constant: 8),
            constantSizeSlider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            constantSizeSlider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            constantSizeLabel.topAnchor.constraint(equalTo: constantSizeSlider.bottomAnchor, constant: 4),
            constantSizeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            constantSizeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Distribution Section
            distributionSectionLabel.topAnchor.constraint(equalTo: constantSizeLabel.bottomAnchor, constant: 20),
            distributionSectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            minSizeInnerLabel.topAnchor.constraint(equalTo: distributionSectionLabel.bottomAnchor, constant: 12),
            minSizeInnerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            minSizeSlider.topAnchor.constraint(equalTo: minSizeInnerLabel.bottomAnchor, constant: 4),
            minSizeSlider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            minSizeSlider.trailingAnchor.constraint(equalTo: minSizeLabel.leadingAnchor, constant: -8),
            
            minSizeLabel.centerYAnchor.constraint(equalTo: minSizeSlider.centerYAnchor),
            minSizeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            maxSizeInnerLabel.topAnchor.constraint(equalTo: minSizeSlider.bottomAnchor, constant: 12),
            maxSizeInnerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            maxSizeSlider.topAnchor.constraint(equalTo: maxSizeInnerLabel.bottomAnchor, constant: 4),
            maxSizeSlider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            maxSizeSlider.trailingAnchor.constraint(equalTo: maxSizeLabel.leadingAnchor, constant: -8),
            
            maxSizeLabel.centerYAnchor.constraint(equalTo: maxSizeSlider.centerYAnchor),
            maxSizeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            distributionEditor.topAnchor.constraint(equalTo: maxSizeSlider.bottomAnchor, constant: 16),
            distributionEditor.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            distributionEditor.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            presetLabel.topAnchor.constraint(equalTo: distributionEditor.bottomAnchor, constant: 16),
            presetLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            
            presetStackView.topAnchor.constraint(equalTo: presetLabel.bottomAnchor, constant: 8),
            presetStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            presetStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            presetStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
        
        updateUI()
    }
    
    @objc private func sizeModeChanged() {
        sizeMode = ParticleSizeMode(rawValue: sizeModeControl.selectedSegmentIndex) ?? .constant
        updateUI()
    }
    
    @objc private func constantSizeChanged() {
        constantSize = constantSizeSlider.value
        constantSizeLabel.text = String(format: "%.1f px", constantSize)
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
        constantSizeSlider.isEnabled = (sizeMode == .constant)
        minSizeSlider.isEnabled = (sizeMode == .random)
        maxSizeSlider.isEnabled = (sizeMode == .random)
        distributionEditor.isUserInteractionEnabled = (sizeMode == .random)
        
        presetStackView.arrangedSubviews.forEach { view in
            if let button = view as? UIButton {
                button.isEnabled = (sizeMode == .random)
            }
        }
    }
    
    func applyConfiguration() {
        renderer.setParticleSizeMode(sizeMode)
        renderer.setConstantParticleSize(constantSize)
        renderer.setSizeRange(minSize, maxSize)
        renderer.setSizeDistribution(distribution)
    }
}
