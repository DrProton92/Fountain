//
//  ConfigurationViewController.swift
//  ipadgameapp
//
//  Created by Dave Schmid on 8/19/26.
//

import UIKit

enum ConfigurationCategory: Int, CaseIterable {
    case general
    case particleColor
    case particleSize
    
    var displayName: String {
        switch self {
        case .general: return "General"
        case .particleColor: return "Particle Color"
        case .particleSize: return "Particle Size"
        }
    }
}

class ConfigurationViewController: UIViewController {
    
    var renderer: Renderer!
    private var selectedCategory: ConfigurationCategory = .general
    
    // UI Components
    private var containerView: UIView!
    private var categoryTableView: UITableView!
    private var detailContainerView: UIView!
    private var currentDetailViewController: UIViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        // Setup navigation
        navigationItem.title = "Configuration"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
        
        // Setup split view
        setupSplitView()
        
        // Select first category
        selectCategory(.general)
    }
    
    private func setupSplitView() {
        // Main container
        containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)
        
        // Category table on the left
        categoryTableView = UITableView(frame: .zero, style: .plain)
        categoryTableView.translatesAutoresizingMaskIntoConstraints = false
        categoryTableView.delegate = self
        categoryTableView.dataSource = self
        categoryTableView.register(UITableViewCell.self, forCellReuseIdentifier: "CategoryCell")
        categoryTableView.backgroundColor = .secondarySystemBackground
        containerView.addSubview(categoryTableView)
        
        // Detail container on the right
        detailContainerView = UIView()
        detailContainerView.translatesAutoresizingMaskIntoConstraints = false
        detailContainerView.backgroundColor = .systemBackground
        containerView.addSubview(detailContainerView)
        
        // Layout constraints
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            categoryTableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            categoryTableView.topAnchor.constraint(equalTo: containerView.topAnchor),
            categoryTableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            categoryTableView.widthAnchor.constraint(equalToConstant: 180),
            
            detailContainerView.leadingAnchor.constraint(equalTo: categoryTableView.trailingAnchor),
            detailContainerView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            detailContainerView.topAnchor.constraint(equalTo: containerView.topAnchor),
            detailContainerView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // Add separator line between table and detail
        let separatorLine = UIView()
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        separatorLine.backgroundColor = .separator
        containerView.addSubview(separatorLine)
        
        NSLayoutConstraint.activate([
            separatorLine.leadingAnchor.constraint(equalTo: categoryTableView.trailingAnchor),
            separatorLine.topAnchor.constraint(equalTo: containerView.topAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            separatorLine.widthAnchor.constraint(equalToConstant: 0.5)
        ])
    }
    
    private func selectCategory(_ category: ConfigurationCategory) {
        selectedCategory = category
        categoryTableView.reloadData()
        
        // Remove current detail view controller
        if let current = currentDetailViewController {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        
        // Create and add new detail view controller
        let detailVC: UIViewController
        
        switch category {
        case .general:
            detailVC = GeneralSettingsViewController()
            (detailVC as! GeneralSettingsViewController).renderer = renderer
        case .particleColor:
            detailVC = ParticleColorSettingsViewController()
            (detailVC as! ParticleColorSettingsViewController).renderer = renderer
        case .particleSize:
            detailVC = ParticleSizeConfigViewController()
            (detailVC as! ParticleSizeConfigViewController).renderer = renderer
        }
        
        addChild(detailVC)
        detailVC.view.translatesAutoresizingMaskIntoConstraints = false
        detailContainerView.addSubview(detailVC.view)
        
        NSLayoutConstraint.activate([
            detailVC.view.topAnchor.constraint(equalTo: detailContainerView.topAnchor),
            detailVC.view.leadingAnchor.constraint(equalTo: detailContainerView.leadingAnchor),
            detailVC.view.trailingAnchor.constraint(equalTo: detailContainerView.trailingAnchor),
            detailVC.view.bottomAnchor.constraint(equalTo: detailContainerView.bottomAnchor)
        ])
        
        detailVC.didMove(toParent: self)
        currentDetailViewController = detailVC
    }
    
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
    
    @objc private func doneTapped() {
        // Apply all settings from current controllers
        if let generalVC = currentDetailViewController as? GeneralSettingsViewController {
            generalVC.applyConfiguration()
        } else if let colorVC = currentDetailViewController as? ParticleColorSettingsViewController {
            colorVC.applyConfiguration()
        } else if let sizeVC = currentDetailViewController as? ParticleSizeConfigViewController {
            sizeVC.applyConfiguration()
        }
        
        dismiss(animated: true)
    }
}

extension ConfigurationViewController: UITableViewDelegate, UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ConfigurationCategory.allCases.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CategoryCell", for: indexPath)
        let category = ConfigurationCategory.allCases[indexPath.row]
        
        var config = cell.defaultContentConfiguration()
        config.text = category.displayName
        config.textProperties.font = .systemFont(ofSize: 16)
        cell.contentConfiguration = config
        
        // Highlight selected category
        if category == selectedCategory {
            cell.backgroundColor = .systemBlue
            var textAttrs = config.textProperties
            textAttrs.color = .white
            config.textProperties = textAttrs
            cell.contentConfiguration = config
        } else {
            cell.backgroundColor = .secondarySystemBackground
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let category = ConfigurationCategory.allCases[indexPath.row]
        selectCategory(category)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 50
    }
}

// MARK: - General Settings View Controller

class GeneralSettingsViewController: UIViewController {
    
    var renderer: Renderer!
    private var particleCount: Int = 10000
    
    private let minParticleCount = 100
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        particleCount = renderer.activeParticleCount
        view.backgroundColor = .systemBackground
        
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        // Particle Count Section
        let countLabel = UILabel()
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.text = "Particle Count"
        countLabel.font = .boldSystemFont(ofSize: 16)
        contentView.addSubview(countLabel)
        
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = sliderValue(forParticleCount: particleCount)
        contentView.addSubview(slider)
        
        let countValueLabel = UILabel()
        countValueLabel.translatesAutoresizingMaskIntoConstraints = false
        countValueLabel.text = formattedCount(particleCount)
        countValueLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        countValueLabel.textAlignment = .right
        contentView.addSubview(countValueLabel)
        
        let countField = UITextField()
        countField.translatesAutoresizingMaskIntoConstraints = false
        countField.borderStyle = .roundedRect
        countField.keyboardType = .numberPad
        countField.textAlignment = .center
        countField.text = "\(particleCount)"
        countField.widthAnchor.constraint(equalToConstant: 120).isActive = true
        contentView.addSubview(countField)
        
        slider.addAction(UIAction { _ in
            let count = self.particleCount(forSliderValue: slider.value)
            countValueLabel.text = self.formattedCount(count)
            countField.text = "\(count)"
            self.particleCount = count
        }, for: .valueChanged)
        
        countField.addAction(UIAction { _ in
            guard let text = countField.text, let entered = Int(text) else { return }
            let clamped = min(max(entered, self.minParticleCount), maxParticleCount)
            countField.text = "\(clamped)"
            countValueLabel.text = self.formattedCount(clamped)
            slider.value = self.sliderValue(forParticleCount: clamped)
            self.particleCount = clamped
        }, for: .editingDidEnd)
        
        // Layout
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
            
            countLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            countLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            slider.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 12),
            slider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            slider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            countValueLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 8),
            countValueLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            countValueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            countField.topAnchor.constraint(equalTo: countValueLabel.bottomAnchor, constant: 12),
            countField.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            countField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    func applyConfiguration() {
        renderer.setParticleCount(particleCount)
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
    
    private func formattedCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Particle Color Settings View Controller

class ParticleColorSettingsViewController: UIViewController {
    
    var renderer: Renderer!
    private var selectedColorStyle: ParticleColorStyle = .rainbow
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        selectedColorStyle = renderer.particleColorStyle
        view.backgroundColor = .systemBackground
        
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        // Color Style Label
        let styleLabel = UILabel()
        styleLabel.translatesAutoresizingMaskIntoConstraints = false
        styleLabel.text = "Color Style"
        styleLabel.font = .boldSystemFont(ofSize: 16)
        contentView.addSubview(styleLabel)
        
        // Color Style Segmented Control
        let colorStyleControl = UISegmentedControl(items: ParticleColorStyle.allCases.map(\.displayName))
        colorStyleControl.translatesAutoresizingMaskIntoConstraints = false
        colorStyleControl.selectedSegmentIndex = selectedColorStyle.rawValue
        colorStyleControl.addTarget(self, action: #selector(colorStyleChanged(_:)), for: .valueChanged)
        contentView.addSubview(colorStyleControl)
        
        // Color preview
        let previewLabel = UILabel()
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.text = "Preview"
        previewLabel.font = .systemFont(ofSize: 14, weight: .medium)
        previewLabel.textColor = .secondaryLabel
        contentView.addSubview(previewLabel)
        
        let previewView = UIView()
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.layer.cornerRadius = 8
        previewView.backgroundColor = .systemGray5
        contentView.addSubview(previewView)
        
        let colorCircles = UIStackView()
        colorCircles.translatesAutoresizingMaskIntoConstraints = false
        colorCircles.axis = .horizontal
        colorCircles.spacing = 8
        colorCircles.alignment = .center
        colorCircles.distribution = .fillEqually
        previewView.addSubview(colorCircles)
        
        // Add color preview circles
        for _ in 0..<5 {
            let circle = UIView()
            circle.translatesAutoresizingMaskIntoConstraints = false
            circle.layer.cornerRadius = 16
            let r = CGFloat.random(in: 0...1)
            let g = CGFloat.random(in: 0...1)
            let b = CGFloat.random(in: 0...1)
            circle.backgroundColor = UIColor(cgColor: CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                               components: [r, g, b, 1.0])!)
            circle.widthAnchor.constraint(equalToConstant: 32).isActive = true
            circle.heightAnchor.constraint(equalToConstant: 32).isActive = true
            colorCircles.addArrangedSubview(circle)
        }
        
        NSLayoutConstraint.activate([
            colorCircles.topAnchor.constraint(equalTo: previewView.topAnchor, constant: 16),
            colorCircles.leadingAnchor.constraint(equalTo: previewView.leadingAnchor, constant: 16),
            colorCircles.trailingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: -16),
            colorCircles.bottomAnchor.constraint(equalTo: previewView.bottomAnchor, constant: -16)
        ])
        
        // Layout
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
            
            colorStyleControl.topAnchor.constraint(equalTo: styleLabel.bottomAnchor, constant: 12),
            colorStyleControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            colorStyleControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            
            previewLabel.topAnchor.constraint(equalTo: colorStyleControl.bottomAnchor, constant: 24),
            previewLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            
            previewView.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 8),
            previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            previewView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }
    
    @objc private func colorStyleChanged(_ sender: UISegmentedControl) {
        selectedColorStyle = ParticleColorStyle(rawValue: sender.selectedSegmentIndex) ?? .rainbow
    }
    
    func applyConfiguration() {
        renderer.setParticleColorStyle(selectedColorStyle)
    }
}
