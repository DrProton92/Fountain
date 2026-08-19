//
//  GameViewController.swift
//  ipadgameapp
//
//  Created by Dave Schmid on 8/15/26.
//

import UIKit
import MetalKit

// Our iOS specific view controller
class GameViewController: UIViewController {

    var renderer: Renderer!
    var mtkView: MTKView!
    private var menuContainerView: UIView!
    private var startButton: UIButton!
    private var inGameMenuButton: UIButton!
    private var lastPinchScale: CGFloat = 1.0
    private let minParticleCount = 100

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = view as? MTKView else {
            print("View of Gameview controller is not an MTKView")
            return
        }
        self.mtkView = mtkView

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported")
            return
        }
        
        mtkView.device = defaultDevice
        mtkView.backgroundColor = UIColor.black

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer
        mtkView.delegate = renderer
        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        // Start paused and show menu first.
        mtkView.isPaused = true
        configureMainMenu()
        configureInGameMenuButton()
        configureCameraGestures()
    }

    private func configureMainMenu() {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        view.addSubview(container)
        self.menuContainerView = container

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Particle Fountain"
        titleLabel.textColor = .white
        titleLabel.font = .boldSystemFont(ofSize: 34)
        titleLabel.textAlignment = .center

        let startButton = UIButton(type: .system)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.titleLabel?.font = .boldSystemFont(ofSize: 22)
        styleMenuButton(startButton, title: "Start", color: .systemBlue)
        startButton.addTarget(self, action: #selector(startGameTapped), for: .touchUpInside)
        self.startButton = startButton

        let configureButton = UIButton(type: .system)
        configureButton.translatesAutoresizingMaskIntoConstraints = false
        configureButton.titleLabel?.font = .boldSystemFont(ofSize: 22)
        styleMenuButton(configureButton, title: "Configure", color: .systemGray)
        configureButton.addTarget(self, action: #selector(configureTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, startButton, configureButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .fill
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.widthAnchor.constraint(equalToConstant: 280)
        ])
    }

    @objc private func startGameTapped() {
        menuContainerView.isHidden = true
        setButtonTitle(startButton, "Resume")
        inGameMenuButton.isHidden = false
        mtkView.isPaused = false
    }

    private func configureInGameMenuButton() {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .boldSystemFont(ofSize: 22)
        styleMenuButton(button, title: "<< Pause", color: UIColor.black.withAlphaComponent(0.6), compact: false)
        button.addTarget(self, action: #selector(showMenuTapped), for: .touchUpInside)
        view.addSubview(button)
        self.inGameMenuButton = button

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 36)
        ])

        button.isHidden = true
    }

    @objc private func showMenuTapped() {
        mtkView.isPaused = true
        menuContainerView.isHidden = false
    }

    private func configureCameraGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        mtkView.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        mtkView.addGestureRecognizer(pinch)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard menuContainerView.isHidden else { return }
        let translation = gesture.translation(in: mtkView)
        renderer.updateCameraRotation(deltaX: Float(translation.x), deltaY: Float(translation.y))
        gesture.setTranslation(.zero, in: mtkView)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard menuContainerView.isHidden else { return }

        if gesture.state == .began {
            lastPinchScale = gesture.scale
            return
        }

        let delta = gesture.scale - lastPinchScale
        renderer.updateCameraZoom(scaleDelta: Float(delta))
        lastPinchScale = gesture.scale
    }

    @objc private func configureTapped() {
        let alert = UIAlertController(
            title: "Configure Particles",
            message: "\n\n\n\n\n\n\n",
            preferredStyle: .alert
        )

        let slider = UISlider(frame: .zero)
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = sliderValue(forParticleCount: renderer.activeParticleCount)
        slider.translatesAutoresizingMaskIntoConstraints = false

        let valueField = UITextField(frame: .zero)
        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.borderStyle = .roundedRect
        valueField.keyboardType = .numberPad
        valueField.textAlignment = .center
        valueField.text = "\(renderer.activeParticleCount)"

        let valueLabel = UILabel(frame: .zero)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.textAlignment = .center
        valueLabel.textColor = .secondaryLabel
        valueLabel.font = .systemFont(ofSize: 14, weight: .medium)
        valueLabel.text = "Particles: \(formattedCount(renderer.activeParticleCount))"

        slider.addAction(UIAction { _ in
            let count = self.particleCount(forSliderValue: slider.value)
            valueLabel.text = "Particles: \(self.formattedCount(count))"
            valueField.text = "\(count)"
        }, for: .valueChanged)

        valueField.addAction(UIAction { _ in
            guard let text = valueField.text, let entered = Int(text) else { return }
            let clamped = min(max(entered, self.minParticleCount), maxParticleCount)
            valueField.text = "\(clamped)"
            valueLabel.text = "Particles: \(self.formattedCount(clamped))"
            slider.value = self.sliderValue(forParticleCount: clamped)
        }, for: .editingDidEnd)

        alert.view.addSubview(slider)
        alert.view.addSubview(valueField)
        alert.view.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: alert.view.leadingAnchor, constant: 18),
            slider.trailingAnchor.constraint(equalTo: valueField.leadingAnchor, constant: -12),
            slider.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 78),

            valueField.widthAnchor.constraint(equalToConstant: 96),
            valueField.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -18),
            valueField.centerYAnchor.constraint(equalTo: slider.centerYAnchor),

            valueLabel.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 8),
            valueLabel.leadingAnchor.constraint(equalTo: alert.view.leadingAnchor, constant: 18),
            valueLabel.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -18)
        ])

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Apply", style: .default) { [weak self] _ in
            guard let self else { return }
            let valueFromField = Int(valueField.text ?? "")
            let value = min(max(valueFromField ?? self.particleCount(forSliderValue: slider.value), self.minParticleCount), maxParticleCount)
            self.renderer.setParticleCount(value)
            if self.renderer.activeParticleCount != value {
                self.showCapacityNotice(requested: value, actual: self.renderer.activeParticleCount)
            }
        })

        present(alert, animated: true)
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

    private func styleMenuButton(_ button: UIButton, title: String, color: UIColor, compact: Bool = false) {
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.title = title
            config.baseBackgroundColor = color
            config.baseForegroundColor = .white
            config.cornerStyle = compact ? .capsule : .medium
            config.contentInsets = compact
                ? NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
                : NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
            button.configuration = config
        } else {
            button.setTitle(title, for: .normal)
            button.backgroundColor = color
            button.tintColor = .white
            button.layer.cornerRadius = compact ? 10 : 12
            button.contentEdgeInsets = compact
                ? UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
                : UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        }
    }

    private func setButtonTitle(_ button: UIButton, _ title: String) {
        if #available(iOS 15.0, *) {
            var config = button.configuration
            config?.title = title
            button.configuration = config
        } else {
            button.setTitle(title, for: .normal)
        }
    }

    private func formattedCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func showCapacityNotice(requested: Int, actual: Int) {
        let alert = UIAlertController(
            title: "Capacity Limit",
            message: "Requested \(formattedCount(requested)) particles, but this device currently supports \(formattedCount(actual)) with available GPU buffer space.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

}
