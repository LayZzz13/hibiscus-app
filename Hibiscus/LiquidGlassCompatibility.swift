import SwiftUI

enum HibiscusGlassKind {
    case regular
    case clear
}

struct HibiscusGlassContainer<Content: View>: View {
    let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func hibiscusGlass<S: Shape>(
        _ kind: HibiscusGlassKind = .regular,
        tint: Color? = nil,
        interactive: Bool = false,
        isEnabled: Bool = true,
        in shape: S
    ) -> some View {
        if isEnabled {
            if #available(iOS 26.0, *) {
                nativeHibiscusGlass(kind, tint: tint, interactive: interactive, in: shape)
            } else {
                modifier(HibiscusMaterialSurface(shape: shape, tint: tint, kind: kind))
            }
        } else {
            self
        }
    }

    @ViewBuilder
    func hibiscusGlassButtonStyle(
        _ kind: HibiscusGlassKind = .regular,
        tint: Color? = nil
    ) -> some View {
        if #available(iOS 26.0, *) {
            switch kind {
            case .regular:
                if let tint {
                    buttonStyle(.glass(.regular.tint(tint).interactive()))
                } else {
                    buttonStyle(.glass(.regular.interactive()))
                }
            case .clear:
                if let tint {
                    buttonStyle(.glass(.clear.tint(tint).interactive()))
                } else {
                    buttonStyle(.glass(.clear.interactive()))
                }
            }
        } else {
            buttonStyle(HibiscusMaterialButtonStyle(kind: kind, tint: tint))
        }
    }

    @available(iOS 26.0, *)
    @ViewBuilder
    private func nativeHibiscusGlass<S: Shape>(
        _ kind: HibiscusGlassKind,
        tint: Color?,
        interactive: Bool,
        in shape: S
    ) -> some View {
        switch kind {
        case .regular:
            if let tint {
                if interactive {
                    glassEffect(.regular.tint(tint).interactive(), in: shape)
                } else {
                    glassEffect(.regular.tint(tint), in: shape)
                }
            } else if interactive {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        case .clear:
            if let tint {
                if interactive {
                    glassEffect(.clear.tint(tint).interactive(), in: shape)
                } else {
                    glassEffect(.clear.tint(tint), in: shape)
                }
            } else if interactive {
                glassEffect(.clear.interactive(), in: shape)
            } else {
                glassEffect(.clear, in: shape)
            }
        }
    }
}

private struct HibiscusMaterialSurface<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let kind: HibiscusGlassKind

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background {
                shape.fill(surfaceTint)
            }
            .overlay {
                shape.stroke(.white.opacity(kind == .clear ? 0.13 : 0.18), lineWidth: 0.7)
            }
    }

    private var surfaceTint: Color {
        if let tint {
            return tint.opacity(kind == .clear ? 0.10 : 0.20)
        }
        return .white.opacity(kind == .clear ? 0.025 : 0.055)
    }
}

private struct HibiscusMaterialButtonStyle: ButtonStyle {
    let kind: HibiscusGlassKind
    let tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .background {
                Capsule().fill(surfaceTint)
            }
            .overlay {
                Capsule().stroke(.white.opacity(kind == .clear ? 0.13 : 0.18), lineWidth: 0.7)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var surfaceTint: Color {
        if let tint {
            return tint.opacity(kind == .clear ? 0.12 : 0.72)
        }
        return .white.opacity(kind == .clear ? 0.025 : 0.065)
    }
}
