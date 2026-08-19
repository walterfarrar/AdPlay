import SwiftUI

/// Centered page column. Scrolls only when the content is taller than the viewport.
struct FitPage<Content: View>: View {
    var maxWidth: CGFloat = 560
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            page
            ScrollView {
                page
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var page: some View {
        content()
            .padding(padding)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
