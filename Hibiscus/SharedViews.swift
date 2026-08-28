import SwiftUI

extension Color {
    static let hibiscusAccent = Color(red: 0.925, green: 0.310, blue: 0.420)
}
import UIKit

struct CameraCharacterIcon: View {
    let character: CameraCharacter
    let size: CGFloat
    let fontSize: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(character.identityColor)
            Text(character.glyph)
                .font(.system(size: fontSize, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .offset(y: fontSize * character.glyphOpticalOffset)
        }
        .frame(width: size, height: size)
    }
}

struct PhotoFillView: View {
    let image: UIImage

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
    }
}

struct PhotoFitView: View {
    let image: UIImage

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct StatusPill: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .hibiscusGlass(tint: .black.opacity(0.35), in: Capsule())
            .padding()
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
