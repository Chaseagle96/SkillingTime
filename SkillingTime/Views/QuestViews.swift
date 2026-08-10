import SwiftData
import SwiftUI

struct QuestListView: View {
    @Query private var sessions: [SkillSession]

    private var quests: [QuestStatus] {
        QuestEngine.currentQuests(sessions: sessions)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 9) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(SkillingTimeTheme.gold)
                    Text("Optional paths, never obligations")
                        .font(.headline)
                    Text("Quests refresh naturally, but unfinished goals never remove XP or erase an accomplishment.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(22)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                ForEach(quests) { quest in
                    QuestCard(quest: quest)
                }

                Text("Daily progress resets at midnight. Weekly progress follows your current calendar and locale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(16)
            .padding(.bottom, 110)
        }
        .navigationTitle("Quests")
        .skillingTimeScreenBackground()
    }
}

private struct QuestCard: View {
    let quest: QuestStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill((quest.isComplete ? SkillingTimeTheme.success : SkillingTimeTheme.gold).opacity(0.12))
                    Image(systemName: quest.isComplete ? "checkmark.seal.fill" : quest.systemImage)
                        .font(.title3)
                        .foregroundStyle(quest.isComplete ? SkillingTimeTheme.success : SkillingTimeTheme.gold)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(quest.title)
                        .font(.headline)
                    Text(quest.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            SkillProgressBar(
                fraction: quest.fractionComplete,
                accent: quest.isComplete ? SkillingTimeTheme.success : SkillingTimeTheme.gold,
                height: 8
            )

            HStack {
                Text(quest.progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if quest.isComplete {
                    Text("COMPLETE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(SkillingTimeTheme.success)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if quest.isComplete {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(SkillingTimeTheme.success.opacity(0.28), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
