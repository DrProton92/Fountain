import UIKit

final class GeneralSettingsViewController: UIViewController {
    
    var renderer: Renderer!
    private var particleCount: Int = 10000
    private let minParticleCount = 100
    private var launchAngleDegrees: Float = 0.0
    private var angleVarianceDegrees: Float = 12.0
    private var trailsEnabled: Bool = false
    private var trailLength: Float = 2.0
    private var showAxis: Bool = false
    
    private var countSlider: UISlider!
    private var countField: UITextField!
    private var launchAngleSlider: UISlider!
    private var launchAngleField: UITextField!
    private var angleVarianceSlider: UISlider!
    private var angleVarianceField: UITextField!
    private var trailsSwitch: UISwitch!
    private var axisSwitch: UISwitch!
    private var trailLengthRowContainer: UIStackView!
    private var trailLengthSlider: UISlider!
    private var trailLengthField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        particleCount = renderer.activeParticleCount
        launchAngleDegrees = renderer.launchAngleDegrees
        angleVarianceDegrees = renderer.angleVarianceDegrees
        trailsEnabled = renderer.trailsEnabled
        trailLength = renderer.trailLength
        showAxis = renderer.showAxis
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

        let axisSwitchToggleRow = UIStackView()
        axisSwitchToggleRow.axis = .horizontal
        axisSwitchToggleRow.spacing = 12
        axisSwitchToggleRow.alignment = .center
        let axisSwitchLabel = UILabel()
        axisSwitchLabel.text = "Show Axis"
        axisSwitchLabel.font = .systemFont(ofSize: 13, weight: .medium)
        axisSwitch = UISwitch()
        axisSwitch.isOn = showAxis
        axisSwitchToggleRow.addArrangedSubview(axisSwitchLabel)
        axisSwitchToggleRow.addArrangedSubview(UIView())
        axisSwitchToggleRow.addArrangedSubview(axisSwitch)
        mainStack.addArrangedSubview(axisSwitchToggleRow)

        let trailsLabel = UILabel()
        trailsLabel.text = "Trails"
        trailsLabel.font = .boldSystemFont(ofSize: 16)
        mainStack.addArrangedSubview(trailsLabel)

        let trailsToggleRow = UIStackView()
        trailsToggleRow.axis = .horizontal
        trailsToggleRow.spacing = 12
        trailsToggleRow.alignment = .center
        let trailsToggleLabel = UILabel()
        trailsToggleLabel.text = "Enable Trails"
        trailsToggleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        trailsSwitch = UISwitch()
        trailsSwitch.isOn = trailsEnabled
        trailsToggleRow.addArrangedSubview(trailsToggleLabel)
        trailsToggleRow.addArrangedSubview(UIView())
        trailsToggleRow.addArrangedSubview(trailsSwitch)
        mainStack.addArrangedSubview(trailsToggleRow)

        let trailLengthRow = makeSliderValueRow(title: "Trail Length", value: trailLength, min: 1, max: Float(maxTrailHistorySamples), isLogSlider: false)
        trailLengthRowContainer = trailLengthRow.container
        trailLengthSlider = trailLengthRow.slider
        trailLengthField = trailLengthRow.field
        mainStack.addArrangedSubview(trailLengthRowContainer)
        trailLengthRowContainer.isHidden = !trailsEnabled

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
        renderer.setTrailsEnabled(trailsEnabled)
        renderer.setTrailLength(trailLength)
        renderer.setShowAxis(showAxis)
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

        trailsSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.trailsEnabled = self.trailsSwitch.isOn
            self.trailLengthRowContainer.isHidden = !self.trailsEnabled
        }, for: .valueChanged)

        axisSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.showAxis = self.axisSwitch.isOn
            self.renderer.setShowAxis(self.showAxis)
        }, for: .valueChanged)

        trailLengthSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.trailLength = round(self.trailLengthSlider.value)
            self.trailLengthSlider.value = self.trailLength
            self.trailLengthField.text = String(format: "%.1f", self.trailLength)
        }, for: .valueChanged)

        trailLengthField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.trailLength = self.sanitizeTrailLengthField(self.trailLengthField, fallback: self.trailLength)
            self.trailLengthSlider.value = self.trailLength
        }, for: .editingDidEnd)
    }

    private func sanitizeTrailLengthField(_ field: UITextField, fallback: Float) -> Float {
        guard let text = field.text, let value = Float(text) else {
            field.text = String(format: "%.1f", fallback)
            return fallback
        }
        let clamped = round(max(1.0, min(value, Float(maxTrailHistorySamples))))
        field.text = String(format: "%.1f", clamped)
        return clamped
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

    private struct SliderValueRow {
        let container: UIStackView
        let slider: UISlider
        let field: UITextField
    }

    private func makeSliderValueRow(title: String, value: Float, min: Float, max: Float, isLogSlider: Bool) -> SliderValueRow {
        let isPhone = traitCollection.userInterfaceIdiom == .phone

        let row = UIStackView()
        row.axis = isPhone ? .vertical : .horizontal
        row.spacing = 12
        row.alignment = isPhone ? .fill : .center

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .medium)
        if !isPhone {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 120).isActive = true
        }

        let slider = UISlider()
        slider.minimumValue = min
        slider.maximumValue = max
        slider.value = value
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.heightAnchor.constraint(equalToConstant: 31).isActive = true

        let field = UITextField()
        field.borderStyle = .roundedRect
        field.keyboardType = isLogSlider ? .numberPad : .decimalPad
        field.textAlignment = .center
        field.text = isLogSlider ? "\(Int(value))" : String(format: "%.1f", value)
        field.translatesAutoresizingMaskIntoConstraints = false
        // Particle counts can reach eight digits, so reserve a little more
        // room for that integer field without widening decimal controls.
        field.widthAnchor.constraint(equalToConstant: isLogSlider ? 96 : 72).isActive = true

        if isPhone {
            let valueRow = UIStackView()
            valueRow.axis = .horizontal
            valueRow.spacing = 12
            valueRow.alignment = .center
            valueRow.addArrangedSubview(slider)
            valueRow.addArrangedSubview(field)
            row.addArrangedSubview(label)
            row.addArrangedSubview(valueRow)
        } else {
            row.addArrangedSubview(label)
            row.addArrangedSubview(slider)
            row.addArrangedSubview(field)
        }

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
