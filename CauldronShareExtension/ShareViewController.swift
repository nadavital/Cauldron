//
//  ShareViewController.swift
//  CauldronShareExtension
//
//  Receives Safari share-sheet URLs and hands them off to the main app.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let appGroupID = "group.Nadav.Cauldron"
    private let pendingRecipeURLKey = "shareExtension.pendingRecipeURL"
    private let callbackURL = URL(string: "cauldron://import-recipe")!
    private var hasProcessedShare = false
    private var launchAttemptCount = 0

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.text = "Sending recipe link to Cauldron..."
        return label
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        return indicator
    }()

    private lazy var openAppButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Open Cauldron"
        configuration.cornerStyle = .capsule

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        button.addTarget(self, action: #selector(openAppButtonTapped), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let stackView = UIStackView(arrangedSubviews: [
            activityIndicator,
            statusLabel,
            openAppButton
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16

        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: stackView.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: stackView.trailingAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !hasProcessedShare else { return }
        hasProcessedShare = true

        Task { [weak self] in
            await self?.processSharedContent()
        }
    }

    private func processSharedContent() async {
        setLoadingState(message: "Sending recipe link to Cauldron...")

        guard let url = await extractSharedURL() else {
            showErrorAndClose("No webpage URL found in this share.")
            return
        }

        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            showErrorAndClose("This link type is not supported.")
            return
        }

        persistPendingURL(url)
        setLoadingState(message: "Link received. Opening Cauldron...")
        openMainApp()
    }

    private func extractSharedURL() async -> URL? {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return nil
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await loadURL(from: provider) {
                    return url
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = await loadText(from: provider),
                   let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return url
                }
            }
        }

        return nil
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let url = item as? NSURL, let value = url as URL? {
                    continuation.resume(returning: value)
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8),
                          let url = URL(string: string) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let text = item as? NSString {
                    continuation.resume(returning: text as String)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func persistPendingURL(_ url: URL) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(url.absoluteString, forKey: pendingRecipeURLKey)
    }

    private func openMainApp() {
        launchAttemptCount += 1

        extensionContext?.open(callbackURL) { [weak self] didOpen in
            DispatchQueue.main.async {
                guard let self else { return }

                if didOpen {
                    self.statusLabel.text = "Link sent. Cauldron is opening so you can review and save."
                    self.completeRequest(after: 0.2)
                } else {
                    // Some hosts block NSExtensionContext.open even when the app is installed.
                    // Try a responder-chain fallback as a best-effort launch path.
                    let openedViaFallback = self.openMainAppViaResponderChain()
                    if openedViaFallback {
                        self.statusLabel.text = "Link sent. Cauldron should open now."
                        self.completeRequest(after: 0.2)
                        return
                    }

                    self.activityIndicator.stopAnimating()
                    self.openAppButton.isHidden = false
                    if self.launchAttemptCount > 1 {
                        self.statusLabel.text = "iOS prevented automatic app launch here. Open Cauldron manually and your link will import."
                    } else {
                        self.statusLabel.text = "The link is saved, but Cauldron did not open automatically. Tap below to try again."
                    }
                }
            }
        }
    }

    @objc private func openAppButtonTapped() {
        setLoadingState(message: "Opening Cauldron...")
        openMainApp()
    }

    private func setLoadingState(message: String) {
        statusLabel.text = message
        openAppButton.isHidden = true
        activityIndicator.startAnimating()
    }

    private func showErrorAndClose(_ message: String) {
        statusLabel.text = message
        openAppButton.isHidden = true
        activityIndicator.stopAnimating()
        completeRequest(after: 1.0)
    }

    private func openMainAppViaResponderChain() -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self

        while let currentResponder = responder {
            if currentResponder.responds(to: selector) {
                _ = currentResponder.perform(selector, with: callbackURL)
                return true
            }
            responder = currentResponder.next
        }

        return false
    }

    private func completeRequest(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
