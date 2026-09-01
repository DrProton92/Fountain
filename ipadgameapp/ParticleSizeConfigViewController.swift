//
//  ParticleSizeConfigView.swift
//  ipadgameapp
//
//  Created by Dave Schmid on 8/19/26.
//

import UIKit


/// View controller for particle size configuration
class ParticleSizeConfigViewController: UIViewController {
    
    var renderer: Renderer!
    
    private var sizeMode: ParticleSizeMode = .constant
    private var constantSize: Float = 5.0
    private var minSize: Float = 5.0
    private var maxSize: Float = 30.0
    private var sizeSpectrumVariancePercent: Float = 50.0
    private var distribution: SizeDistribution = SizeDistribution()
    private var selectedPreset: SizeDistributionPreset = .flat
    
    private var sizeModeControl: UISegmentedControl!
    private var constantModeContainer: UIStackView!
    private var constantSizeSlider: UISlider!
    private var constantSizeField: UITextField!
    private var randomModeContainer: UIStackView!
    private var minSizeSlider: UISlider!
    private var maxSizeSlider: UISlider!
    private var minSizeField: UITextField!
    private var maxSizeField: UITextField!
    private var sizeVarianceSlider: UISlider!
    private var sizeVarianceField: UITextField!
    private var sizeVarianceContainer: UIStackView!
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
        
        sizeMode = renderer.particleSizeMode
        constantSize = renderer.constantParticleSize
        minSize = renderer.minSizeRange
        maxSize = renderer.maxSizeRange
        sizeSpectrumVariancePercent = renderer.sizeSpectrumVariancePercent
        distribution = renderer.sizeDistribution
        selectedPreset = renderer.sizeDistributionPreset
        
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
        constantRow.axis = isPhone ? .vertical : .horizontal
        constantRow.spacing = 12
        constantRow.alignment = isPhone ? .fill : .center
        constantRow.translatesAutoresizingMaskIntoConstraints = false
        constantModeContainer.addArrangedSubview(constantRow)

        let constantLabel = UILabel()
        constantLabel.translatesAutoresizingMaskIntoConstraints = false
        constantLabel.text = "Single Size"
        constantLabel.font = .systemFont(ofSize: 13, weight: .medium)
        if !isPhone {
            constantLabel.widthAnchor.constraint(equalToConstant: 96).isActive = true
        }

        constantSizeSlider = UISlider()
        constantSizeSlider.translatesAutoresizingMaskIntoConstraints = false
        constantSizeSlider.minimumValue = 0.5
        constantSizeSlider.maximumValue = 30
        constantSizeSlider.value = constantSize
        constantSizeSlider.addTarget(self, action: #selector(constantSizeChanged), for: .valueChanged)

        constantSizeField = UITextField()
        constantSizeField.translatesAutoresizingMaskIntoConstraints = false
        constantSizeField.borderStyle = .roundedRect
        constantSizeField.keyboardType = .decimalPad
        constantSizeField.textAlignment = .center
        constantSizeField.text = String(format: "%.1f", constantSize)
        constantSizeField.widthAnchor.constraint(equalToConstant: 72).isActive = true
        constantSizeField.addAction(UIAction { [weak self] _ in
            self?.constantSizeEdited()
        }, for: .editingDidEnd)

        if isPhone {
            let valueRow = UIStackView()
            valueRow.axis = .horizontal
            valueRow.spacing = 12
            valueRow.alignment = .center
            valueRow.addArrangedSubview(constantSizeSlider)
            valueRow.addArrangedSubview(constantSizeField)
            constantRow.addArrangedSubview(constantLabel)
            constantRow.addArrangedSubview(valueRow)
        } else {
            constantRow.addArrangedSubview(constantLabel)
            constantRow.addArrangedSubview(constantSizeSlider)
            constantRow.addArrangedSubview(constantSizeField)
        }
        
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

        let varianceRow = makeSliderValueRow(title: "Variance", value: sizeSpectrumVariancePercent, min: 0, max: 100, action: #selector(sizeVarianceChanged))
        sizeVarianceSlider = varianceRow.slider
        sizeVarianceField = varianceRow.valueField
        sizeVarianceContainer = varianceRow.container
        randomModeContainer.addArrangedSubview(sizeVarianceContainer)
        sizeVarianceField.addAction(UIAction { [weak self] _ in
            self?.sizeVarianceEdited()
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

    @objc private func sizeVarianceChanged() {
        sizeSpectrumVariancePercent = sizeVarianceSlider.value
        sizeVarianceField.text = String(format: "%.1f", sizeSpectrumVariancePercent)
        distribution.applyPreset(selectedPreset, variancePercent: sizeSpectrumVariancePercent)
        distributionEditor.distribution = distribution
    }

    private func sizeVarianceEdited() {
        guard let text = sizeVarianceField.text, let value = Float(text) else {
            sizeVarianceField.text = String(format: "%.1f", sizeSpectrumVariancePercent)
            return
        }
        sizeSpectrumVariancePercent = min(max(value, 0.0), 100.0)
        sizeVarianceSlider.value = sizeSpectrumVariancePercent
        sizeVarianceField.text = String(format: "%.1f", sizeSpectrumVariancePercent)
        distribution.applyPreset(selectedPreset, variancePercent: sizeSpectrumVariancePercent)
        distributionEditor.distribution = distribution
    }
    
    @objc private func presetTapped(_ sender: UIButton) {
        let preset = SizeDistributionPreset(rawValue: sender.tag) ?? .gaussian
        selectedPreset = preset
        distribution.applyPreset(preset, variancePercent: sizeSpectrumVariancePercent)
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
        constantModeContainer.isHidden = sizeMode != .constant
        randomModeContainer.isHidden = sizeMode != .random
        updateVarianceUIVisibility()
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

    private func updateVarianceUIVisibility() {
        sizeVarianceContainer?.isHidden = (sizeMode != .random) || (selectedPreset == .flat)
    }
    
    func applyConfiguration() {
        guard isViewLoaded else { return }
        renderer.setParticleSizeMode(sizeMode)
        renderer.setSizeSpectrumVariance(sizeSpectrumVariancePercent)
        switch sizeMode {
        case .constant:
            renderer.setConstantParticleSize(constantSize)
        case .random:
            renderer.setSizeRange(minSize, maxSize)
            renderer.setSizeDistribution(distribution)
            renderer.setSizeDistributionPreset(selectedPreset)
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
        newValueField.text = String(format: "%.1f", value)
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
