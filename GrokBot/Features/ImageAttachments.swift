import SwiftUI
import UIKit

/// Turns photos and clipboard images into small JPEGs that fit through the encrypted relay.
enum ImageAttachments {
    static let targetBytes = 1_500_000

    static func make(from data: Data) -> RemoteAttachment? {
        guard let image = UIImage(data: data) else { return nil }
        return make(from: image)
    }

    static func make(from image: UIImage) -> RemoteAttachment? {
        for side: CGFloat in [1800, 1400, 1000, 720] {
            let scaled = resized(image, longestSide: side)
            for quality: CGFloat in [0.8, 0.65, 0.5, 0.35] {
                if let data = scaled.jpegData(compressionQuality: quality), data.count <= targetBytes {
                    return RemoteAttachment(name: "Photo-\(Int(Date().timeIntervalSince1970)).jpg", mime: "image/jpeg", data: data)
                }
            }
        }
        return nil
    }

    private static func resized(_ image: UIImage, longestSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > longestSide else { return image }
        let scale = longestSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

struct ImageChips: View {
    let images: [RemoteAttachment]
    let tint: Color
    let remove: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, item in
                    ZStack(alignment: .topTrailing) {
                        if let ui = UIImage(data: item.data) {
                            Image(uiImage: ui).resizable().scaledToFill().frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Button { remove(index) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 20))
                                .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.65))
                        }.buttonStyle(.plain).offset(x: 6, y: -6).accessibilityLabel("Remove image")
                    }.frame(width: 64, height: 64)
                }
            }.padding(.horizontal, 8).padding(.top, 8)
        }
    }
}
