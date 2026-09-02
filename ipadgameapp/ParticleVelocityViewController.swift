//
//  ParticleVelocitySettingsViewController.swift
//

import UIKit

final class ParticleVelocityViewController: UIViewController {

    var renderer: Renderer!

    private var velocityMode: ParticleSizeMode = .constant
    private var constantVelocity: Float = 0.04
    private var minVelocity: Float = 0.02
    private var maxVelocity: Float = 0.08
    private var velocitySpectrumVariancePercent: Float = 50.0
    private var selectedPreset: SizeDistributionPreset = .flat
    private var distribution: SizeDistribution = SizeDistribution()

    private var velocityModeControl: UISegmentedControl!
    private var varianceSlider: UISlider!
    private var varianceField: UITextField!
    private var varianceContainer: UIStackView!

    private var constantModeContainer: UIStackView!
    private var constantVelocitySlider: UISlider!
    private var constantVelocityField: UITextField!

    private var randomModeContainer: UIStackView!
    private var minVelocitySlider: UISlider!
    private var maxVelocitySlider: UISlider!
    private var minVelocityField: UITextField!
    private var maxVelocityField: UITextField!

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

        let isPhone = traitCollection.userInterfaceIdiom == .phone

        velocityMode = renderer.particleVelocityMode
        constantVelocity = renderer.constantParticleVelocity
        minVelocity = renderer.minVelocityRange
        maxVelocity = renderer.maxVelocityRange
        velocitySpectrumVariancePercent = renderer.velocitySpectrumVariancePercent
        selectedPreset = renderer.velocityDistributionPreset
        distribution = renderer.velocityDistribution

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

        let modeLabel = UILabel()
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modeLabel.text = "Velocity Mode"
        modeLabel.font = .boldSystemFont(ofSize: 16)
        mainStack.addArrangedSubview(modeLabel)

        velocityModeControl = UISegmentedControl(items: ParticleSizeMode.allCases.map(\.displayName))
        velocityModeControl.translatesAutoresizingMaskIntoConstraints = false
        velocityModeControl.selectedSegmentIndex = velocityMode.rawValue
        velocityModeControl.addTarget(self, action: #selector(velocityModeChanged), for: .valueChanged)
        mainStack.addArrangedSubview(velocityModeControl)

        constantModeContainer = UIStackView()
        constantModeContainer.axis = .vertical
        constantModeContainer.spacing = 8
        mainStack.addArrangedSubview(constantModeContainer)

        let constantRow = UIStackView()
        constantRow.axis = isPhone ? .vertical : .horizontal
        constantRow.spacing = 12
        constantRow.alignment = isPhone ? .fill : .center
        constantRow.translatesAutoresizingMaskIntoConstraints = false
        constantModeContainer.addArrangedSubview(constantRow)

        let constantLabel = UILabel()
        constantLabel.translatesAutoresizingMaskIntoConstraints = false
        constantLabel.text = "Single Velocity"
        constantLabel.font = .systemFont(ofSize: 13, weight: .medium)
        if !isPhone {
            constantLabel.widthAnchor.constraint(equalToConstant: 96).isActive = true
        }

        constantVelocitySlider = UISlider()
        constantVelocitySlider.translatesAutoresizingMaskIntoConstraints = false
        constantVelocitySlider.minimumValue = 0.005
        constantVelocitySlider.maximumValue = 0.20
        constantVelocitySlider.value = constantVelocity
        constantVelocitySlider.addTarget(self, action: #selector(constantVelocityChanged), for: .valueChanged)

        constantVelocityField = UITextField()
        constantVelocityField.translatesAutoresizingMaskIntoConstraints = false
        constantVelocityField.borderStyle = .roundedRect
        constantVelocityField.keyboardType = .decimalPad
        constantVelocityField.textAlignment = .center
        constantVelocityField.text = String(format: "%.3f", constantVelocity)
        constantVelocityField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        constantVelocityField.addAction(UIAction { [weak self] _ in
            self?.constantVelocityEdited()
        }, for: .editingDidEnd)

        if isPhone {
            let valueRow = UIStackView()
            valueRow.axis = .horizontal
            valueRow.spacing = 12
            valueRow.alignment = .center
            valueRow.addArrangedSubview(constantVelocitySlider)
            valueRow.addArrangedSubview(constantVelocityField)
            constantRow.addArrangedSubview(constantLabel)
            constantRow.addArrangedSubview(valueRow)
        } else {
            constantRow.addArrangedSubview(constantLabel)
            constantRow.addArrangedSubview(constantVelocitySlider)
            constantRow.addArrangedSubview(constantVelocityField)
        }

        randomModeContainer = UIStackView()
        randomModeContainer.axis = .vertical
        randomModeContainer.spacing = 10
        mainStack.addArrangedSubview(randomModeContainer)

        let distributionSectionLabel = UILabel()
        distributionSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        distributionSectionLabel.text = "Velocity Range & Spectrum"
        distributionSectionLabel.font = .boldSystemFont(ofSize: 14)
        randomModeContainer.addArrangedSubview(distributionSectionLabel)

        let minRow = makeSliderValueRow(title: "Min Velocity", value: minVelocity, min: 0.005, max: 0.15, action: #selector(minVelocityChanged))
        minVelocitySlider = minRow.slider
        minVelocityField = minRow.valueField
        randomModeContainer.addArrangedSubview(minRow.container)

        let maxRow = makeSliderValueRow(title: "Max Velocity", value: maxVelocity, min: 0.01, max: 0.20, action: #selector(maxVelocityChanged))
        maxVelocitySlider = maxRow.slider
        maxVelocityField = maxRow.valueField
        randomModeContainer.addArrangedSubview(maxRow.container)

        minVelocityField.addAction(UIAction { [weak self] _ in
            self?.minVelocityEdited()
        }, for: .editingDidEnd)

        maxVelocityField.addAction(UIAction { [weak self] _ in
            self?.maxVelocityEdited()
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

        let varianceRow = makeSliderValueRow(title: "Variance", value: velocitySpectrumVariancePercent, min: 0, max: 100, action: #selector(velocityVarianceChanged))
        varianceSlider = varianceRow.slider
        varianceField = varianceRow.valueField
        varianceContainer = varianceRow.container
        randomModeContainer.addArrangedSubview(varianceContainer)
        varianceField.addAction(UIAction { [weak self] _ in
            self?.velocityVarianceEdited()
        }, for: .editingDidEnd)

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

            constantVelocitySlider.heightAnchor.constraint(equalToConstant: 31)
        ])

        updateUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePresetButtonLayout()
    }

    @objc private func velocityModeChanged() {
        velocityMode = ParticleSizeMode(rawValue: velocityModeControl.selectedSegmentIndex) ?? .constant
        updateUI()
    }

    @objc private func velocityVarianceChanged() {
        velocitySpectrumVariancePercent = varianceSlider.value
        varianceField.text = String(format: "%.1f", velocitySpectrumVariancePercent)
        distribution.applyPreset(selectedPreset, variancePercent: velocitySpectrumVariancePercent)
        distributionEditor.distribution = distribution
    }

    private func velocityVarianceEdited() {
        guard let text = varianceField.text, let value = Float(text) else {
            varianceField.text = String(format: "%.1f", velocitySpectrumVariancePercent)
            return
        }
        velocitySpectrumVariancePercent = min(max(value, 0.0), 100.0)
        varianceSlider.value = velocitySpectrumVariancePercent
        varianceField.text = String(format: "%.1f", velocitySpectrumVariancePercent)
        distribution.applyPreset(selectedPreset, variancePercent: velocitySpectrumVariancePercent)
        distributionEditor.distribution = distribution
    }

    @objc private func constantVelocityChanged() {
        constantVelocity = constantVelocitySlider.value
        constantVelocityField.text = String(format: "%.3f", constantVelocity)
    }

    private func constantVelocityEdited() {
        guard let text = constantVelocityField.text, let value = Float(text) else {
            constantVelocityField.text = String(format: "%.3f", constantVelocity)
            return
        }
        constantVelocity = min(max(value, 0.005), 0.20)
        constantVelocitySlider.value = constantVelocity
        constantVelocityField.text = String(format: "%.3f", constantVelocity)
    }

    @objc private func minVelocityChanged() {
        minVelocity = minVelocitySlider.value
        minVelocityField.text = String(format: "%.3f", minVelocity)
        if minVelocity > maxVelocity {
            maxVelocity = minVelocity
            maxVelocitySlider.value = maxVelocity
            maxVelocityField.text = String(format: "%.3f", maxVelocity)
        }
    }

    @objc private func maxVelocityChanged() {
        maxVelocity = maxVelocitySlider.value
        maxVelocityField.text = String(format: "%.3f", maxVelocity)
        if maxVelocity < minVelocity {
            minVelocity = maxVelocity
            minVelocitySlider.value = minVelocity
            minVelocityField.text = String(format: "%.3f", minVelocity)
        }
    }

    private func minVelocityEdited() {
        guard let text = minVelocityField.text, let value = Float(text) else {
            minVelocityField.text = String(format: "%.3f", minVelocity)
            return
        }
        minVelocity = min(max(value, 0.005), 0.15)
        if minVelocity > maxVelocity {
            maxVelocity = minVelocity
            maxVelocitySlider.value = maxVelocity
            maxVelocityField.text = String(format: "%.3f", maxVelocity)
        }
        minVelocitySlider.value = minVelocity
        minVelocityField.text = String(format: "%.3f", minVelocity)
    }

    private func maxVelocityEdited() {
        guard let text = maxVelocityField.text, let value = Float(text) else {
            maxVelocityField.text = String(format: "%.3f", maxVelocity)
            return
        }
        maxVelocity = min(max(value, 0.01), 0.20)
        if maxVelocity < minVelocity {
            minVelocity = maxVelocity
            minVelocitySlider.value = minVelocity
            minVelocityField.text = String(format: "%.3f", minVelocity)
        }
        maxVelocitySlider.value = maxVelocity
        maxVelocityField.text = String(format: "%.3f", maxVelocity)
    }

    @objc private func presetTapped(_ sender: UIButton) {
        let preset = SizeDistributionPreset(rawValue: sender.tag) ?? .gaussian
        selectedPreset = preset
        distribution.applyPreset(preset, variancePercent: velocitySpectrumVariancePercent)
        distributionEditor.distribution = distribution
        updateVarianceUIVisibility()
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
        constantModeContainer.isHidden = velocityMode != .constant
        randomModeContainer.isHidden = velocityMode != .random
        updateVarianceUIVisibility()
        if velocityMode == .constant {
            constantVelocitySlider.value = constantVelocity
            constantVelocityField.text = String(format: "%.3f", constantVelocity)
        } else {
            minVelocitySlider.value = minVelocity
            maxVelocitySlider.value = maxVelocity
            minVelocityField.text = String(format: "%.3f", minVelocity)
            maxVelocityField.text = String(format: "%.3f", maxVelocity)
        }
    }

    private func updateVarianceUIVisibility() {
        varianceContainer?.isHidden = (velocityMode != .random) || (selectedPreset == .flat)
    }

    func applyConfiguration() {
        guard isViewLoaded else { return }
        renderer.setParticleVelocityMode(velocityMode)
        renderer.setVelocitySpectrumVariance(velocitySpectrumVariancePercent)
        switch velocityMode {
        case .constant:
            renderer.setConstantParticleVelocity(constantVelocity)
        case .random:
            renderer.setVelocityRange(minVelocity, maxVelocity)
            renderer.setVelocityDistribution(distribution)
            renderer.setVelocityDistributionPreset(selectedPreset)
        }
    }

    private struct SliderValueRow {
        let container: UIStackView
        let slider: UISlider
        let valueField: UITextField
    }

    private func makeSliderValueRow(title: String, value: Float, min: Float, max: Float, action: Selector) -> SliderValueRow {
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
            label.widthAnchor.constraint(equalToConstant: 96).isActive = true
        }

        let newSlider = UISlider()
        newSlider.translatesAutoresizingMaskIntoConstraints = false
        newSlider.minimumValue = min
        newSlider.maximumValue = max
        newSlider.value = value
        newSlider.addTarget(self, action: action, for: .valueChanged)

        let newValueField = UITextField()
        newValueField.translatesAutoresizingMaskIntoConstraints = false
        newValueField.borderStyle = .roundedRect
        newValueField.keyboardType = .decimalPad
        newValueField.textAlignment = .center
        newValueField.text = max <= 1.0 ? String(format: "%.3f", value) : String(format: "%.1f", value)
        newValueField.widthAnchor.constraint(equalToConstant: 72).isActive = true

        if isPhone {
            let valueRow = UIStackView()
            valueRow.axis = .horizontal
            valueRow.spacing = 12
            valueRow.alignment = .center
            valueRow.addArrangedSubview(newSlider)
            valueRow.addArrangedSubview(newValueField)
            container.addArrangedSubview(label)
            container.addArrangedSubview(valueRow)
        } else {
            container.addArrangedSubview(label)
            container.addArrangedSubview(newSlider)
            container.addArrangedSubview(newValueField)
        }

        return SliderValueRow(container: container, slider: newSlider, valueField: newValueField)
    }
}
