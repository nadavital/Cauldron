//
//  SharedCollectionDetailView.swift
//  Cauldron
//
//  Created by Claude on 10/30/25.
//

import SwiftUI

/// Compatibility wrapper for older call sites. CollectionDetailView owns the
/// dynamic owned/shared presentation and behavior.
struct SharedCollectionDetailView: View {
    let collection: Collection
    let dependencies: DependencyContainer

    var body: some View {
        CollectionDetailView(collection: collection, dependencies: dependencies)
    }
}

#Preview {
    NavigationStack {
        SharedCollectionDetailView(
            collection: Collection.new(name: "Holiday Foods", userId: UUID()),
            dependencies: DependencyContainer.preview()
        )
    }
}
