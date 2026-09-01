//
//  DistributionEditorView.swift
//  ipadgameapp
//
//  Created by Dave Schmid on 8/19/26.
//

import UIKit

/// A custom view for graphically editing particle size or velocity distribution
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
