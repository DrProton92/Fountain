
import UIKit

final class CameraViewController: UIViewController {

    var renderer: Renderer!

    private var cameraControlMode: CameraControlMode = .touchControlled
    private var cameraMotionModel: CameraMotionModel = .orbit
    private var cameraInclinationDegrees: Float = 22.0

    private var modeControl: UISegmentedControl!
    private var modelContainer: UIStackView!
    private var modelControl: UISegmentedControl!
    private var inclinationSlider: UISlider!
    private var inclinationField: UITextField!

    override func viewDidLoad() {
        super.viewDidLoad()

        cameraControlMode = renderer.cameraControlMode
        cameraMotionModel = renderer.cameraMotionModel
        cameraInclinationDegrees = renderer.cameraInclinationDegrees

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

        let modeLabel = UILabel()
        modeLabel.text = "Motion Mode"
        modeLabel.font = .boldSystemFont(ofSize: 16)
        mainStack.addArrangedSubview(modeLabel)

        modeControl = UISegmentedControl(items: CameraControlMode.allCases.map(\.displayName))
        modeControl.selectedSegmentIndex = cameraControlMode.rawValue
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        mainStack.addArrangedSubview(modeControl)

        modelContainer = UIStackView()
        modelContainer.axis = .vertical
        modelContainer.spacing = 8
        mainStack.addArrangedSubview(modelContainer)

        let modelLabel = UILabel()
        modelLabel.text = "Motion Model"
        modelLabel.font = .boldSystemFont(ofSize: 14)
        modelContainer.addArrangedSubview(modelLabel)

        modelControl = UISegmentedControl(items: CameraMotionModel.allCases.map(\.displayName))
        modelControl.selectedSegmentIndex = cameraMotionModel.rawValue
        modelControl.addTarget(self, action: #selector(modelChanged), for: .valueChanged)
        modelContainer.addArrangedSubview(modelControl)

        let inclinationRow = makeSliderValueRow(title: "Inclination", value: cameraInclinationDegrees, min: 0, max: 85)
        inclinationSlider = inclinationRow.slider
        inclinationField = inclinationRow.field
        modelContainer.addArrangedSubview(inclinationRow.container)

        inclinationSlider.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.cameraInclinationDegrees = self.inclinationSlider.value
            self.inclinationField.text = String(format: "%.1f", self.cameraInclinationDegrees)
        }, for: .valueChanged)

        inclinationField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.cameraInclinationDegrees = self.sanitizeInclinationField(self.inclinationField, fallback: self.cameraInclinationDegrees)
            self.inclinationSlider.value = self.cameraInclinationDegrees
        }, for: .editingDidEnd)

        let helperLabel = UILabel()
        helperLabel.text = "Camera motion animates the eye position and always looks at the emitter origin."
        helperLabel.font = .systemFont(ofSize: 12)
        helperLabel.textColor = .secondaryLabel
        helperLabel.numberOfLines = 0
        modelContainer.addArrangedSubview(helperLabel)

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

        updateUI()
    }

    @objc private func modeChanged() {
        cameraControlMode = CameraControlMode(rawValue: modeControl.selectedSegmentIndex) ?? .touchControlled
        updateUI()
    }

    @objc private func modelChanged() {
        cameraMotionModel = CameraMotionModel(rawValue: modelControl.selectedSegmentIndex) ?? .orbit
    }

    private func updateUI() {
        modelContainer.isHidden = cameraControlMode != .motionModel
    }

    func applyConfiguration() {
        renderer.setCameraControlMode(cameraControlMode)
        renderer.setCameraMotionModel(cameraMotionModel)
        renderer.setCameraInclination(cameraInclinationDegrees)
    }

    private func sanitizeInclinationField(_ field: UITextField, fallback: Float) -> Float {
        guard let text = field.text, let value = Float(text) else {
            field.text = String(format: "%.1f", fallback)
            return fallback
        }
        let clamped = max(0.0, min(value, 85.0))
        field.text = String(format: "%.1f", clamped)
        return clamped
    }

    private struct SliderValueRow {
        let container: UIStackView
        let slider: UISlider
        let field: UITextField
    }

    private func makeSliderValueRow(title: String, value: Float, min: Float, max: Float) -> SliderValueRow {
        let isPhone = traitCollection.userInterfaceIdiom == .phone

        let container = UIStackView()
        container.axis = isPhone ? .vertical : .horizontal
        container.spacing = 12
        container.alignment = isPhone ? .fill : .center

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
        field.keyboardType = .decimalPad
        field.textAlignment = .center
        field.text = String(format: "%.1f", value)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 72).isActive = true

        if isPhone {
            let valueRow = UIStackView()
            valueRow.axis = .horizontal
            valueRow.spacing = 12
            valueRow.alignment = .center
            valueRow.addArrangedSubview(slider)
            valueRow.addArrangedSubview(field)
            container.addArrangedSubview(label)
            container.addArrangedSubview(valueRow)
        } else {
            container.addArrangedSubview(label)
            container.addArrangedSubview(slider)
            container.addArrangedSubview(field)
        }

        return SliderValueRow(container: container, slider: slider, field: field)
    }
}
