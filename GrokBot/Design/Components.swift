import SwiftUI

enum Palette {
    static let background = Color(uiColor: .systemBackground)
    static let card = Color(uiColor: .secondarySystemBackground)
    static func bot(_ name: String) -> Color {
        switch name {
        case "purple": Color(red: 0.57, green: 0.32, blue: 1)
        case "pink": Color(red: 1, green: 0.16, blue: 0.6)
        case "ochre": Color(red: 0.64, green: 0.43, blue: 0.23)
        default: Color.primary
        }
    }
}

/// Original vector artwork. No proprietary assets are bundled.
struct BotAvatar: View {
    var color = "white"
    var size: CGFloat = 48
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.36)
                .fill(Palette.bot(color))
                .rotationEffect(.degrees(color == "pink" ? -12 : -20))
            HStack(spacing: size * 0.12) {
                Capsule().frame(width: size * 0.1, height: size * 0.26)
                Capsule().frame(width: size * 0.1, height: size * 0.26)
            }
            .foregroundStyle(Color(uiColor: .systemBackground))
            .rotationEffect(.degrees(-25))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PreviewBanner: View {
    var body: some View {
        Label("OFFLINE PREVIEW · LOCAL DATA", systemImage: "iphone.slash")
            .font(.caption2.weight(.semibold))
            .tracking(1.1)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Palette.card)
            .accessibilityLabel("Offline preview. All data stays on this device. No connection to Grok Bot.")
    }
}

struct RoundButton: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 46, height: 46)
                .glassChrome(in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct StatusCard: View {
    var title: String
    var detail: String
    var symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
    }
}
