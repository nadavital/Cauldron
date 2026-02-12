//
//  ShareViewController.swift
//  CauldronShareExtension
//
//  Receives recipe links, prepares share payload, and saves to App Group.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let appGroupID = "group.Nadav.Cauldron"
    private let pendingRecipeURLKey = "shareExtension.pendingRecipeURL"
    private let preparedRecipePayloadKey = "shareExtension.preparedRecipePayload"

    private var hasProcessedShare = false
    private var sharedURL: URL?
    private var preparedPayload: PreparedShareRecipePayload?
    private var imageLoadTask: Task<Void, Never>?

    private let accentColor = UIColor.systemOrange

    private let logoImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        return imageView
    }()

    private let appTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Cauldron"
        label.font = .preferredFont(forTextStyle: .title2)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let previewImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isHidden = true
        return imageView
    }()

    private let recipeTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .headline)
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.isHidden = true
        return label
    }()

    private let recipeMetaLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.isHidden = true
        return label
    }()

    private let recipeSourceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .tertiaryLabel
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        label.isHidden = true
        return label
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        return indicator
    }()

    private lazy var primaryButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.title = "Save to Cauldron"
        configuration.baseBackgroundColor = accentColor
        configuration.baseForegroundColor = .white

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(primaryButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var secondaryButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Cancel"

        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(secondaryButtonTapped), for: .touchUpInside)
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
        configureInitialBranding()
        setProcessingState(message: "Analyzing shared recipe...")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !hasProcessedShare else { return }
        hasProcessedShare = true

        Task { [weak self] in
            await self?.processSharedContent()
        }
    }

    deinit {
        imageLoadTask?.cancel()
    }

    private func configureLayout() {
        view.backgroundColor = .systemBackground

        let headerStack = UIStackView(arrangedSubviews: [logoImageView, appTitleLabel])
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 10

        let detailsStack = UIStackView(arrangedSubviews: [
            statusLabel,
            recipeTitleLabel,
            recipeMetaLabel,
            recipeSourceLabel,
            activityIndicator
        ])
        detailsStack.translatesAutoresizingMaskIntoConstraints = false
        detailsStack.axis = .vertical
        detailsStack.alignment = .fill
        detailsStack.spacing = 10
        detailsStack.isLayoutMarginsRelativeArrangement = true
        detailsStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 20, bottom: 22, trailing: 20)

        let contentStack = UIStackView(arrangedSubviews: [
            previewImageView,
            detailsStack
        ])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 0

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.addSubview(contentStack)

        let buttonStack = UIStackView(arrangedSubviews: [primaryButton, secondaryButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .vertical
        buttonStack.alignment = .fill
        buttonStack.spacing = 8

        view.addSubview(headerStack)
        view.addSubview(scrollView)
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),

            logoImageView.widthAnchor.constraint(equalToConstant: 32),
            logoImageView.heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            previewImageView.heightAnchor.constraint(equalToConstant: 230),

            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            primaryButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func configureInitialBranding() {
        logoImageView.image = UIImage(named: "BrandMarks/CauldronIcon")
        if logoImageView.image == nil {
            logoImageView.image = UIImage(systemName: "flame.fill")
            logoImageView.tintColor = accentColor
        }

        showImagePlaceholder()
    }

    private func processSharedContent() async {
        setProcessingState(message: "Analyzing shared recipe...")

        guard let url = await extractSharedURL() else {
            setFailureState(message: "No webpage URL found in this share.")
            return
        }

        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            setFailureState(message: "This link type is not supported.")
            return
        }

        sharedURL = url

        let payload = await SharedRecipePreprocessor.prepareRecipePayload(from: url)
        preparedPayload = payload

        await MainActor.run { [weak self] in
            guard let self else { return }
            if let payload {
                self.setReadyState(with: payload, sourceURL: url)
                self.loadPreviewImageIfAvailable(from: payload.imageURL)
            } else {
                self.setFallbackReadyState(sourceURL: url)
            }
        }
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
                   let url = extractFirstURL(from: text) {
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
                          let url = self.extractFirstURL(from: string) {
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

    private func extractFirstURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return URL(string: trimmed)
        }

        let range = NSRange(location: 0, length: trimmed.utf16.count)
        let matches = detector.matches(in: trimmed, options: [], range: range)

        for match in matches {
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }
            return url
        }

        if let fallback = URL(string: trimmed),
           let scheme = fallback.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return fallback
        }

        return nil
    }

    private func loadPreviewImageIfAvailable(from imageURLString: String?) {
        guard let imageURLString,
              let url = URL(string: imageURLString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }

        imageLoadTask?.cancel()
        imageLoadTask = Task { [weak self] in
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue(
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                forHTTPHeaderField: "User-Agent"
            )

            guard let self else { return }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled,
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode),
                      let image = UIImage(data: data) else {
                    return
                }

                await MainActor.run {
                    self.previewImageView.image = image
                    self.previewImageView.contentMode = .scaleAspectFill
                    self.previewImageView.backgroundColor = .clear
                    self.previewImageView.tintColor = nil
                    self.previewImageView.isHidden = false
                }
            } catch {
                // Best effort only.
            }
        }
    }

    private func showImagePlaceholder() {
        if let brandIcon = UIImage(named: "BrandMarks/CauldronIcon")?.withRenderingMode(.alwaysTemplate) {
            previewImageView.image = brandIcon
        } else {
            previewImageView.image = UIImage(systemName: "fork.knife.circle.fill")
        }
        previewImageView.contentMode = .center
        previewImageView.tintColor = .tertiaryLabel
        previewImageView.backgroundColor = .secondarySystemBackground
        previewImageView.isHidden = false
    }

    private func setSavingState() {
        var config = primaryButton.configuration
        config?.title = "Saving..."
        config?.showsActivityIndicator = true
        primaryButton.configuration = config
        primaryButton.isEnabled = false
        secondaryButton.isEnabled = false
    }

    private func setProcessingState(message: String) {
        statusLabel.text = message
        activityIndicator.startAnimating()
        activityIndicator.isHidden = false

        recipeTitleLabel.isHidden = true
        recipeMetaLabel.isHidden = true
        recipeSourceLabel.isHidden = true
        showImagePlaceholder()

        primaryButton.isEnabled = false
        var primaryConfig = primaryButton.configuration
        primaryConfig?.title = "Preparing..."
        primaryConfig?.showsActivityIndicator = false
        primaryButton.configuration = primaryConfig

        secondaryButton.isHidden = false
        secondaryButton.configuration?.title = "Cancel"
        secondaryButton.isEnabled = true
    }

    private func setReadyState(with payload: PreparedShareRecipePayload, sourceURL: URL) {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true

        statusLabel.text = "Recipe preview ready. Save to Cauldron."

        recipeTitleLabel.text = payload.title
        recipeTitleLabel.isHidden = false

        var metaParts: [String] = [
            "\(payload.ingredients.count) ingredients",
            "\(payload.steps.count) steps"
        ]
        if let totalMinutes = payload.totalMinutes {
            metaParts.append("\(totalMinutes)m")
        }
        recipeMetaLabel.text = metaParts.joined(separator: "  •  ")
        recipeMetaLabel.isHidden = false

        if let host = sourceURL.host {
            recipeSourceLabel.text = "Source: \(host)"
            recipeSourceLabel.isHidden = false
        }

        if payload.imageURL == nil {
            previewImageView.isHidden = true
        } else {
            showImagePlaceholder()
        }

        primaryButton.isEnabled = true
        var primaryConfig = primaryButton.configuration
        primaryConfig?.title = "Save to Cauldron"
        primaryConfig?.showsActivityIndicator = false
        primaryButton.configuration = primaryConfig

        secondaryButton.isHidden = false
        secondaryButton.configuration?.title = "Cancel"
        secondaryButton.isEnabled = true
    }

    private func setFallbackReadyState(sourceURL: URL) {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true

        statusLabel.text = "We couldn't fully parse this page here. Save the link and Cauldron will finish import."

        recipeTitleLabel.text = sourceURL.absoluteString
        recipeTitleLabel.isHidden = false

        if let host = sourceURL.host {
            recipeSourceLabel.text = "Source: \(host)"
            recipeSourceLabel.isHidden = false
        }

        recipeMetaLabel.isHidden = true
        previewImageView.isHidden = true

        primaryButton.isEnabled = true
        var primaryConfig = primaryButton.configuration
        primaryConfig?.title = "Send Link to Cauldron"
        primaryConfig?.showsActivityIndicator = false
        primaryButton.configuration = primaryConfig

        secondaryButton.isHidden = false
        secondaryButton.configuration?.title = "Cancel"
        secondaryButton.isEnabled = true
    }

    private func setFailureState(message: String) {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true

        statusLabel.text = message
        recipeTitleLabel.isHidden = true
        recipeMetaLabel.isHidden = true
        recipeSourceLabel.isHidden = true
        previewImageView.isHidden = true

        primaryButton.isEnabled = false
        var primaryConfig = primaryButton.configuration
        primaryConfig?.title = "Unavailable"
        primaryConfig?.showsActivityIndicator = false
        primaryButton.configuration = primaryConfig

        secondaryButton.isHidden = false
        secondaryButton.configuration?.title = "Done"
        secondaryButton.isEnabled = true
    }

    @objc private func primaryButtonTapped() {
        guard let sharedURL else {
            setFailureState(message: "Missing shared URL. Try sharing again.")
            return
        }

        setSavingState()
        persistPendingURL(sharedURL)

        if let preparedPayload {
            persistPreparedRecipePayload(preparedPayload)
        } else {
            clearPreparedRecipePayload()
        }

        completeRequest(after: 0)
    }

    @objc private func secondaryButtonTapped() {
        completeRequest(after: 0)
    }

    private func persistPendingURL(_ url: URL) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(url.absoluteString, forKey: pendingRecipeURLKey)
    }

    private func persistPreparedRecipePayload(_ payload: PreparedShareRecipePayload) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(payload) else {
            return
        }

        defaults.set(data, forKey: preparedRecipePayloadKey)
    }

    private func clearPreparedRecipePayload() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.removeObject(forKey: preparedRecipePayloadKey)
    }

    private func completeRequest(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
