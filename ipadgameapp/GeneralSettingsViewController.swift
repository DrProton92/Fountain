//
//  GeneralSettingsViewController.swift
//  ipadgameapp
//
//  Created by GitHub Copilot on 8/20/26.
//

import UIKit

final class GeneralSettingsViewController: UIViewController {
    
    var renderer: Renderer!
    private var particleCount: Int = 10000
    private let minParticleCount = 100
    private var launchAngleDegrees: Float = 0.0
    private var angleVarianceDegrees: Float = 12.0
    private var velocityVariancePercent: Float = 0.0

    private var countSlider: UISlider!
    private var countField: UITextField!
    private var launchAngleSlider: UISlider!
    private var launchAngleField: UITextField!
    private var angleVarianceSlider: UISlider!
    private var angleVarianceField: UITextField!
    private var velocityVarianceSlider: UISlider!
    private var velocityVarianceField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        particleCount = renderer.activeParticleCount
        launchAngleDegrees = renderer.launchAngleDegrees
        angleVarianceDegrees = renderer.angleVarianceDegrees
        velocityVariancePercent = renderer.velocityVariancePercent
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
        mainStack.spacing = 12
        contentView.addSubview(mainStack)

        let countLabel = UILabel()
        countLabel.text = "Particle Count"
        countLabel.font = .boldSystemFont(ofSize: 16)
        mainStack.addArrangedSubview(countLabel)

        let countRow = makeSliderValueRow(title: "Count", value: Float(particleCount), min: 0, max: 1, isLogSlider: true)
        countSlider = countRow.slider
        countField = countRow.field
        countSlider.value = sliderValue(forParticleCount: particleCount)
        countField.text = "\(particleCount)"
        mainStack.addArrangedSubview(countRow.container)

        let launchLabel = UILabel()
        launchLabel.text = "Launch"
        launchLabel.font = .boldSystemFont(ofSize: 16)
        mainStack.addArrangedSubview(launchLabel)

        let launchRow = makeSliderValueRow(title: "Launch Angle", value: launchAngleDegrees, min: 0, max: 90, isLogSlider: false)
        launchAngleSlider = launchRow.slider
        launchAngleField = launchRow.field
        mainStack.addArrangedSubview(launchRow.container)

        let coneRow = makeSliderValueRow(title: "Angle Variance", value: angleVarianceDegrees, min: 0, max: 90, isLogSlider: false)
        angleVarianceSlider = coneRow.slider
        angleVarianceField = coneRow.field
        mainStack.addArrangedSubview(coneRow.container)

        let velocityRow = makeSliderValueRow(title: "Velocity Variance", value: velocityVariancePercent, min: 0, max: 100, isLogSlider: false)
        velocityVarianceSlider = velocityRow.slider
        velocityVarianceField = velocityRow.field
        mainStack.addArrangedSubview(velocityRow.container)

        wireEvents()

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

            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    func applyConfiguration() {
        renderer.setParticleCount(particleCount)
        renderer.setLaunchAngle(launchAngleDegrees)
        renderer.setAngleVariance(angleVarianceDegrees)
        renderer.setVelocityVariance(velocityVariancePercent)
    }

    private func wireEvents() {
        countSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let count = self.particleCount(forSliderValue: self.countSlider.value)
            self.countField.text = "\(count)"
            self.particleCount = count
        }, for: .valueChanged)

        countField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            guard let text = self.countField.text, let entered = Int(text) else {
                self.countField.text = "\(self.particleCount)"
                return
            }
            let clamped = min(max(entered, self.minParticleCount), maxParticleCount)
            self.particleCount = clamped
            self.countField.text = "\(clamped)"
            self.countSlider.value = self.sliderValue(forParticleCount: clamped)
        }, for: .editingDidEnd)

        launchAngleSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.launchAngleDegrees = self.launchAngleSlider.value
            self.launchAngleField.text = String(format: "%.1f", self.launchAngleDegrees)
        }, for: .valueChanged)

        launchAngleField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.launchAngleDegrees = self.sanitizeAngleField(self.launchAngleField, fallback: self.launchAngleDegrees)
            self.launchAngleSlider.value = self.launchAngleDegrees
        }, for: .editingDidEnd)

        angleVarianceSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.angleVarianceDegrees = self.angleVarianceSlider.value
            self.angleVarianceField.text = String(format: "%.1f", self.angleVarianceDegrees)
        }, for: .valueChanged)

        angleVarianceField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.angleVarianceDegrees = self.sanitizeAngleField(self.angleVarianceField, fallback: self.angleVarianceDegrees)
            self.angleVarianceSlider.value = self.angleVarianceDegrees
        }, for: .editingDidEnd)

        velocityVarianceSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.velocityVariancePercent = self.velocityVarianceSlider.value
            self.velocityVarianceField.text = String(format: "%.1f", self.velocityVariancePercent)
        }, for: .valueChanged)

        velocityVarianceField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.velocityVariancePercent = self.sanitizePercentField(self.velocityVarianceField, fallback: self.velocityVariancePercent)
            self.velocityVarianceSlider.value = self.velocityVariancePercent
        }, for: .editingDidEnd)
    }

    private func sanitizeAngleField(_ field: UITextField, fallback: Float) -> Float {
        guard let text = field.text, let value = Float(text) else {
            field.text = String(format: "%.1f", fallback)
            return fallback
        }
        let clamped = max(0.0, min(value, 90.0))
        field.text = String(format: "%.1f", clamped)
        return clamped
    }

    private func sanitizePercentField(_ field: UITextField, fallback: Float) -> Float {
        guard let text = field.text, let value = Float(text) else {
            field.text = String(format: "%.1f", fallback)
            return fallback
        }
        let clamped = max(0.0, min(value, 100.0))
        field.text = String(format: "%.1f", clamped)
        return clamped
    }

    private struct SliderValueRow {
        let container: UIStackView
        let slider: UISlider
        let field: UITextField
    }

    private func makeSliderValueRow(title: String, value: Float, min: Float, max: Float, isLogSlider: Bool) -> SliderValueRow {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true
        row.addArrangedSubview(label)

        let slider = UISlider()
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.heightAnchor.constraint(equalToConstant: 31).isActive = true
        row.addArrangedSubview(slider)

        let field = UITextField()
        field.borderStyle = .roundedRect
        field.keyboardType = isLogSlider ? .numberPad : .decimalPad
        field.textAlignment = .center
        field.text = isLogSlider ? "\(Int(value))" : String(format: "%.1f", value)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 96).isActive = true
        row.addArrangedSubview(field)

        return SliderValueRow(container: row, slider: slider, field: field)
    }

    private func particleCount(forSliderValue value: Float) -> Int {
        let minLog = log10(Float(minParticleCount))
        let maxLog = log10(Float(maxParticleCount))
        let logValue = minLog + (maxLog - minLog) * value
        let raw = Int(pow(10, logValue).rounded())
        return min(max(raw, minParticleCount), maxParticleCount)
    }
    
    private func sliderValue(forParticleCount count: Int) -> Float {
        let minLog = log10(Float(minParticleCount))
        let maxLog = log10(Float(maxParticleCount))
        let clamped = Float(min(max(count, minParticleCount), maxParticleCount))
        return (log10(clamped) - minLog) / (maxLog - minLog)
    }
}
