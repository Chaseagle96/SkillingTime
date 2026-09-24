import SwiftData
import SwiftUI

// MARK: - Profile

@MainActor
enum ProfileService {
    static func ensureProfile(in modelContext: ModelContext, now: Date = .now) throws -> CharacterProfile {
        if let existing = try modelContext.fetch(FetchDescriptor<CharacterProfile>()).first {
            return existing
        }
        let profile = CharacterProfile(createdAt: now)
        modelContext.insert(profile)
        return profile
    }
}

enum ProfileDestination: String, Identifiable {
    case achievements
    case milestones
    case retiredSkills
    case backup
    case settings

    var id: String { rawValue }
}

/// The profile button in the top-right corner. Everything that isn't the Skills
/// themselves lives in this one small menu.
struct ProfileMenuButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var profiles: [CharacterProfile]

    let lifetimeLevel: Int
    let hasRetiredSkills: Bool
    @Binding var columnCount: Int
    let open: (ProfileDestination) -> Void

    init(
        lifetimeLevel: Int,
        hasRetiredSkills: Bool,
        columnCount: Binding<Int>,
        open: @escaping (ProfileDestination) -> Void
    ) {
        self.lifetimeLevel = lifetimeLevel
        self.hasRetiredSkills = hasRetiredSkills
        _columnCount = columnCount
        self.open = open
    }

    var body: some View {
        let profile = profiles.first
        Menu {
            Section("\(profile?.displayName ?? "The Practitioner") · Lifetime Level \(lifetimeLevel)") {
                Button {
                    open(.achievements)
                } label: {
                    Label("Achievements", systemImage: "trophy.fill")
                }
                Button {
                    open(.milestones)
                } label: {
                    Label("Milestones", systemImage: "scroll.fill")
                }
            }

            Section {
                Picker(selection: $columnCount) {
                    ForEach(SkillbookLayout.columnOptions, id: \.self) { count in
                        Label(SkillbookLayout.label(for: count), systemImage: SkillbookLayout.symbol(for: count))
                            .tag(count)
                    }
                } label: {
                    Label("Skill Layout", systemImage: SkillbookLayout.symbol(for: columnCount))
                }
                .pickerStyle(.menu)

                if hasRetiredSkills {
                    Button {
                        open(.retiredSkills)
                    } label: {
                        Label("Retired Skills", systemImage: "archivebox")
                    }
                }
            }

            Section {
                Button {
                    open(.backup)
                } label: {
                    Label("Backup & Data", systemImage: "externaldrive")
                }
                Button {
                    open(.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        } label: {
            ProfileAvatar(
                symbolName: profile?.crestSymbolName ?? "person.fill",
                accentHex: profile?.accentHex ?? "D2A84A"
            )
        }
        .accessibilityLabel("Profile, Lifetime Level \(lifetimeLevel)")
    }
}

private struct ProfileAvatar: View {
    let symbolName: String
    let accentHex: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: accentHex).opacity(0.18))
            Circle()
                .strokeBorder(Color(hex: accentHex).opacity(0.7), lineWidth: 1.2)
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: accentHex))
        }
        .frame(width: 30, height: 30)
    }
}

// MARK: - Hero cards

/// Small, swipeable stat cards above the Skill grid.
struct SkillbookHeroCards: View {
    let lifetimeLevel: Int
    let snapshot: WidgetSnapshot
    let totalSeconds: Int
    let sessionCount: Int
    let activeSkillCount: Int
    let canStart: Bool
    let startSkill: (UUID) -> Void

    private var weekSeconds: Int { snapshot.weekDaySeconds.reduce(0, +) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                card(title: "Lifetime Level", systemImage: "chevron.up.2") {
                    Text(lifetimeLevel.formatted())
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                    Text("\(activeSkillCount) active \(activeSkillCount == 1 ? "Skill" : "Skills")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let next = snapshot.closestToLevel, let seconds = next.secondsToNextLevel {
                    upNextCard(next, seconds: seconds)
                }

                card(title: "Today", systemImage: "sun.max.fill") {
                    Text(DurationText.compact(snapshot.todaySeconds))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("\(snapshot.todayXP.formatted()) XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                card(title: "This Week", systemImage: "calendar") {
                    Text(DurationText.compact(weekSeconds))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    WeekBars(values: snapshot.weekDaySeconds)
                }

                card(title: "All Time", systemImage: "hourglass") {
                    Text(DurationText.compact(totalSeconds))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("\(sessionCount.formatted()) \(sessionCount == 1 ? "session" : "sessions")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
    }

    private func card<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(SkillingTimeTheme.gold)
                .lineLimit(1)
            Spacer(minLength: 0)
            content()
        }
        .frame(width: 138, height: 92, alignment: .topLeading)
        .padding(12)
        .background(
            Color.white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func upNextCard(_ skill: WidgetSkillSummary, seconds: Int) -> some View {
        Button {
            startSkill(skill.id)
        } label: {
            card(title: "Up Next", systemImage: "arrow.up.forward.circle.fill") {
                HStack(spacing: 6) {
                    Image(systemName: skill.symbolName)
                        .foregroundStyle(Color(hex: skill.accentHex))
                    Text(skill.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                HStack {
                    Text("\(DurationText.compact(seconds)) to Lv \(skill.level + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if canStart {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(Color(hex: skill.accentHex))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
        .accessibilityHint(canStart ? "Starts a \(skill.name) session" : "")
    }
}

private struct WeekBars: View {
    let values: [Int]

    var body: some View {
        let peak = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, seconds in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index == values.count - 1 ? SkillingTimeTheme.gold : Color.white.opacity(0.3))
                    .frame(width: 8, height: max(3, 18 * CGFloat(seconds) / CGFloat(peak)))
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var notificationManager: ProgressionNotificationManager
    @AppStorage(SkillbookLayout.storageKey) private var columnCount = SkillbookLayout.defaultColumnCount
    @Query private var profiles: [CharacterProfile]

    @State private var displayName = "The Practitioner"
    @State private var crestSymbolName = "person.fill"
    @State private var accentHex = "D2A84A"
    @State private var saveError: String?

    private let crests = [
        "person.fill", "shield.fill", "crown.fill", "seal.fill",
        "star.circle.fill", "sparkles", "flame.fill", "book.closed.fill"
    ]
    private let accents = ["D2A84A", "D97A43", "C85E5E", "8A72B5", "55A7A2", "A96AA2"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $displayName)
                        .textInputAutocapitalization(.words)
                }

                Section("Crest") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 4),
                        spacing: 12
                    ) {
                        ForEach(crests, id: \.self) { symbol in
                            Button {
                                crestSymbolName = symbol
                                Haptics.selection()
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title2)
                                    .frame(width: 48, height: 48)
                                    .background(
                                        crestSymbolName == symbol
                                            ? Color(hex: accentHex).opacity(0.18)
                                            : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(SymbolNames.label(for: symbol))
                            .accessibilityAddTraits(crestSymbolName == symbol ? .isSelected : [])
                        }
                    }
                }

                Section("Accent") {
                    HStack {
                        ForEach(accents, id: \.self) { hex in
                            Button {
                                accentHex = hex
                                Haptics.selection()
                            } label: {
                                ZStack {
                                    Circle().fill(Color(hex: hex))
                                    if accentHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(SymbolNames.colorLabel(for: hex))
                            .accessibilityAddTraits(accentHex == hex ? .isSelected : [])
                        }
                    }
                }

                Section {
                    Picker("Skill Layout", selection: $columnCount) {
                        ForEach(SkillbookLayout.columnOptions, id: \.self) { count in
                            Text(SkillbookLayout.label(for: count)).tag(count)
                        }
                    }
                } header: {
                    Text("Skills")
                } footer: {
                    Text("You can also pinch the Skill grid: pinch out for larger cards, down to a list, and pinch in for more, up to four columns.")
                }

                Section {
                    progressionAlertsControl
                } header: {
                    Text("Level-Up Alerts")
                } footer: {
                    Text("Notify me when a running session reaches the next level or Mastery star. Applies immediately.")
                }

                if let saveError {
                    Section("Could Not Save") {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(
                            displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
            .task {
                // Load the saved profile before any await so an early edit is never
                // overwritten when the authorization check returns.
                if let profile = profiles.first {
                    displayName = profile.displayName
                    crestSymbolName = profile.crestSymbolName
                    accentHex = profile.accentHex
                }
                await notificationManager.refreshAuthorizationStatus()
            }
        }
    }

    @ViewBuilder
    private var progressionAlertsControl: some View {
        if notificationManager.authorizationStatus == .denied {
            Button("Open Notification Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
        } else if notificationManager.alertsEnabled {
            Button("Turn Off Level-Up Alerts", role: .destructive) {
                notificationManager.disableAlerts()
            }
        } else {
            Button("Turn On Level-Up Alerts") {
                Task { await notificationManager.enableAlerts() }
            }
        }
    }

    private func save() {
        do {
            let profile = try ProfileService.ensureProfile(in: modelContext)
            profile.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.crestSymbolName = crestSymbolName
            profile.accentHex = accentHex
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
        }
    }
}

/// Backup and restore on their own screen, reached from the profile menu.
struct BackupDataView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                BackupSettingsSection()
            }
            .navigationTitle("Backup & Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
