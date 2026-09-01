import SwiftUI
import UIKit

/// Fires on touch-down inside the circle. SwiftUI `onTapGesture` waits for lift
/// and drops burst taps while the wheel view is updating.
struct InstantTapOverlay: UIViewRepresentable {
    var enabled: Bool = true
    var onTap: () -> Void

    func makeUIView(context: Context) -> InstantTapUIView {
        let view = InstantTapUIView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.onTap = onTap
        view.isUserInteractionEnabled = enabled
        view.isAccessibilityElement = true
        view.accessibilityTraits = .button
        view.accessibilityLabel = "Tap the wheel to fill"
        return view
    }

    func updateUIView(_ uiView: InstantTapUIView, context: Context) {
        uiView.onTap = onTap
        uiView.isUserInteractionEnabled = enabled
    }
}

final class InstantTapUIView: UIView {
    var onTap: (() -> Void)?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let radius = min(bounds.width, bounds.height) / 2
        let dx = point.x - bounds.midX
        let dy = point.y - bounds.midY
        return dx * dx + dy * dy <= radius * radius
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isUserInteractionEnabled else { return }
        for _ in touches {
            onTap?()
        }
    }

    override func accessibilityActivate() -> Bool {
        onTap?()
        return true
    }
}
