import SwiftUI
import UIKit

/// Centralized toggleable haptic feedback helper (controlled in Settings).
enum Haptics {
    static let enabledKey = "wt16.haptics.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func light() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func heavy() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func soft(_ intensity: CGFloat = 0.5) {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: intensity)
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// Upstream Waytrace visual components adapted for iOS 16.0+.

struct WaytraceCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

/// 2x2 grouped metric card separated by hairlines (matches upstream MetricGrid).
struct MetricGrid2x2<T1: View, T2: View, T3: View, T4: View>: View {
    let topLeft: T1
    let topRight: T2
    let bottomLeft: T3
    let bottomRight: T4

    init(
        @ViewBuilder topLeft: () -> T1,
        @ViewBuilder topRight: () -> T2,
        @ViewBuilder bottomLeft: () -> T3,
        @ViewBuilder bottomRight: () -> T4
    ) {
        self.topLeft = topLeft()
        self.topRight = topRight()
        self.bottomLeft = bottomLeft()
        self.bottomRight = bottomRight()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                topLeft.frame(maxWidth: .infinity, alignment: .leading)
                Divider().padding(.vertical, 14)
                topRight.frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            Divider().padding(.horizontal, 16)
            HStack(spacing: 0) {
                bottomLeft.frame(maxWidth: .infinity, alignment: .leading)
                Divider().padding(.vertical, 14)
                bottomRight.frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var showsChevron: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if showsChevron {
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct PlaceIcon: View {
    let category: PlaceCategory
    var isLandmark = false
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: isLandmark ? "star.fill" : category.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().fill((isLandmark ? Color.yellow : category.tint).gradient))
    }
}

struct PulsingDot: View {
    var color: Color = .green
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .background(
                Circle()
                    .fill(color.opacity(0.4))
                    .scaleEffect(animate ? 2.6 : 1)
                    .opacity(animate ? 0 : 1)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: animate)
            )
            .onAppear {
                animate = true
            }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

/// Top-right avatar button that opens Settings sheet, matching upstream Waytrace.
struct ProfileToolbarButton: View {
    @Binding var showingSettings: Bool
    @AppStorage("wt16.profile.name") private var profileName: String = "F"

    var body: some View {
        Button {
            Haptics.selection()
            showingSettings = true
        } label: {
            let initial = String(profileName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased().nilIfEmpty ?? "F"
            Text(initial)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.14, green: 0.62, blue: 1.0), Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )
        }
        .accessibilityLabel("设置")
    }
}
