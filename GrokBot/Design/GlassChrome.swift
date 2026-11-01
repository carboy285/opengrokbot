import SwiftUI

/// Compiles with older SDKs; real Liquid Glass is enabled with Xcode 26+ and OS 26+.
struct GlassChrome<S: Shape>: ViewModifier {
    let shape: S
    var interactive = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.background, in: shape)
                .overlay(shape.stroke(.primary.opacity(0.15), lineWidth: 1))
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, iOS 26.0, *) {
                content.glassEffect(.regular.interactive(interactive), in: shape)
            } else {
                fallback(content)
            }
            #else
            fallback(content)
            #endif
        }
    }

    private func fallback(_ content: Content) -> some View {
        content.background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(.primary.opacity(0.12), lineWidth: 1))
    }
}

extension View {
    func glassChrome<S: Shape>(in shape: S, interactive: Bool = true) -> some View {
        modifier(GlassChrome(shape: shape, interactive: interactive))
    }
}
