//
//  ReviewCardPreviewProvider.swift
//  ReviewFeature
//
//  Created by Amgi Contributors.
//

package import SwiftUI
package import AppShared

/// Root-injected provider bridging `CardPreviewProviding` (in `AppShared`) to
/// `CardPreviewerView` (in `ReviewFeature`). Holds zero stored properties so
/// SwiftUI environment comparison stays O(1).
package struct ReviewCardPreviewProvider: CardPreviewProviding {
    package init() {}

    package func previewView(
        request: CardPreviewRequest,
        onCollectionChanged: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) -> AnyView {
        AnyView(
            CardPreviewerView(
                request: request,
                onCollectionChanged: onCollectionChanged,
                onDismiss: onDismiss
            )
        )
    }
}
