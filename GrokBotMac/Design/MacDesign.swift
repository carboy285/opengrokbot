import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

enum MacTheme {
    static let canvas = adaptive(dark: 0x111111, light: 0xFAFAFA)
    static let sidebar = adaptive(dark: 0x0D0D0D, light: 0xF0F0F0)
    static let panel = adaptive(dark: 0x1F1F1F, light: 0xEFEFEF)
    static let raised = adaptive(dark: 0x282828, light: 0xE3E3E3)
    static let secondary = adaptive(dark: 0xA0A0A0, light: 0x686868)
    static let line = Color.primary.opacity(0.09)
    static let userBubble = adaptive(dark: 0x393939, light: 0xDEDEDE)
    static let prominent = adaptive(dark: 0xFFFFFF, light: 0x191919)
    static let onProminent = adaptive(dark: 0x000000, light: 0xFFFFFF)

    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static func botColor(_ name: String) -> Color {
        switch name {
        case "purple": Color(hex: 0x9355FF)
        case "pink": Color(hex: 0xFA2A99)
        case "ochre": Color(hex: 0x9C6C37)
        default: Color.white
        }
    }
}

struct MacBotAvatar: View {
    var color = "white"
    var size: CGFloat = 42
    var starred = false
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if color == "white" {
                    Circle().fill(.white)
                } else if color == "pink" {
                    Circle().fill(MacTheme.botColor(color))
                } else {
                    RoundedRectangle(cornerRadius: size * 0.27)
                        .fill(MacTheme.botColor(color)).rotationEffect(.degrees(-20))
                }
                HStack(spacing: size * 0.13) {
                    Capsule().frame(width: size * 0.10, height: size * 0.25)
                    Capsule().frame(width: size * 0.08, height: size * 0.23).offset(y: -size * 0.09)
                }
                .rotationEffect(.degrees(-26))
                .foregroundStyle(Color(hex: 0x111111))
                .offset(x: size * 0.10, y: -size * 0.12)
            }
            if starred {
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.32, height: size * 0.32)
                    .background(Color.orange, in: Circle())
                    .overlay(Circle().stroke(MacTheme.sidebar, lineWidth: size * 0.05))
                    .offset(x: size * 0.04, y: size * 0.04)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct MacCircleButton: View {
    let symbol: String
    let label: String
    var diameter: CGFloat = 42
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: diameter * 0.4, weight: .regular))
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .glassChrome(in: Circle())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct MacPillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(prominent ? MacTheme.prominent : MacTheme.raised, in: Capsule())
                .foregroundStyle(prominent ? MacTheme.onProminent : Color.primary.opacity(0.88))
        }.buttonStyle(.plain)
    }
}
