import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum AvatarArtwork {
    static func color(_ name: String) -> Color {
        let values: [String: UInt32] = ["black": 0x111111, "ochre": 0xA46E39, "red": 0xFF2948,
            "orange": 0xFF7012, "amber": 0xF69A0A, "green": 0x10BF70, "teal": 0x15B6A5,
            "blue": 0x2385FF, "purple": 0x9355FF, "pink": 0xF62A9B, "gray": 0x969696, "white": 0xFFFFFF]
        let hex = values[name] ?? 0x9355FF
        return Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
                     green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }

    private static func safeDimensions(_ source: CGImageSource) -> Bool {
        guard let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = values[kCGImagePropertyPixelWidth as String] as? Int,
              let height = values[kCGImagePropertyPixelHeight as String] as? Int else { return false }
        return width > 0 && height > 0 && width <= 32768 && height <= 32768 && width * height <= 40_000_000
    }
    static func image(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary), safeDimensions(source) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ] as CFDictionary)
    }

    static func importImage(_ url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let resource = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = resource.fileSize, size <= 12_000_000,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary), safeDimensions(source),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 192
              ] as CFDictionary) else { throw AvatarImportError.unreadable }
        for quality in [0.8, 0.6, 0.4, 0.2] {
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else { throw AvatarImportError.unreadable }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination), result.length <= 24_576 { return result as Data }
        }
        throw AvatarImportError.unreadable
    }
}

private enum AvatarImportError: LocalizedError {
    case unreadable
    var errorDescription: String? { "Choose an image under 12 MB. Try a smaller JPEG, PNG, or HEIC image." }
}

struct CustomBotAvatar: View {
    let appearance: BotAppearance
    var size: CGFloat = 48
    var body: some View {
        Group {
            if let data = appearance.imageData, let image = AvatarArtwork.image(data) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                ZStack {
                    BotGlyphShape(style: appearance.shape).fill(AvatarArtwork.color(appearance.color))
                    HStack(spacing: size * 0.115) {
                        Capsule().frame(width: size * 0.09, height: size * 0.25)
                        Capsule().frame(width: size * 0.09, height: size * 0.25).offset(y: -size * 0.035)
                    }
                    .foregroundStyle(appearance.color == "white" ? Color.black : Color.white)
                    .rotationEffect(.degrees(-25)).offset(x: size * 0.07, y: -size * 0.06)
                    if appearance.shape == .fruit {
                        Capsule().fill(Color.primary).frame(width: size * 0.08, height: size * 0.17)
                            .rotationEffect(.degrees(-35)).offset(x: -size * 0.12, y: -size * 0.42)
                    }
                }.padding(size * 0.04)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

private struct BotGlyphShape: Shape {
    let style: BotAvatarShape
    func path(in rect: CGRect) -> Path {
        if style == .circle || style == .fruit { return Circle().path(in: rect) }
        if style == .square { return RoundedRectangle(cornerRadius: rect.width * 0.13).path(in: rect).applying(CGAffineTransform(translationX: -rect.midX, y: -rect.midY).concatenating(CGAffineTransform(rotationAngle: -.pi / 9)).concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))) }
        if style == .capsule { return Capsule().path(in: rect.insetBy(dx: 0, dy: rect.height * 0.12)) }
        if style == .heart {
            var path = Path()
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y) }
            path.move(to: p(0.5, 0.94))
            path.addCurve(to: p(0.04, 0.3), control1: p(0.1, 0.75), control2: p(-0.1, 0.55))
            path.addCurve(to: p(0.5, 0.22), control1: p(0.1, -0.02), control2: p(0.4, 0.01))
            path.addCurve(to: p(0.96, 0.3), control1: p(0.6, 0.01), control2: p(0.9, -0.02))
            path.addCurve(to: p(0.5, 0.94), control1: p(1.1, 0.55), control2: p(0.9, 0.75))
            path.closeSubpath(); return path
        }
        let count = 120
        let points: [CGPoint] = (0..<count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi - .pi / 2
            let radius: Double
            switch style {
            case .hexagon:
                let sector = (angle + 2 * .pi).truncatingRemainder(dividingBy: .pi / 3) - .pi / 6
                radius = 0.42 / cos(sector)
            case .triangle: radius = 0.37 + 0.105 * cos(3 * angle)
            case .sparkle: radius = 0.37 + 0.11 * cos(4 * angle)
            case .star: radius = 0.37 + 0.105 * cos(6 * angle)
            case .flower: radius = 0.41 + 0.07 * cos(5 * angle)
            case .clover: radius = 0.40 + 0.085 * cos(4 * angle + 0.6)
            case .cloud: radius = 0.42 + 0.055 * cos(7 * angle) + 0.025 * sin(3 * angle)
            case .droplet: radius = 0.39 + 0.08 * cos(angle) + 0.055 * cos(3 * angle)
            case .pebble: radius = 0.43 + 0.035 * cos(3 * angle) + 0.025 * sin(2 * angle)
            default: radius = 0.46
            }
            return CGPoint(x: rect.midX + rect.width * CGFloat(radius * cos(angle)),
                           y: rect.midY + rect.height * CGFloat(radius * sin(angle)))
        }
        var path = Path(); path.addLines(points); path.closeSubpath(); return path
    }
}

/// Shared editor: the Mac saves locally; iOS sends the same appearance to the Mac.
struct BotAvatarPicker: View {
    let bot: Bot
    var save: (BotAppearance?) async -> Bool
    var close: () -> Void
    @State private var draft: BotAppearance
    @State private var reset = false
    @State private var tab = "Bot"
    @State private var importing = false
    @State private var saving = false
    @State private var error: String?

    init(bot: Bot, save: @escaping (BotAppearance?) async -> Bool, close: @escaping () -> Void) {
        self.bot = bot; self.save = save; self.close = close
        _draft = State(initialValue: bot.appearance ?? BotAppearance(color: bot.color))
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text("Bot avatar").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark").frame(width: 32, height: 32).background(.quaternary, in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel("Close avatar picker").disabled(saving)
            }
            CustomBotAvatar(appearance: draft, size: 100).padding(.vertical, 12)
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(["Bot", "Generate", "Upload"], id: \.self) { item in
                        Button {
                            if item == "Upload" { importing = true }
                            else { tab = item }
                        } label: {
                            Text(item).font(.system(size: 14)).padding(.horizontal, 10).padding(.vertical, 9)
                                .background(tab == item ? Color.primary.opacity(0.07) : .clear, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    Button("Reset") {
                        draft = BotAppearance(shape: bot.isMain == true ? .circle : .square, color: bot.isMain == true ? "white" : "purple")
                        reset = true; tab = "Bot"
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }.padding(12)
                Divider()
                ScrollView {
                    VStack(spacing: 24) {
                        if tab == "Generate" {
                            Text("Generate a new shape and color combination.").font(.subheadline).foregroundStyle(.secondary)
                            Button("Generate a look") {
                                draft = BotAppearance(shape: BotAvatarShape.allCases.randomElement() ?? .hexagon,
                                                      color: BotAppearance.colors.filter { $0 != "white" }.randomElement() ?? "purple")
                                reset = false
                            }.buttonStyle(.bordered)
                        }
                        shapes
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                            ForEach(BotAppearance.colors, id: \.self) { color in
                                Button { draft.color = color; draft.imageData = nil; reset = false } label: {
                                    Circle().fill(AvatarArtwork.color(color)).frame(width: 30, height: 30)
                                        .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                                        .padding(5).overlay(Circle().stroke(draft.color == color && draft.imageData == nil ? Color.primary.opacity(0.4) : .clear, lineWidth: 1.5))
                                }.buttonStyle(.plain).accessibilityLabel(color.capitalized)
                                    .accessibilityAddTraits(draft.color == color ? [.isSelected] : [])
                            }
                        }
                    }.padding(18)
                }.frame(maxHeight: 430)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.primary.opacity(0.08), lineWidth: 1))
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Button(saving ? "Saving…" : "Save avatar") {
                saving = true; error = nil
                Task {
                    if await save(reset ? nil : draft) { close() }
                    else { error = "The avatar could not be saved. Check your connection and try again." }
                    saving = false
                }
            }.buttonStyle(.borderedProminent).disabled(saving)
        }.padding(18)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get()
                draft.imageData = try AvatarArtwork.importImage(url); reset = false; error = nil; tab = "Bot"
            } catch { self.error = error.localizedDescription }
        }
    }

    private var shapes: some View {
        VStack(spacing: 18) {
            ForEach(0..<3) { row in
                HStack(spacing: 8) {
                    ForEach(Array(BotAvatarShape.allCases.dropFirst(row * 5).prefix(5)), id: \.self) { shape in
                        Button { draft.shape = shape; draft.imageData = nil; reset = false } label: {
                            CustomBotAvatar(appearance: BotAppearance(shape: shape, color: draft.color), size: 38)
                                .padding(4).overlay(RoundedRectangle(cornerRadius: 15).stroke(draft.shape == shape && draft.imageData == nil ? Color.primary.opacity(0.35) : .clear, lineWidth: 1.5))
                        }.buttonStyle(.plain).accessibilityLabel(shape.label)
                            .accessibilityAddTraits(draft.shape == shape ? [.isSelected] : [])
                    }
                }
            }
        }
    }
}
