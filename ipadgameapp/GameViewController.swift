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
    private var inGameMenuButton: UIButton!
    private var gestureDebugLabel: UILabel!
    private var hasPresentedInitialConfiguration = false
    private var shouldShowConfigurationAfterInterruption = false
    private var previousPinchScale: CGFloat = 1.0
    private var lastConfigurationCategory: ConfigurationCategory = .general

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

        // Start paused and show configuration first.
        mtkView.isPaused = true
        configureInGameMenuButton()
        configureCameraGestures()
        configureGestureDebugLabel()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasPresentedInitialConfiguration else { return }
        hasPresentedInitialConfiguration = true
        presentConfigurationScreen(showCancelButton: false, doneTitle: "Start")
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
        presentConfigurationScreen(showCancelButton: true, doneTitle: "Resume")
    }

    private func configureCameraGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delegate = self

        // Attach to the controller root view so gestures are not dependent on MTKView input quirks.
        view.addGestureRecognizer(pan)
        
        // Add tap gesture to pause/resume
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.numberOfTouchesRequired = 1
        view.addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !mtkView.isPaused, presentedViewController == nil else { return }
        presentConfigurationScreen(showCancelButton: true, doneTitle: "Resume")
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !mtkView.isPaused, presentedViewController == nil else { return }

        if gesture.state == .began {
            updateGestureDebug("pan began")
        }

        if gesture.state == .changed {
            let translation = gesture.translation(in: mtkView)
            renderer.updateCameraRotation(deltaX: Float(translation.x), deltaY: Float(translation.y))
            updateGestureDebug("pan changed")
            gesture.setTranslation(.zero, in: mtkView)
        } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            updateGestureDebug("pan ended")
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard !mtkView.isPaused, presentedViewController == nil else { return }

        switch gesture.state {
        case .began:
            previousPinchScale = gesture.scale
            updateGestureDebug("zoom began (pinch)")
        case .changed:
            let deltaScale = gesture.scale / previousPinchScale
            renderer.updateCameraZoom(scaleFactor: Float(deltaScale))
            previousPinchScale = gesture.scale
            updateGestureDebug("zoom changed")
        case .ended, .cancelled, .failed:
            previousPinchScale = 1.0
            updateGestureDebug("zoom ended")
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    @objc private func configureTapped() {
        presentConfigurationScreen(showCancelButton: true, doneTitle: "Resume")
    }

    @objc private func handleWillResignActive() {
        guard !mtkView.isPaused else { return }
        shouldShowConfigurationAfterInterruption = true
        mtkView.isPaused = true
        inGameMenuButton.isHidden = true
    }

    @objc private func handleDidBecomeActive() {
        guard shouldShowConfigurationAfterInterruption else { return }
        shouldShowConfigurationAfterInterruption = false
        if presentedViewController == nil {
            presentConfigurationScreen(showCancelButton: true, doneTitle: "Resume")
        }
    }

    private func presentConfigurationScreen(showCancelButton: Bool, doneTitle: String) {
        guard presentedViewController == nil else { return }
        mtkView.isPaused = true
        inGameMenuButton.isHidden = true

        let configVC = ConfigurationViewController()
        configVC.renderer = renderer
        configVC.showsCancelButton = showCancelButton
        configVC.doneButtonTitle = doneTitle
        configVC.initialCategory = lastConfigurationCategory
        configVC.onCategoryChanged = { [weak self] category in
            self?.lastConfigurationCategory = category
        }
        configVC.onDone = { [weak self] in
            guard let self else { return }
            self.mtkView.isPaused = false
            self.inGameMenuButton.isHidden = false
            self.updateGestureDebug("idle")
        }
        configVC.onCancel = { [weak self] in
            guard let self else { return }
            self.mtkView.isPaused = false
            self.inGameMenuButton.isHidden = false
            self.updateGestureDebug("idle")
        }

        let navController = UINavigationController(rootViewController: configVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
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

}
