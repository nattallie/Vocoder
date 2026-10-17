import SwiftUI

// MARK: - Card grouping

struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
        .depthShadow()
    }
}

// MARK: - Bouncy button styles (scale-on-press, explicit tint so it composes predictably)

struct BouncyProminentButtonStyle: ButtonStyle {
    var tint: Color = Theme.indigo
    /// Most buttons use the indigo->teal brand gradient; pass false for a one-off
    /// solid color (e.g. the record sheet's red "Save").
    var useGradient: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(useGradient ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(tint))
            )
            .shadow(
                color: tint.opacity(configuration.isPressed ? 0.18 : 0.4),
                radius: configuration.isPressed ? 5 : 12,
                x: 0, y: configuration.isPressed ? 2 : 6
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct BouncyBorderedButtonStyle: ButtonStyle {
    var tint: Color = Theme.indigo

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tint.opacity(0.14)))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Channel count control: four bars that fill up to the selected count

struct ChannelBarsControl: View {
    let options: [Int]
    @Binding var selectedIndex: Int

    /// Plain `.onTapGesture` doesn't respect the ambient `.disabled()` modifier the
    /// way `Button` does -- reading `isEnabled` directly and guarding on it makes
    /// `.disabled(...)` on this control actually block taps, not just dim it visually.
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(options.indices, id: \.self) { index in
                let lit = index <= selectedIndex
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(lit ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.secondary.opacity(0.18)))
                        .frame(height: barHeight(for: index))
                        .shadow(color: lit ? Theme.indigo.opacity(0.4) : .clear, radius: 5, x: 0, y: 3)
                    Text("\(options[index])")
                        .font(.caption2)
                        .fontWeight(index == selectedIndex ? .bold : .regular)
                        .foregroundStyle(index == selectedIndex ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isEnabled, selectedIndex != index else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedIndex = index
                    }
                }
            }
        }
        .frame(height: 96)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let minHeight: CGFloat = 26
        let maxHeight: CGFloat = 72
        guard options.count > 1 else { return maxHeight }
        let t = CGFloat(index) / CGFloat(options.count - 1)
        return minHeight + t * (maxHeight - minHeight)
    }
}

// MARK: - Clip chip (bundled or user-added source)

struct ClipChip: View {
    let source: AudioSource
    let isSelected: Bool
    let action: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: source.iconName)
                    .font(.title2)
                Text(source.name)
                    .font(.caption)
                    .lineLimit(1)
            }
            .frame(width: 88, height: 66)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(.regularMaterial))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(
                color: isSelected ? Theme.indigo.opacity(0.4) : .black.opacity(0.08),
                radius: isSelected ? 10 : 5, x: 0, y: isSelected ? 5 : 3
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .contextMenu {
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - "Now playing" equalizer-style indicator

struct PlayingIndicator: View {
    var color: Color = Theme.teal
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: animate ? 18 : 7)
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .frame(height: 20)
        .onAppear { animate = true }
    }
}

// MARK: - Stable-layout playback button label

/// A button label (icon + text + optional trailing accessory) that never reflows when
/// its state changes -- the icon and the accessory each sit in a fixed-size slot, and
/// the whole row is leading-aligned. Without this, swapping between idle/processing/
/// playing content (an equalizer or spinner popping in from nothing, text changing
/// length) shifted everything sideways -- a visible "jump" on tap, worse once that
/// transition stopped being animated (animating it caused a different glitch: old and
/// new content cross-fading with overlapping text).
struct PlaybackButtonLabel: View {
    enum Accessory {
        case none
        case equalizer(Color)
    }

    let icon: String
    let text: String
    var accessory: Accessory = .none

    var body: some View {
        // Centered, not leading-aligned: with the icon and accessory each already
        // pinned to a fixed-size slot (below), total content width barely changes
        // between states (only the text itself varies by a few characters), so
        // centering looks balanced/consistent -- leading-aligning it instead left a
        // large, uneven empty gutter on the right whenever the accessory was empty.
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
            Text(text)
            Group {
                switch accessory {
                case .none:
                    Color.clear
                case .equalizer(let color):
                    PlayingIndicator(color: color)
                }
            }
            .frame(width: 20, height: 20)
        }
    }
}
