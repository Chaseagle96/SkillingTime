import SwiftUI

struct LaunchMotionPlan: Equatable, Sendable {
    let ignitionDelayNanoseconds: UInt64
    let wordmarkDelayNanoseconds: UInt64
    let dismissalDelayNanoseconds: UInt64
    let usesSpatialMotion: Bool

    static func make(hasPlayed: Bool, reduceMotion: Bool) -> LaunchMotionPlan {
        if reduceMotion {
            return LaunchMotionPlan(
                ignitionDelayNanoseconds: 0,
                wordmarkDelayNanoseconds: 0,
                dismissalDelayNanoseconds: 80_000_000,
                usesSpatialMotion: false
            )
        }

        if hasPlayed {
            return LaunchMotionPlan(
                ignitionDelayNanoseconds: 25_000_000,
                wordmarkDelayNanoseconds: 75_000_000,
                dismissalDelayNanoseconds: 230_000_000,
                usesSpatialMotion: true
            )
        }

        return LaunchMotionPlan(
            ignitionDelayNanoseconds: 90_000_000,
            wordmarkDelayNanoseconds: 200_000_000,
            dismissalDelayNanoseconds: 520_000_000,
            usesSpatialMotion: true
        )
    }
}

enum SkillingTimeMotion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let responsive = Animation.spring(response: 0.36, dampingFraction: 0.84)
    static let progress = Animation.easeOut(duration: 0.42)
    static let ceremonial = Animation.spring(response: 0.62, dampingFraction: 0.78)
    static let gentle = Animation.easeInOut(duration: 0.30)

    static func animation(
        _ animation: Animation,
        reduceMotion: Bool
    ) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func revealDelayNanoseconds(order: Int) -> UInt64 {
        UInt64(min(max(order, 0), 10)) * 55_000_000
    }
}

struct SkillingTimePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(
                SkillingTimeMotion.animation(
                    SkillingTimeMotion.quick,
                    reduceMotion: reduceMotion
                ),
                value: configuration.isPressed
            )
    }
}

private struct SkillingTimeRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let order: Int
    let trigger: Bool

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: reduceMotion || isVisible ? 0 : 12)
            .scaleEffect(reduceMotion || isVisible ? 1 : 0.985)
            .task(id: trigger) {
                guard trigger, !isVisible else { return }

                if reduceMotion {
                    isVisible = true
                    return
                }

                let delay = SkillingTimeMotion.revealDelayNanoseconds(order: order)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled else { return }
                withAnimation(SkillingTimeMotion.responsive) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func skillingTimeReveal(
        order: Int = 0,
        trigger: Bool = true
    ) -> some View {
        modifier(SkillingTimeRevealModifier(order: order, trigger: trigger))
    }
}
