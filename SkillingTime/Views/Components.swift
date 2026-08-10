import SwiftUI

struct SkillGlyph: View {
    let symbolName: String
    let color: Color
    var size: CGFloat = 48
    var rank: SkillRank = .novice

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(color.opacity(0.17))

            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [color.opacity(0.95), SkillingTimeTheme.rankColor(rank).opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: rank == .novice ? 1 : 1.6
                )

            if rank == .expert || rank == .master {
                Circle()
                    .strokeBorder(SkillingTimeTheme.rankColor(rank).opacity(0.42), lineWidth: 1)
                    .padding(size * 0.10)
            }

            Image(systemName: symbolName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SkillProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let fraction: Double
    let accent: Color
    var height: CGFloat = 9

    var body: some View {
        let clampedFraction = min(max(fraction, 0), 1)

        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.09))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.78), accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * CGFloat(clampedFraction))
                    .overlay(alignment: .trailing) {
                        Circle()
                            .fill(Color.white.opacity(0.42))
                            .frame(width: height * 0.52, height: height * 0.52)
                            .padding(.trailing, height * 0.24)
                            .opacity(clampedFraction > 0.02 && clampedFraction < 0.995 ? 1 : 0)
                    }
            }
        }
        .frame(height: height)
        .animation(
            SkillingTimeMotion.animation(
                SkillingTimeMotion.progress,
                reduceMotion: reduceMotion
            ),
            value: clampedFraction
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(clampedFraction * 100)) percent")
    }
}

struct MetricCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(SkillingTimeTheme.gold)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(
            SkillingTimeMotion.animation(
                SkillingTimeMotion.quick,
                reduceMotion: reduceMotion
            ),
            value: value
        )
        .accessibilityElement(children: .combine)
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(SkillingTimeTheme.gold)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ParchmentCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(22)
            .foregroundStyle(SkillingTimeTheme.ink)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(SkillingTimeTheme.parchment)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [SkillingTimeTheme.mutedGold, Color(hex: "6D4A2D"), SkillingTimeTheme.mutedGold],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(SkillingTimeTheme.ink.opacity(0.20), lineWidth: 1)
                        .padding(6)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }
}

extension View {
    func skillingTimeScreenBackground() -> some View {
        background(
            LinearGradient(
                colors: [SkillingTimeTheme.background, Color(hex: "111824")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}
