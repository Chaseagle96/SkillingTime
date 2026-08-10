import SwiftData
import SwiftUI

struct SkillbookView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionController: SessionController
    @Query(sort: \LifeSkill.sortOrder) private var allSkills: [LifeSkill]
    @Query private var ledgers: [SkillLedger]
    @Query private var specializations: [SkillSpecialization]

    @State private var showingCreateSkill = false
    @State private var showingRetiredSkills = false
    @State private var editingSkill: LifeSkill?
    @State private var persistenceError: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var activeSkills: [LifeSkill] {
        allSkills.filter { !$0.isArchived }
    }

    private var retiredSkills: [LifeSkill] {
        allSkills.filter(\.isArchived)
    }

    var body: some View {
        let index = SessionAnalytics.index(ledgers: ledgers)
        let lifetimeTotalLevel = SessionAnalytics.totalLevel(
            skills: allSkills,
            index: index
        )

        ScrollView {
            VStack(spacing: 18) {
                characterHeader(
                    index: index,
                    lifetimeTotalLevel: lifetimeTotalLevel
                )

                if activeSkills.isEmpty {
                    EmptyStateCard(
                        systemImage: "sparkles.rectangle.stack",
                        title: "Your active Skillbook is waiting",
                        message: retiredSkills.isEmpty
                            ? "Create a Skill for anything you want to practice, maintain, or master."
                            : "Restore a retired Skill or create a new path. Your lifetime history remains preserved."
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(activeSkills) { skill in
                            NavigationLink {
                                SkillDetailView(skill: skill)
                            } label: {
                                SkillCard(
                                    skill: skill,
                                    totalSeconds: index.statistics(for: skill.id).totalSeconds,
                                    specializationTitle: specializations.first {
                                        $0.skillID == skill.id
                                    }?.title
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
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
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .navigationTitle("Skillbook")
        .toolbar {
            if !retiredSkills.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingRetiredSkills = true
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .accessibilityLabel("Retired Skills")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreateSkill = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Skill")
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
        .sheet(isPresented: $showingRetiredSkills) {
            RetiredSkillsView()
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

    private func characterHeader(
        index: SessionIndex,
        lifetimeTotalLevel: Int
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(SkillingTimeTheme.gold.opacity(0.13))
                Circle()
                    .strokeBorder(SkillingTimeTheme.gold.opacity(0.55), lineWidth: 1.5)
                Image(systemName: "book.closed.fill")
                    .font(.title2)
                    .foregroundStyle(SkillingTimeTheme.gold)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR SKILLBOOK")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(SkillingTimeTheme.gold)
                Text(
                    "\(activeSkills.count) active · \(DurationText.compact(index.totalSeconds)) lifetime"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(lifetimeTotalLevel.formatted())
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("LIFETIME LEVEL")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            Color.white.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(SkillingTimeTheme.gold.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func move(_ skill: LifeSkill, offset: Int) {
        var reordered = activeSkills
        guard let index = reordered.firstIndex(where: { $0.id == skill.id }) else { return }
        let destination = index + offset
        guard reordered.indices.contains(destination) else { return }
        reordered.swapAt(index, destination)
        for (sortOrder, item) in reordered.enumerated() {
            item.sortOrder = sortOrder
        }
        saveSkillChanges()
    }

    private func archive(_ skill: LifeSkill) {
        guard sessionController.activeSession?.skillID != skill.id else {
            persistenceError = "Finish or discard the active session before retiring this Skill."
            return
        }
        skill.isArchived = true
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

private struct SkillCard: View {
    let skill: LifeSkill
    let totalSeconds: Int
    let specializationTitle: String?

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

    var body: some View {
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
                Text(
                    specializationTitle.map {
                        "\(progress.displayRank) · \($0)"
                    } ?? progress.displayRank
                )
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
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.065), accent.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
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
    @Binding var selectedPath: CharacterPath

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

        Section {
            Picker("Path", selection: $selectedPath) {
                ForEach(CharacterPath.allCases) { path in
                    Label(path.title, systemImage: path.systemImage)
                        .tag(path)
                }
            }
        } header: {
            Text("Character Path")
        } footer: {
            Text(selectedPath.description)
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
                    .accessibilityLabel(
                        symbol.replacingOccurrences(of: ".fill", with: "")
                    )
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
                    .accessibilityLabel("Accent color")
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
    @State private var selectedPath = CharacterPath.stewardship
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                SkillIdentitySections(
                    name: $name,
                    category: $category,
                    selectedSymbol: $selectedSymbol,
                    selectedColor: $selectedColor,
                    selectedPath: $selectedPath
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
        CharacterProgressionService.recordInitialAssignment(
            skill: skill,
            path: selectedPath,
            in: modelContext
        )

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            saveError = error.localizedDescription
            return
        }

        do {
            try RewardBackfillService.reconcileAll(in: modelContext)
            try CharacterProgressionService.prepare(in: modelContext)
            _ = try QuestBoardService.prepareCurrentBoard(in: modelContext)
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
    @Query private var pathAssignments: [SkillPathAssignment]

    @State private var name: String
    @State private var category: String
    @State private var selectedSymbol: String
    @State private var selectedColor: String
    @State private var selectedPath: CharacterPath
    @State private var isArchived: Bool
    @State private var saveError: String?

    init(skill: LifeSkill) {
        self.skill = skill
        _name = State(initialValue: skill.name)
        _category = State(initialValue: skill.category)
        _selectedSymbol = State(initialValue: skill.symbolName)
        _selectedColor = State(initialValue: skill.accentHex)
        _selectedPath = State(initialValue: CharacterProgressionEngine.suggestedPath(for: skill))
        _isArchived = State(initialValue: skill.isArchived)
        let skillID = skill.id
        _pathAssignments = Query(
            filter: #Predicate<SkillPathAssignment> { assignment in
                assignment.skillID == skillID
            },
            sort: \SkillPathAssignment.effectiveFrom
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                SkillIdentitySections(
                    name: $name,
                    category: $category,
                    selectedSymbol: $selectedSymbol,
                    selectedColor: $selectedColor,
                    selectedPath: $selectedPath
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
            .task {
                selectedPath = CharacterProgressionEngine.currentPath(
                    for: skill.id,
                    assignments: pathAssignments
                ) ?? CharacterProgressionEngine.suggestedPath(for: skill)
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
        CharacterProgressionService.changePath(
            skill: skill,
            to: selectedPath,
            assignments: pathAssignments,
            in: modelContext
        )

        do {
            try modelContext.save()
            try CharacterProgressionService.prepare(in: modelContext)
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
