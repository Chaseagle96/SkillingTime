# Skilling Time 0.3: Beyond the Screen

Skilling Time is a native, local-first iOS app that turns real activity into persistent RPG-style Skills. Version 0.3 extends the active-session loop into the system UI, makes long-lived history reads effectively constant-time, and turns the Level 50 reward into a functional identity choice.

**Brand migration:** the product, Xcode project, targets, app entry point, widgets, and user-facing app metadata are now **Skilling Time**. The in-app collection of Skills remains intentionally named the **Skillbook**. Legacy bundle/App Group/store identifiers remain unchanged so existing sideloaded installs can upgrade without losing history.

## What is new in 0.3

- A WidgetKit extension presents the active Skill on the Lock Screen and Dynamic Island.
- Live Activity controls pause or resume without opening Skilling Time; Finish deep-links into the recoverable correction flow before anything is committed.
- The app and extension share only the active timer through an App Group. Completed history remains in SwiftData inside the app.
- Both bundles include privacy manifests declaring their app-owned/App Group `UserDefaults` access; no data collection or tracking is declared.
- Optional local notifications announce the next level or Mastery-star threshold. Alerts are scheduled from timestamps, canceled while paused, and recalculated after resume—including Live Activity actions.
- iOS 26 uses the native, Liquid Glass-compatible tab-bar bottom accessory and adapts its layout when the tab bar becomes inline. iOS 17–25 retain the existing overlay.
- `SkillLedger` stores rebuildable per-Skill aggregates for fast Skillbook, Character, Chronicle progression, mini-session, and active-session reads.
- `SkillSession` history remains authoritative. Ledgers are updated in the same transaction as commits, corrections, and deletions. Launch performs a cheap integrity check and scans history only when a rebuild is needed.
- SwiftData schema v3 adds ledgers and specializations through an explicit v2-to-v3 lightweight migration.
- Level 50 now unlocks a persistent Journeyman Specialization: a suggested or custom title that appears throughout the Skillbook but never changes XP.
- Timer recovery tests now cover pending finishes across relaunch and pause/resume actions originating in shared storage.

Version 0.3 retains the v0.2 integrity work: frozen finish chronology, idempotent session commits, editable history, append-only reward records, curve-version routing, ceremonial outcomes, Level 25 Focus Goals, and lifetime semantics for retired Skills.

The deterministic v1 progression economy is unchanged: 20 XP per active minute, Levels 1 through 100, milestone ranks at 25/50/75/100, and unlimited Mastery stars beyond Level 100.

## Data boundaries

Completed sessions are still the source of truth; XP and levels are derived.

```text
timer or manual entry
    -> SessionCommitService
    -> validate and mutate SkillSession history
    -> resolve rewards
    -> reconcile SkillLedger
    -> save once
    -> SessionOutcome
```

`SkillLedger` is acceleration data, not progression authority. Startup can recreate every ledger by scanning `SkillSession` history. `AchievementUnlock` and `ChronicleUnlock` remain permanent, dated records even when a triggering session is later corrected or deleted.

The App Group contains only the recoverable `ActiveSessionSnapshot` and the progression-alert preference. The Live Activity never writes completed sessions or XP counters.

## Requirements

- Xcode 26.2 or newer (required to compile the current `tabViewBottomAccessory(isEnabled:content:)` path)
- iOS 17.0 or newer
- A physical iPhone for final Live Activity, Dynamic Island, notification, migration, and sideload validation
- No third-party runtime dependencies

The app still runs on iOS 17–25; the iOS 26 tab accessory is availability-gated and the earlier overlay remains the fallback.

## Run and migrate

1. Back up an existing v0.1 or v0.2 app container before the first physical migration test.
2. Open `SkillingTime.xcodeproj` in Xcode 26.2 or newer.
3. Select the shared **SkillingTime** scheme.
4. In **Signing & Capabilities**, choose the same Apple Developer team for `SkillingTime` and `SkillingTimeWidgets`.
5. Register or change the App Group `group.com.projectskillbook.app` for both targets if the bundle IDs are customized.
6. Run `SkillingTimeTests`, then install on a physical iPhone.

On first launch, SwiftData migrates older stores to schema v3, preserves all sessions and unlock records, and rebuilds missing ledgers from completed history. Later launches skip the history scan while ledger counts remain coherent. No migration changes the v1 XP curve.

## Signing and SideStore gate

The new extension is entitlement-sensitive. A sideloaded build needs provisioning for all three identifiers:

- `com.projectskillbook.app`
- `com.projectskillbook.app.SkillingTimeWidgets`
- `group.com.projectskillbook.app`

Validate the complete archive on the actual SideStore setup before distributing it. Confirm that the extension is embedded, both targets share the App Group entitlement, pause/resume survives a locked-screen round trip, Finish opens the correction sheet, and migration preserves a copy of real v0.2 history. If a signing service cannot provision App Groups or extension App IDs, the Live Activity target cannot safely share timer state with the app.

## Tests

The test suite covers:

- frozen v1 XP thresholds, multi-level crossings, milestones, and Mastery
- finish-time freezing, idempotent retries, timer restoration, and pending-finish relaunch
- shared-store pause and resume lifecycle behavior
- exact next-threshold notification planning and paused-session cancellation semantics
- Focus Goal evaluation and Level 50 capability resolution
- cross-midnight Quest attribution and lifetime retired-Skill levels
- chronological, append-only Achievement and Chronicle records
- transactional ledger updates during commit and deletion
- full ledger rebuilds, stale-row removal, and exact aggregate/index values

## Intentionally deferred

Version 0.3 does not add Level 75 Master Challenges, a larger Level 100 Legacy editor, personalized Quest generation, cloud accounts, social systems, monetization, or an Apple Watch app. Those systems should build on verified migration, extension signing, and multi-year performance behavior instead of expanding the progression economy first.

## Validation note

This delivery can validate Swift syntax structure, project references, plist/XML structure, target membership, asset catalogs, and ZIP integrity outside macOS. A definitive compiler pass, SwiftData migration against a real historical store, simulator run, notification authorization flow, and signed-device/SideStore test require Xcode and Apple’s iOS SDK on macOS.

## GitHub Actions unsigned IPA with Live Activity

The workflow at `.github/workflows/build-ios.yml` performs a genuine Apple-SDK device build on a GitHub-hosted macOS runner. It builds both the `SkillingTime` application and `SkillingTimeWidgets` WidgetKit extension with signing disabled, packages them into an unsigned IPA, and fails the build if `Payload/SkillingTime.app/PlugIns/SkillingTimeWidgets.appex` is absent.

This is required for Lock Screen Live Activities and Dynamic Island presentation. The Linux compatibility IPA cannot provide WidgetKit/ActivityKit extension UI because it does not contain an Apple-compiled `.appex`.
