//
//  GameViewController.swift
//  ipadgameapp
//
//  Created by Dave Schmid on 8/15/26.
//

import UIKit
import MetalKit

// Our iOS specific view controller
class GameViewController: UIViewController, UIGestureRecognizerDelegate {

    var renderer: Renderer!
    var mtkView: MTKView!
    private var menuContainerView: UIView!
    private var startButton: UIButton!
    private var inGameMenuButton: UIButton!
    private var gestureDebugLabel: UILabel!
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
        mtkView.isMultipleTouchEnabled = true
        mtkView.isUserInteractionEnabled = true
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
        configureGestureDebugLabel()
    }

    private func configureGestureDebugLabel() {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.textAlignment = .left
        label.isUserInteractionEnabled = false
        label.text = "Gesture: idle\nDistance: --"
        view.addSubview(label)
        self.gestureDebugLabel = label

        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            label.widthAnchor.constraint(equalToConstant: 190)
        ])
    }

    private func updateGestureDebug(_ text: String) {
        let distanceText = String(format: "%.2f", renderer.cameraDistance)
        gestureDebugLabel.text = "Gesture: \(text)\nDistance: \(distanceText)"
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
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = false
        pan.delegate = self

        // Attach to the controller root view so gestures are not dependent on MTKView input quirks.
        view.addGestureRecognizer(pan)
        
        // Add tap gesture to pause/resume
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.numberOfTouchesRequired = 1
        view.addGestureRecognizer(tap)
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // Only handle tap when menu is hidden (game is running)
        guard menuContainerView.isHidden else { return }
        
        // Pause/resume the game
        mtkView.isPaused = true
        menuContainerView.isHidden = false
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard menuContainerView.isHidden else { return }

        if gesture.state == .began {
            if gesture.numberOfTouches >= 2 {
                updateGestureDebug("zoom began (2-finger drag)")
            } else {
                updateGestureDebug("pan began")
            }
        }

        if gesture.state == .changed {
            let translation = gesture.translation(in: mtkView)
            if gesture.numberOfTouches >= 2 {
                // Two-finger vertical drag for zoom
                // Drag UP (negative Y) = zoom in, Drag DOWN (positive Y) = zoom out
                let zoomDelta = Float(translation.y) * 0.01
                renderer.updateCameraZoom(scaleFactor: 1.0 - zoomDelta)
                updateGestureDebug("zoom: \(String(format: "%.1f", translation.y))")
            } else {
                // Single finger pan for rotation
                renderer.updateCameraRotation(deltaX: Float(translation.x), deltaY: Float(translation.y))
                updateGestureDebug("pan changed")
            }
            gesture.setTranslation(.zero, in: mtkView)
        } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            updateGestureDebug(gesture.numberOfTouches >= 2 ? "zoom ended" : "pan ended")
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    @objc private func configureTapped() {
        let configVC = ConfigurationViewController()
        configVC.renderer = renderer
        let navController = UINavigationController(rootViewController: configVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
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

}
