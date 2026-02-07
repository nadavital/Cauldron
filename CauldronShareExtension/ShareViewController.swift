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

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.text = "Sending recipe link to Cauldron..."
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Task { [weak self] in
            await self?.processSharedContent()
        }
    }

    private func processSharedContent() async {
        guard let url = await extractSharedURL() else {
            statusLabel.text = "No webpage URL found in this share."
            completeRequest(after: 1.0)
            return
        }

        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            statusLabel.text = "This link type is not supported."
            completeRequest(after: 1.0)
            return
        }

        persistPendingURL(url)
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
        extensionContext?.open(callbackURL) { [weak self] _ in
            self?.completeRequest(after: 0.1)
        }
    }

    private func completeRequest(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
