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
    case particleVelocity
    case camera
    
    var displayName: String {
        switch self {
        case .general: return "General"
        case .particleColor: return "Particle Color"
        case .particleSize: return "Particle Size"
        case .particleVelocity: return "Particle Velocity"
        case .camera: return "Camera"
        }
    }
}

class ConfigurationViewController: UIViewController {
    
    var renderer: Renderer!
    var doneButtonTitle: String = "OK"
    var showsCancelButton: Bool = true
    var initialCategory: ConfigurationCategory = .general
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCategoryChanged: ((ConfigurationCategory) -> Void)?
    private var selectedCategory: ConfigurationCategory = .general
    
    // UI Components
    private var containerView: UIView!
    private var categoryTableView: UITableView!
    private var detailContainerView: UIView!
    private var currentDetailViewController: UIViewController?
    private var generalSettingsViewController: GeneralSettingsViewController!
    private var particleColorSettingsViewController: ParticleColorSettingsViewController!
    private var particleSizeSettingsViewController: ParticleSizeConfigViewController!
    private var particleVelocitySettingsViewController: ParticleVelocitySettingsViewController!
    private var cameraSettingsViewController: CameraSettingsViewController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        // Setup navigation
        navigationItem.title = "Configuration"
        if showsCancelButton {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(cancelTapped)
            )
        } else {
            navigationItem.leftBarButtonItem = nil
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: doneButtonTitle,
            style: .prominent,
            target: self,
            action: #selector(doneTapped)
        )

        generalSettingsViewController = GeneralSettingsViewController()
        generalSettingsViewController.renderer = renderer
        particleColorSettingsViewController = ParticleColorSettingsViewController()
        particleColorSettingsViewController.renderer = renderer
        particleSizeSettingsViewController = ParticleSizeConfigViewController()
        particleSizeSettingsViewController.renderer = renderer
        particleVelocitySettingsViewController = ParticleVelocitySettingsViewController()
        particleVelocitySettingsViewController.renderer = renderer
        cameraSettingsViewController = CameraSettingsViewController()
        cameraSettingsViewController.renderer = renderer
        
        // Setup split view
        setupSplitView()
        
        // Select the category that was active when this screen was last shown.
        selectCategory(initialCategory)
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
        
        let categoryWidth: CGFloat = traitCollection.userInterfaceIdiom == .phone ? 132 : 180

        // Layout constraints
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            categoryTableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            categoryTableView.topAnchor.constraint(equalTo: containerView.topAnchor),
            categoryTableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            categoryTableView.widthAnchor.constraint(equalToConstant: categoryWidth),
            
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
        onCategoryChanged?(category)
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
            detailVC = generalSettingsViewController
        case .particleColor:
            detailVC = particleColorSettingsViewController
        case .particleSize:
            detailVC = particleSizeSettingsViewController
        case .particleVelocity:
            detailVC = particleVelocitySettingsViewController
        case .camera:
            detailVC = cameraSettingsViewController
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
        dismiss(animated: true) {
            self.onCancel?()
        }
    }
    
    @objc private func doneTapped() {
        // Only apply categories the user has actually opened; otherwise we risk
        // writing each controller's default property values back into the renderer.
        if generalSettingsViewController.isViewLoaded {
            generalSettingsViewController.applyConfiguration()
        }
        if particleColorSettingsViewController.isViewLoaded {
            particleColorSettingsViewController.applyConfiguration()
        }
        if particleSizeSettingsViewController.isViewLoaded {
            particleSizeSettingsViewController.applyConfiguration()
        }
        if particleVelocitySettingsViewController.isViewLoaded {
            particleVelocitySettingsViewController.applyConfiguration()
        }
        if cameraSettingsViewController.isViewLoaded {
            cameraSettingsViewController.applyConfiguration()
        }

        dismiss(animated: true) {
            self.onDone?()
        }
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
