//
//  ShareSheet.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/4/25.
//

import SwiftUI
import UIKit
import LinkPresentation

/// UIKit wrapper for UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Process items to create activity items
        var activityItems: [Any] = []

        for item in items {
            if let shareableLink = item as? ShareableLink {
                // Share URL and text as separate items
                // iOS will combine them appropriately for each share target
                activityItems.append(shareableLink.url)
                activityItems.append(shareableLink.previewText)
            } else if let url = item as? URL {
                activityItems.append(url)
            } else {
                activityItems.append(item)
            }
        }

        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

/// Custom activity item source to provide rich link metadata
class LinkMetadataSource: NSObject, UIActivityItemSource {
    let link: ShareableLink
    let metadata: LPLinkMetadata
    
    init(link: ShareableLink) {
        self.link = link
        self.metadata = LPLinkMetadata()
        self.metadata.originalURL = link.url
        self.metadata.url = link.url
        self.metadata.title = link.previewText
        
        if let image = link.image {
            self.metadata.imageProvider = NSItemProvider(object: image)
            self.metadata.iconProvider = NSItemProvider(object: image)
        }
        
        super.init()
    }
    
    // MARK: - UIActivityItemSource
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return link.previewText
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        // For Messages, return the URL so it uses the metadata
        // For others, we might want to return the text + URL string
        return link.url
    }
    
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        return metadata
    }
}
