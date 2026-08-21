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
        
        let countLabel = UILabel()
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.text = "Particle Count"
        countLabel.font = .boldSystemFont(ofSize: 16)
        contentView.addSubview(countLabel)
        
        let countRow = UIStackView()
        countRow.translatesAutoresizingMaskIntoConstraints = false
        countRow.axis = .horizontal
        countRow.spacing = 12
        countRow.alignment = .center
        contentView.addSubview(countRow)

        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = sliderValue(forParticleCount: particleCount)
        countRow.addArrangedSubview(slider)
        
        let countField = UITextField()
        countField.translatesAutoresizingMaskIntoConstraints = false
        countField.borderStyle = .roundedRect
        countField.keyboardType = .numberPad
        countField.textAlignment = .center
        countField.text = "\(particleCount)"
        countField.widthAnchor.constraint(equalToConstant: 96).isActive = true
        countRow.addArrangedSubview(countField)
        
        slider.addAction(UIAction { _ in
            let count = self.particleCount(forSliderValue: slider.value)
            countField.text = "\(count)"
            self.particleCount = count
        }, for: .valueChanged)
        
        countField.addAction(UIAction { _ in
            guard let text = countField.text, let entered = Int(text) else { return }
            let clamped = min(max(entered, self.minParticleCount), maxParticleCount)
            countField.text = "\(clamped)"
            slider.value = self.sliderValue(forParticleCount: clamped)
            self.particleCount = clamped
        }, for: .editingDidEnd)
        
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
            
            countRow.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 12),
            countRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            countRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            countRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            
            slider.heightAnchor.constraint(equalToConstant: 31)
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
}
