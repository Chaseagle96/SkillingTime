import SwiftData
import SwiftUI

struct SkillbookView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var sessionController: SessionController
    @EnvironmentObject private var presenter: ActiveSessionPresenter
    @Query private var dayLedgers: [ActivityDayLedger]
    @AppStorage(SkillbookLayout.storageKey) private var preferredColumnCount = SkillbookLayout.defaultColumnCount
    @AppStorage(SkillbookLayout.showStatsKey) private var showStats = true
    @Query(sort: \LifeSkill.sortOrder) private var allSkills: [LifeSkill]
    @Query private var ledgers: [SkillLedger]

    @State private var showingCreateSkill = false
    @State private var profileDestination: ProfileDestination?
    @State private var pinchHandled = false
    @State private var editingSkill: LifeSkill?
    @State private var persistenceError: String?
    @Namespace private var skillTransition

    private var columnCount: Int {
        SkillbookLayout.columnCount(
            preferred: preferredColumnCount,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var density: SkillCardDensity {
        SkillCardDensity(columnCount: columnCount)
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: density.spacing),
            count: columnCount
        )
    }

    private var activeSkills: [LifeSkill] {
        allSkills.filter { !$0.isArchived }
    }

    private var retiredSkills: [LifeSkill] {
        allSkills.filter(\.isArchived)
    }

    var body: some View {
        let sessionIndex = SessionAnalytics.index(ledgers: ledgers)
        let lifetimeTotalLevel = SessionAnalytics.totalLevel(
            skills: allSkills,
            index: sessionIndex
        )
        let snapshot = WidgetSnapshotPublisher.make(
            skills: allSkills,
            ledgers: ledgers,
            days: dayLedgers,
            now: .now,
            calendar: .current
        )

        ScrollView {
            VStack(spacing: 16) {
                if showStats {
                    SkillbookHeroCards(
                        lifetimeLevel: lifetimeTotalLevel,
                        snapshot: snapshot,
                        totalSeconds: sessionIndex.totalSeconds,
                        sessionCount: sessionIndex.sessionCount,
                        activeSkillCount: activeSkills.count,
                        canStart: sessionController.activeSession == nil,
                        startSkill: startSkill
                    )
                    .skillingTimeReveal(order: 0)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if activeSkills.isEmpty {
                    EmptyStateCard(
                        systemImage: "sparkles.rectangle.stack",
                        title: "Your active Skillbook is waiting",
                        message: retiredSkills.isEmpty
                            ? "Tap + to create a Skill for anything you want to practice, maintain, or master."
                            : "Tap + to create a Skill, or restore a retired one from your profile. Your history is preserved."
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: density.spacing) {
                        ForEach(
                            Array(activeSkills.enumerated()),
                            id: \.element.id
                        ) { position, skill in
                            skillNavigationLink(
                                skill,
                                totalSeconds: sessionIndex
                                    .statistics(for: skill.id)
                                    .totalSeconds,
                                revealOrder: position + 1
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .simultaneousGesture(pinchToResize)
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingCreateSkill = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Skill")
            }

            ToolbarItem(placement: .topBarTrailing) {
                ProfileMenuButton(
                    lifetimeLevel: lifetimeTotalLevel,
                    hasRetiredSkills: !retiredSkills.isEmpty,
                    columnCount: $preferredColumnCount
                ) { destination in
                    profileDestination = destination
                }
            }
        }
        .sheet(isPresented: $showingCreateSkill) {
            CreateSkillView(
                nextSortOrder: (allSkills.map(\.sortOrder).max() ?? -1) + 1
            )
        }
        .sheet(item: $editingSkill) { skill in
            EditSkillView(skill: skill)
        }
        .sheet(item: $profileDestination) { destination in
            ProfileDestinationView(destination: destination)
        }
        .alert(
            "Skill Not Saved",
            isPresented: Binding(
                get: { persistenceError != nil },
                set: { if !$0 { persistenceError = nil } }
            )
        ) {
            Button("OK") { persistenceError = nil }
        } message: {
            Text(persistenceError ?? "The requested Skill change could not be saved.")
        }
        .skillingTimeScreenBackground()
    }

    /// Pinch out for fewer, larger cards (down to one column); pinch in for more,
    /// smaller cards (up to four). One step per pinch, so a single gesture never
    /// jumps several sizes.
    private var pinchToResize: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.04)
            .onChanged { value in
                guard !pinchHandled else { return }
                if value.magnification >= SkillbookLayout.pinchOutThreshold {
                    stepColumns(by: -1)
                } else if value.magnification <= SkillbookLayout.pinchInThreshold {
                    stepColumns(by: 1)
                }
            }
            .onEnded { _ in
                pinchHandled = false
            }
    }

    private func stepColumns(by delta: Int) {
        pinchHandled = true
        let next = SkillbookLayout.stepped(from: columnCount, by: delta)
        guard next != columnCount else { return }
        withAnimation(
            SkillingTimeMotion.animation(
                SkillingTimeMotion.responsive,
                reduceMotion: reduceMotion
            )
        ) {
            preferredColumnCount = next
        }
        Haptics.selection()
    }

    private func startSkill(_ skillID: UUID) {
        guard sessionController.start(skillID: skillID) else { return }
        Haptics.sessionStart()
        presenter.present(skillID: skillID)
    }

    @ViewBuilder
    private func skillNavigationLink(
        _ skill: LifeSkill,
        totalSeconds: Int,
        revealOrder: Int
    ) -> some View {
        if #available(iOS 18.0, *), !reduceMotion {
            NavigationLink {
                SkillDetailView(skill: skill)
                    .navigationTransition(
                        .zoom(sourceID: skill.id, in: skillTransition)
                    )
            } label: {
                skillCard(skill, totalSeconds: totalSeconds)
            }
            .matchedTransitionSource(id: skill.id, in: skillTransition)
            .buttonStyle(SkillingTimePressStyle())
            .contextMenu { skillContextMenu(skill) }
            .skillingTimeReveal(order: revealOrder)
        } else {
            NavigationLink {
                SkillDetailView(skill: skill)
            } label: {
                skillCard(skill, totalSeconds: totalSeconds)
            }
            .buttonStyle(SkillingTimePressStyle())
            .contextMenu { skillContextMenu(skill) }
            .skillingTimeReveal(order: revealOrder)
        }
    }

    private func skillCard(
        _ skill: LifeSkill,
        totalSeconds: Int
    ) -> some View {
        SkillCard(
            skill: skill,
            density: density,
            totalSeconds: totalSeconds
        )
    }

    @ViewBuilder
    private func skillContextMenu(_ skill: LifeSkill) -> some View {
        Button {
            editingSkill = skill
        } label: {
            Label("Edit Skill", systemImage: "pencil")
        }

        Button {
            move(skill, offset: -1)
        } label: {
            Label("Move Earlier", systemImage: "arrow.up")
        }
        .disabled(activeSkills.first?.id == skill.id)

        Button {
            move(skill, offset: 1)
        } label: {
            Label("Move Later", systemImage: "arrow.down")
        }
        .disabled(activeSkills.last?.id == skill.id)

        Button(role: .destructive) {
            archive(skill)
        } label: {
            Label("Retire Skill", systemImage: "archivebox")
        }
        .disabled(sessionController.activeSession?.skillID == skill.id)
    }

    private func move(_ skill: LifeSkill, offset: Int) {
        var reordered = activeSkills
        guard let index = reordered.firstIndex(where: { $0.id == skill.id }) else { return }
        let destination = index + offset
        guard reordered.indices.contains(destination) else { return }
        withAnimation(
            SkillingTimeMotion.animation(
                SkillingTimeMotion.responsive,
                reduceMotion: reduceMotion
            )
        ) {
            reordered.swapAt(index, destination)
            for (sortOrder, item) in reordered.enumerated() {
                item.sortOrder = sortOrder
            }
        }
        Haptics.selection()
        saveSkillChanges()
    }

    private func archive(_ skill: LifeSkill) {
        guard sessionController.activeSession?.skillID != skill.id else {
            persistenceError = "Finish or discard the active session before retiring this Skill."
            return
        }
        withAnimation(
            SkillingTimeMotion.animation(
                SkillingTimeMotion.responsive,
                reduceMotion: reduceMotion
            )
        ) {
            skill.isArchived = true
        }
        Haptics.selection()
        saveSkillChanges()
    }

    private func saveSkillChanges() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            persistenceError = error.localizedDescription
        }
    }
}

/// Two columns is the full card; three and four trade detail for more Skills on
/// screen. The accessibility label always carries the full description.
enum SkillCardDensity {
    case row
    case regular
    case compact
    case dense

    init(columnCount: Int) {
        switch columnCount {
        case ...1: self = .row
        case 2: self = .regular
        case 3: self = .compact
        default: self = .dense
        }
    }

    var spacing: CGFloat {
        switch self {
        case .row: 10
        case .regular: 12
        case .compact: 10
        case .dense: 8
        }
    }
}

enum SkillbookLayout {
    static let storageKey = "skillbook.grid-columns"
    static let defaultColumnCount = 2
    static let columnOptions = [1, 2, 3, 4]
    static let showStatsKey = "skillbook.show-stats"
    /// Pinch scale that counts as a deliberate pinch out (fewer columns) or in.
    static let pinchOutThreshold: CGFloat = 1.2
    static let pinchInThreshold: CGFloat = 0.83

    /// Clamps a stored preference to a supported value; the largest text sizes
    /// allow at most two columns so names and levels stay readable.
    static func columnCount(preferred: Int, isAccessibilitySize: Bool) -> Int {
        let clamped = min(max(preferred, columnOptions.first ?? 1), columnOptions.last ?? 4)
        return isAccessibilitySize ? min(clamped, 2) : clamped
    }

    /// The next column count one pinch step away, clamped to 1...4.
    static func stepped(from current: Int, by delta: Int) -> Int {
        min(max(current + delta, columnOptions.first ?? 1), columnOptions.last ?? 4)
    }

    static func label(for columnCount: Int) -> String {
        columnCount == 1 ? "List" : "\(columnCount) Columns"
    }

    static func symbol(for columnCount: Int) -> String {
        switch columnCount {
        case ...1: "list.bullet.rectangle"
        case 2: "square.grid.2x2"
        case 3: "square.grid.3x3"
        default: "square.grid.4x3.fill"
        }
    }
}

private struct SkillCard: View {
    let skill: LifeSkill
    var density: SkillCardDensity = .regular
    let totalSeconds: Int

    private var accent: Color { Color(hex: skill.accentHex) }
    private var progress: ProgressSnapshot {
        let xp = ProgressionEngine.xp(
            forActiveSeconds: totalSeconds,
            curveVersion: skill.progressionCurveVersion
        )
        return ProgressionEngine.progress(
            forTotalXP: xp,
            curveVersion: skill.progressionCurveVersion
        )
    }

    private var cornerRadius: CGFloat {
        switch density {
        case .row: 18
        case .regular: 20
        case .compact: 16
        case .dense: 14
        }
    }

    var body: some View {
        Group {
            switch density {
            case .row: rowContent
            case .regular: regularContent
            case .compact: compactContent
            case .dense: denseContent
            }
        }
        .background(
            LinearGradient(
                colors: [Color.primary.opacity(0.065), accent.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    SkillingTimeTheme.rankColor(progress.rank)
                        .opacity(progress.rank == .novice ? 0.13 : 0.34),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(skill.name)
        .accessibilityValue(
            "Level \(progress.level), \(progress.displayRank), \(Int(progress.fractionComplete * 100)) percent to next progression threshold"
        )
        .accessibilityHint("Opens Skill details")
    }

    private var regularContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                SkillGlyph(
                    symbolName: skill.symbolName,
                    color: accent,
                    size: 48,
                    rank: progress.rank
                )
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(progress.level.formatted())
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                    Text("LEVEL")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(skill.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(progress.displayRank)
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(SkillingTimeTheme.rankColor(progress.rank))
                    .lineLimit(1)
            }

            SkillProgressBar(
                fraction: progress.fractionComplete,
                accent: accent,
                height: 7
            )

            HStack {
                Text(DurationText.compact(totalSeconds))
                Spacer()
                Text(
                    progress.level == 100
                        ? "Next star"
                        : "\(progress.xpRemaining.formatted()) XP"
                )
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    /// One column: the most detail, readable at a glance.
    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SkillGlyph(
                    symbolName: skill.symbolName,
                    color: accent,
                    size: 44,
                    rank: progress.rank
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(progress.displayRank)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SkillingTimeTheme.rankColor(progress.rank))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(progress.level.formatted())
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                    Text("LEVEL")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                }
            }

            SkillProgressBar(
                fraction: progress.fractionComplete,
                accent: accent,
                height: 7
            )

            HStack {
                Text("\(DurationText.compact(totalSeconds)) total")
                Spacer()
                Text(
                    progress.level == 100
                        ? "\(DurationText.compact(progress.xpRemaining * 3)) to next star"
                        : "\(DurationText.compact(progress.xpRemaining * 3)) to Level \(progress.level + 1)"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    /// Three columns: glyph and level, name, rank, progress, time.
    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                SkillGlyph(
                    symbolName: skill.symbolName,
                    color: accent,
                    size: 34,
                    rank: progress.rank
                )
                Spacer(minLength: 0)
                Text(progress.level.formatted())
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(progress.displayRank)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(SkillingTimeTheme.rankColor(progress.rank))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            SkillProgressBar(
                fraction: progress.fractionComplete,
                accent: accent,
                height: 5
            )

            Text(DurationText.compact(totalSeconds))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
    }

    /// Four columns: glyph, name, level, and progress only.
    private var denseContent: some View {
        VStack(spacing: 6) {
            SkillGlyph(
                symbolName: skill.symbolName,
                color: accent,
                size: 30,
                rank: progress.rank
            )
            Text(skill.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text("Lv \(progress.level.formatted())")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(SkillingTimeTheme.rankColor(progress.rank))
                .contentTransition(.numericText())
                .lineLimit(1)
            SkillProgressBar(
                fraction: progress.fractionComplete,
                accent: accent,
                height: 4
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }
}

private enum SkillIdentityOptions {
    static let symbols = [
        "sparkles", "frying.pan.fill", "book.closed.fill", "music.note", "pianokeys",
        "paintpalette.fill", "hammer.fill", "wrench.and.screwdriver.fill", "leaf.fill", "figure.run",
        "figure.strengthtraining.traditional", "brain.head.profile", "globe.americas.fill", "character.book.closed.fill",
        "laptopcomputer", "camera.fill", "pawprint.fill", "heart.fill", "cross.fill", "hands.sparkles.fill",
        "house.fill", "car.fill", "tray.full.fill", "shippingbox.fill", "dumbbell.fill", "bicycle"
    ]

    static let colors = [
        "D97A43", "C85E5E", "C96E91", "A96AA2", "8A72B5",
        "5D83C4", "55A7A2", "6D9E58", "D2A84A", "B38255"
    ]
}

private struct SkillIdentitySections: View {
    @Binding var name: String
    @Binding var category: String
    @Binding var selectedSymbol: String
    @Binding var selectedColor: String

    var body: some View {
        Section("Preview") {
            HStack(spacing: 14) {
                SkillGlyph(
                    symbolName: selectedSymbol,
                    color: Color(hex: selectedColor),
                    size: 58
                )
                VStack(alignment: .leading) {
                    Text(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "New Skill"
                            : name
                    )
                    .font(.headline)
                    Text(category.isEmpty ? "Personal" : category)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }

        Section("Identity") {
            TextField("Skill name", text: $name)
                .textInputAutocapitalization(.words)
            TextField("Category", text: $category)
                .textInputAutocapitalization(.words)
        }

        Section("Glyph") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 6),
                spacing: 14
            ) {
                ForEach(SkillIdentityOptions.symbols, id: \.self) { symbol in
                    Button {
                        selectedSymbol = symbol
                        Haptics.selection()
                    } label: {
                        Image(systemName: symbol)
                            .font(.title3)
                            .frame(width: 38, height: 38)
                            .background(
                                selectedSymbol == symbol
                                    ? Color(hex: selectedColor).opacity(0.22)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay {
                                if selectedSymbol == symbol {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            Color(hex: selectedColor),
                                            lineWidth: 1.5
                                        )
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(SymbolNames.label(for: symbol))
                    .accessibilityAddTraits(
                        selectedSymbol == symbol ? .isSelected : []
                    )
                }
            }
            .padding(.vertical, 4)
        }

        Section("Accent") {
            HStack {
                ForEach(SkillIdentityOptions.colors, id: \.self) { color in
                    Button {
                        selectedColor = color
                        Haptics.selection()
                    } label: {
                        ZStack {
                            Circle().fill(Color(hex: color))
                            if selectedColor == color {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(SymbolNames.colorLabel(for: color))
                    .accessibilityAddTraits(
                        selectedColor == color ? .isSelected : []
                    )
                }
            }
        }
    }
}

struct CreateSkillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let nextSortOrder: Int

    @State private var name = ""
    @State private var category = "Personal"
    @State private var selectedSymbol = "sparkles"
    @State private var selectedColor = "D97A43"
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                SkillIdentitySections(
                    name: $name,
                    category: $category,
                    selectedSymbol: $selectedSymbol,
                    selectedColor: $selectedColor
                )

                if let saveError {
                    Section("Not Saved") {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Create Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createSkill() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
        }
    }

    private func createSkill() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let skill = LifeSkill(
            name: trimmedName,
            symbolName: selectedSymbol,
            accentHex: selectedColor,
            category: normalizedCategory,
            sortOrder: nextSortOrder
        )
        modelContext.insert(skill)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
            return
        }

        do {
            try RewardBackfillService.reconcileAll(in: modelContext)
            dismiss()
        } catch {
            saveError = "The Skill was saved, but its global reward history could not be refreshed yet. \(error.localizedDescription)"
        }
    }

    private var normalizedCategory: String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Personal" : trimmed
    }
}

struct EditSkillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionController: SessionController

    let skill: LifeSkill

    @State private var name: String
    @State private var category: String
    @State private var selectedSymbol: String
    @State private var selectedColor: String
    @State private var isArchived: Bool
    @State private var saveError: String?

    init(skill: LifeSkill) {
        self.skill = skill
        _name = State(initialValue: skill.name)
        _category = State(initialValue: skill.category)
        _selectedSymbol = State(initialValue: skill.symbolName)
        _selectedColor = State(initialValue: skill.accentHex)
        _isArchived = State(initialValue: skill.isArchived)
    }

    var body: some View {
        NavigationStack {
            Form {
                SkillIdentitySections(
                    name: $name,
                    category: $category,
                    selectedSymbol: $selectedSymbol,
                    selectedColor: $selectedColor
                )

                Section {
                    Toggle("Retired", isOn: $isArchived)
                        .disabled(sessionController.activeSession?.skillID == skill.id)
                } header: {
                    Text("Skillbook Status")
                } footer: {
                    Text(
                        "Retiring hides this Skill from the active grid without removing its levels, sessions, achievements, Chronicle, or Lifetime Total Level."
                    )
                }

                if let saveError {
                    Section("Not Saved") {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                }
            }
        }
    }

    private func save() {
        skill.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        skill.category = trimmedCategory.isEmpty ? "Personal" : trimmedCategory
        skill.symbolName = selectedSymbol
        skill.accentHex = selectedColor
        skill.isArchived = isArchived

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
        }
    }
}

private struct RetiredSkillsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LifeSkill.sortOrder) private var allSkills: [LifeSkill]

    @State private var saveError: String?

    private var retiredSkills: [LifeSkill] {
        allSkills.filter(\.isArchived)
    }

    var body: some View {
        NavigationStack {
            List {
                if retiredSkills.isEmpty {
                    ContentUnavailableView(
                        "No Retired Skills",
                        systemImage: "archivebox",
                        description: Text("Retired Skills remain part of lifetime history and appear here.")
                    )
                } else {
                    ForEach(retiredSkills) { skill in
                        HStack(spacing: 12) {
                            SkillGlyph(
                                symbolName: skill.symbolName,
                                color: Color(hex: skill.accentHex),
                                size: 42
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.headline)
                                Text(skill.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") {
                                restore(skill)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Retired Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Skill Not Restored",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "The Skill could not be restored.")
            }
        }
    }

    private func restore(_ skill: LifeSkill) {
        skill.isArchived = false
        skill.sortOrder = (allSkills.map(\.sortOrder).max() ?? -1) + 1
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
        }
    }
}

/// What each profile-menu item opens.
private struct ProfileDestinationView: View {
    @Environment(\.dismiss) private var dismiss
    let destination: ProfileDestination

    var body: some View {
        switch destination {
        case .achievements:
            chronicle(.achievements)
        case .milestones:
            chronicle(.milestones)
        case .retiredSkills:
            RetiredSkillsView()
        case .backup:
            BackupDataView()
        case .settings:
            SettingsView()
        }
    }

    private func chronicle(_ section: ChronicleSection) -> some View {
        NavigationStack {
            ChronicleRootView(section: section)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
