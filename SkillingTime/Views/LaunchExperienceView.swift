import SwiftUI

struct LaunchExperienceContainer<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("skillingTime.awakeningLaunchPlayed.v1") private var hasPlayed = false

    @State private var markAwake = false
    @State private var wordmarkVisible = false
    @State private var contentVisible = false
    @State private var overlayVisible = true

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .opacity(contentVisible ? 1 : 0)
                .scaleEffect(
                    reduceMotion || contentVisible ? 1 : 0.992
                )
                .allowsHitTesting(!overlayVisible)
                .accessibilityHidden(overlayVisible)

            if overlayVisible {
                LaunchExperienceView(
                    markAwake: markAwake,
                    wordmarkVisible: wordmarkVisible,
                    usesSpatialMotion: !reduceMotion
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .background(SkillingTimeTheme.background.ignoresSafeArea())
        .task {
            await playLaunchExperience()
        }
    }

    @MainActor
    private func playLaunchExperience() async {
        guard overlayVisible else { return }
        let plan = LaunchMotionPlan.make(
            hasPlayed: hasPlayed,
            reduceMotion: reduceMotion
        )

        await wait(plan.ignitionDelayNanoseconds)
        guard !Task.isCancelled else { return }
        if plan.usesSpatialMotion {
            withAnimation(SkillingTimeMotion.ceremonial) {
                markAwake = true
            }
        } else {
            markAwake = true
        }

        await wait(plan.wordmarkDelayNanoseconds)
        guard !Task.isCancelled else { return }
        withAnimation(
            plan.usesSpatialMotion ? SkillingTimeMotion.responsive : .easeOut(duration: 0.08)
        ) {
            wordmarkVisible = true
        }

        await wait(plan.dismissalDelayNanoseconds)
        guard !Task.isCancelled else { return }
        withAnimation(
            plan.usesSpatialMotion ? SkillingTimeMotion.gentle : .easeOut(duration: 0.10)
        ) {
            contentVisible = true
            overlayVisible = false
        }
        hasPlayed = true
    }

    private func wait(_ nanoseconds: UInt64) async {
        guard nanoseconds > 0 else { return }
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

private struct LaunchExperienceView: View {
    let markAwake: Bool
    let wordmarkVisible: Bool
    let usesSpatialMotion: Bool

    var body: some View {
        ZStack {
            SkillingTimeTheme.background
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    SkillingTimeTheme.gold.opacity(markAwake ? 0.13 : 0),
                    Color(hex: "162033").opacity(markAwake ? 0.58 : 0),
                    SkillingTimeTheme.background
                ],
                center: .center,
                startRadius: 0,
                endRadius: 340
            )
            .ignoresSafeArea()

            ZStack {
                Circle()
                    .strokeBorder(
                        SkillingTimeTheme.gold.opacity(markAwake ? 0.20 : 0),
                        lineWidth: 1
                    )
                    .frame(width: 218, height: 218)
                    .scaleEffect(markAwake && usesSpatialMotion ? 1 : 0.82)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                SkillingTimeTheme.gold.opacity(markAwake ? 0.10 : 0),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 112
                        )
                    )
                    .frame(width: 232, height: 232)

                Image("LaunchMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 176, height: 176)
                    .scaleEffect(markAwake && usesSpatialMotion ? 1.035 : 1)
                    .shadow(
                        color: SkillingTimeTheme.gold.opacity(markAwake ? 0.30 : 0.08),
                        radius: markAwake ? 22 : 8
                    )

                VStack(spacing: 7) {
                    Text("SKILLING TIME")
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .tracking(3.2)
                        .foregroundStyle(SkillingTimeTheme.parchment)
                    Text("TIME BECOMES EXPERIENCE")
                        .font(.caption2.weight(.bold))
                        .tracking(1.7)
                        .foregroundStyle(SkillingTimeTheme.gold.opacity(0.88))
                }
                .offset(y: 148)
                .opacity(wordmarkVisible ? 1 : 0)
                .offset(y: usesSpatialMotion && !wordmarkVisible ? 8 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Skilling Time. Time becomes experience.")
    }
}
