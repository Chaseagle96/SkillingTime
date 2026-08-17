#!/usr/bin/env python3
"""Apply a pinned experimental Apple Watch companion patch to SideStore + AltSign.

This patch intentionally does not invent a watchOS Developer Portal request dialect.
It makes the existing SideStore signing/provisioning pipeline understand the nested
Watch app hierarchy and continues using the same iOS App Development profile request
path SideStore already uses.
"""
from __future__ import annotations

import argparse
from pathlib import Path

SIDESTORE_COMMIT = "e3f3a5b941ce657723a4939c89f2eea63bcfe263"
ALTSIGN_COMMIT = "c0031f042a388a3a2f16549f14c04417a2976765"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def replace_between(text: str, start_marker: str, end_marker: str, new: str, label: str) -> str:
    start = text.find(start_marker)
    if start < 0:
        raise RuntimeError(f"{label}: start marker not found")
    end = text.find(end_marker, start)
    if end < 0:
        raise RuntimeError(f"{label}: end marker not found")
    return text[:start] + new + text[end:]


def patch_file(path: Path, transform) -> None:
    original = path.read_text(encoding="utf-8")
    updated = transform(original)
    if updated == original:
        raise RuntimeError(f"{path}: transform produced no changes")
    path.write_text(updated, encoding="utf-8")
    print(f"patched {path}")


def patch_alt_application(text: str) -> str:
    text = replace_once(
        text,
        """    public var appExtensions: Set<ALTApplication> {\n        loadExtensions()\n    }\n""",
        """    public var appExtensions: Set<ALTApplication> {\n        loadExtensions()\n    }\n\n    /// Direct embedded companion applications, including WatchKit apps in Watch/*.app.\n    public var embeddedApplications: Set<ALTApplication> {\n        loadEmbeddedApplications()\n    }\n\n    /// Direct signable children. Descendants are exposed separately for callers that\n    /// need to provision the complete nested bundle graph.\n    public var signableChildren: Set<ALTApplication> {\n        appExtensions.union(embeddedApplications)\n    }\n\n    public var signableDescendants: Set<ALTApplication> {\n        var result = Set<ALTApplication>()\n        var stack = Array(signableChildren)\n        while let child = stack.popLast() {\n            if result.insert(child).inserted {\n                stack.append(contentsOf: child.signableChildren)\n            }\n        }\n        return result\n    }\n""",
        "ALTApplication public bundle graph",
    )
    text = replace_once(
        text,
        """            case 1: return .iPhone\n            case 2: return .iPad\n            case 3: return .appleTV\n            default: return .none\n""",
        """            case 1: return .iPhone\n            case 2: return .iPad\n            case 3: return .appleTV\n            case 4: return .appleWatch\n            default: return .none\n""",
        "ALTApplication UIDeviceFamily",
    )
    marker = """        return result\n    }\n}\n\n// MARK: Safe Index\n"""
    replacement = """        return result\n    }\n\n    func loadEmbeddedApplications() -> Set<ALTApplication> {\n        let watchURL = bundle.bundleURL.appendingPathComponent(\"Watch\", isDirectory: true)\n        guard FileManager.default.fileExists(atPath: watchURL.path) else {\n            return []\n        }\n\n        var result = Set<ALTApplication>()\n        let enumerator = FileManager.default.enumerator(\n            at: watchURL,\n            includingPropertiesForKeys: nil,\n            options: [.skipsSubdirectoryDescendants]\n        )\n\n        while let url = enumerator?.nextObject() as? URL {\n            guard url.pathExtension.lowercased() == \"app\" else { continue }\n            if let app = ALTApplication(fileURL: url) {\n                result.insert(app)\n            }\n        }\n        return result\n    }\n}\n\n// MARK: Safe Index\n"""
    return replace_once(text, marker, replacement, "ALTApplication Watch loader")


def patch_alt_device(text: str) -> str:
    text = replace_once(
        text,
        """    public static let appleTV = ALTDeviceType(rawValue: 1 << 3)\n\n    public static let none: ALTDeviceType = []\n    public static let all: ALTDeviceType = [.iPhone, .iPad, .appleTV]\n""",
        """    public static let appleTV = ALTDeviceType(rawValue: 1 << 3)\n    public static let appleWatch = ALTDeviceType(rawValue: 1 << 4)\n\n    public static let none: ALTDeviceType = []\n    public static let all: ALTDeviceType = [.iPhone, .iPad, .appleTV, .appleWatch]\n""",
        "ALTDeviceType Watch bit",
    )
    text = replace_once(
        text,
        """    if deviceType.contains(.appleTV) {\n        return \"tvOS\"\n    }\n\n    return nil\n""",
        """    if deviceType.contains(.appleTV) {\n        return \"tvOS\"\n    }\n\n    if deviceType.contains(.appleWatch) {\n        return \"watchOS\"\n    }\n\n    return nil\n""",
        "ALTDevice OS name",
    )
    text = replace_once(
        text,
        """        case \"iphone\": type = .iPhone\n        case \"ipad\":   type = .iPad\n        case \"tvOS\":   type = .appleTV\n        default:       type = .none\n""",
        """        case \"iphone\": type = .iPhone\n        case \"ipad\":   type = .iPad\n        case \"tvOS\":   type = .appleTV\n        case \"watch\", \"watchOS\", \"appleWatch\": type = .appleWatch\n        default:       type = .none\n""",
        "ALTDevice response parsing",
    )
    return text


def patch_alt_signer(text: str) -> str:
    old = """        try prepare(application)\n\n        for ext in application.appExtensions {\n            verboseLog(\"[AltSign] Found app extension: \\(ext.bundleIdentifier) at \\(ext.fileURL.path)\")\n            try prepare(ext)\n        }\n"""
    new = """        func prepareRecursively(_ app: ALTApplication) throws {\n            try prepare(app)\n            for child in app.signableChildren {\n                verboseLog(\"[AltSign] Found nested signable bundle: \\(child.bundleIdentifier) at \\(child.fileURL.path)\")\n                try prepareRecursively(child)\n            }\n        }\n\n        try prepareRecursively(application)\n"""
    return replace_once(text, old, new, "ALTSigner recursive preparation")


def patch_fetch_profiles(text: str) -> str:
    start_marker = '        self.debugLog("[FetchProvisioningProfiles] Preparing main provisioning profile'
    end_marker = "\n    \n    internal func fetchProvisioningProfile"
    new_execute_tail = '''        self.debugLog("[FetchProvisioningProfiles] Preparing main provisioning profile for \\(targetAppBundle.bundleIdentifier)...")\n        let profile = try await self.prepareProvisioningProfile(\n            for: targetAppBundle,\n            parentAppBundle: nil,\n            parentProfileBundleIdentifier: nil,\n            team: team,\n            session: session\n        )\n        self.debugLog("[FetchProvisioningProfiles] Main profile prepared successfully for \\(effectiveBundleId), expiration: \\(String(describing: profile.expirationDate))")\n\n        var profiles = [effectiveBundleId: profile]\n\n        if !self.context.useMainProfile {\n            let totalChildren = targetAppBundle.signableDescendants.count\n            if totalChildren > 0 {\n                self.setProgress(50)\n                self.debugLog("[FetchProvisioningProfiles] Preparing profiles for \\(totalChildren) nested signable bundles...")\n\n                var pending: [(application: ALTApplication, profile: ALTProvisioningProfile)] = [(targetAppBundle, profile)]\n                var completed = 0\n\n                while let parent = pending.popLast() {\n                    for child in parent.application.signableChildren {\n                        let childProfile = try await self.prepareProvisioningProfile(\n                            for: child,\n                            parentAppBundle: parent.application,\n                            parentProfileBundleIdentifier: parent.profile.bundleIdentifier,\n                            team: team,\n                            session: session\n                        )\n                        let logicalBundleID = child.bundleIdentifier.replacingOccurrences(\n                            of: targetAppBundle.bundleIdentifier,\n                            with: effectiveBundleId\n                        )\n                        profiles[logicalBundleID] = childProfile\n                        pending.append((child, childProfile))\n                        completed += 1\n                        let percent = 50 + Int64((Double(completed) / Double(max(totalChildren, 1))) * 50.0)\n                        self.setProgress(min(percent, 100))\n                        self.debugLog("[FetchProvisioningProfiles] Added nested profile: \\(logicalBundleID) -> \\(childProfile.bundleIdentifier)")\n                    }\n                }\n            } else {\n                self.setProgress(100)\n            }\n        } else {\n            self.setProgress(100)\n        }\n\n        self.debugLog("[FetchProvisioningProfiles] Total profiles prepared: \\(profiles.count) -> keys: \\(Array(profiles.keys))")\n        return profiles\n    }\n'''
    text = replace_between(text, start_marker, end_marker, new_execute_tail, "FetchProvisioningProfiles execute")

    old_sig = '''    private func prepareProvisioningProfile(for targetAppBundle: ALTApplication,\n                                    parentAppBundle: ALTApplication?,\n                                    team: ALTTeam,\n                                    session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {\n'''
    new_sig = '''    private func prepareProvisioningProfile(for targetAppBundle: ALTApplication,\n                                    parentAppBundle: ALTApplication?,\n                                    parentProfileBundleIdentifier: String? = nil,\n                                    team: ALTTeam,\n                                    session: ALTAppleAPISession) async throws -> ALTProvisioningProfile {\n'''
    text = replace_once(text, old_sig, new_sig, "prepareProvisioningProfile signature")

    old_logic = '''            let parentBundleID = parentAppBundle?.bundleIdentifier ?? targetAppBundle.bundleIdentifier\n            let effectiveParentBundleID = self.context.targetBundleIdentifier\n            let updatedParentBundleID = effectiveParentBundleID + "." + team.identifier\n\n            if parentAppBundle != nil,\n               targetAppBundle.bundleIdentifier.hasPrefix(parentBundleID + ".") {\n                let suffix = String(targetAppBundle.bundleIdentifier.dropFirst(parentBundleID.count))\n                bundleID = updatedParentBundleID + suffix\n            } else {\n                bundleID = updatedParentBundleID\n            }\n'''
    new_logic = '''            if let parentAppBundle {\n                let effectiveParentBundleID = parentProfileBundleIdentifier\n                    ?? (self.context.targetBundleIdentifier + "." + team.identifier)\n\n                if targetAppBundle.bundleIdentifier.hasPrefix(parentAppBundle.bundleIdentifier + ".") {\n                    let suffix = String(targetAppBundle.bundleIdentifier.dropFirst(parentAppBundle.bundleIdentifier.count))\n                    bundleID = effectiveParentBundleID + suffix\n                } else {\n                    bundleID = effectiveParentBundleID + "." + targetAppBundle.bundleIdentifier\n                }\n            } else {\n                bundleID = self.context.targetBundleIdentifier + "." + team.identifier\n            }\n'''
    text = replace_once(text, old_logic, new_logic, "recursive bundle ID construction")

    text = replace_once(
        text,
        "let requiredAppIDs = 1 + targetAppBundle.appExtensions.count",
        "let requiredAppIDs = 1 + targetAppBundle.signableDescendants.count",
        "recursive App ID count",
    )
    return text


def patch_prepare_ids(text: str) -> str:
    return replace_once(
        text,
        """                for appex in appBundle.appExtensions {\n                    appexBundleIds[appex.bundleIdentifier] = appex.bundleIdentifier\n                        .replacingOccurrences(of: appBundle.bundleIdentifier, with: profile.bundleIdentifier)\n                }\n""",
        """                for child in appBundle.signableDescendants {\n                    appexBundleIds[child.bundleIdentifier] = child.bundleIdentifier\n                        .replacingOccurrences(of: appBundle.bundleIdentifier, with: profile.bundleIdentifier)\n                }\n""",
        "PrepareAppExtensionBundleIDs recursive graph",
    )


def patch_resign(text: str) -> str:
    text = replace_once(
        text,
        """        guard let appBundle = Bundle(url: appBundleURL) else { throw ALTError(.missingAppBundle) }\n        guard let infoDictionary = appBundle.completeInfoDictionary else { throw ALTError(.missingInfoPlist) }\n""",
        """        guard let appBundle = Bundle(url: appBundleURL) else { throw ALTError(.missingAppBundle) }\n        guard let stagedApplication = ALTApplication(fileURL: appBundleURL) else { throw ALTError(.missingAppBundle) }\n        guard let infoDictionary = appBundle.completeInfoDictionary else { throw ALTError(.missingInfoPlist) }\n""",
        "ResignApp staged ALTApplication",
    )

    start_marker = """        if let directory = appBundle.builtInPlugInsURL,\n"""
    end_marker = """        return appBundleURL\n"""
    replacement = '''        // Prepare every nested code-signing bundle, not only PlugIns/*.appex.\n        // A companion Watch app lives under Watch/*.app and contains its own PlugIns/*.appex.\n        var pending: [(application: ALTApplication, finalBundleIdentifier: String)] = [\n            (stagedApplication, finalBundleIdentifier)\n        ]\n\n        while let parent = pending.popLast() {\n            for child in parent.application.signableChildren {\n                let logicalBundleID = child.bundleIdentifier.replacingOccurrences(\n                    of: targetAppBundle.bundleIdentifier,\n                    with: bundleIdentifier\n                )\n                guard let childProfile = context.useMainProfile ? profiles.values.first : profiles[logicalBundleID] else {\n                    throw ALTError(.missingProvisioningProfile)\n                }\n\n                var childInfoValues: [String: Any] = [:]\n                if let childInfo = child.bundle.completeInfoDictionary {\n                    if childInfo["WKApplication"] as? Bool == true {\n                        childInfoValues["WKCompanionAppBundleIdentifier"] = finalBundleIdentifier\n                    }\n                    if let extensionInfo = childInfo["NSExtension"] as? [String: Any],\n                       extensionInfo["NSExtensionPointIdentifier"] as? String == "com.apple.watchkit" {\n                        childInfoValues["WKAppBundleIdentifier"] = parent.finalBundleIdentifier\n                    }\n                }\n\n                try self.prepare(\n                    child.bundle,\n                    bundleID: logicalBundleID,\n                    additionalInfoDictionaryValues: childInfoValues,\n                    profiles: profiles,\n                    appexBundleIds: appexBundleIds\n                )\n                pending.append((child, childProfile.bundleIdentifier))\n            }\n        }\n\n'''
    return replace_between(text, start_marker, end_marker, replacement, "ResignApp recursive preparation")


def apply(root: Path) -> None:
    alt = root / "Dependencies" / "AltSign"
    patch_file(alt / "Sources/Model/ALTApplication.swift", patch_alt_application)
    patch_file(alt / "Sources/Model/ALTDevice.swift", patch_alt_device)
    patch_file(alt / "Sources/ALTSigner.swift", patch_alt_signer)

    pipeline = root / "SideStore/Core/Operations/PipelineOperations"
    patch_file(pipeline / "FetchProvisioningProfilesOperation.swift", patch_fetch_profiles)
    patch_file(pipeline / "PrepareAppExtensionBundleIDsOperation.swift", patch_prepare_ids)
    patch_file(pipeline / "ResignAppOperation.swift", patch_resign)


def validate(root: Path) -> None:
    checks = {
        root / "Dependencies/AltSign/Sources/Model/ALTApplication.swift": ["embeddedApplications", "signableDescendants", "case 4: return .appleWatch"],
        root / "Dependencies/AltSign/Sources/ALTSigner.swift": ["prepareRecursively", "app.signableChildren"],
        root / "SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift": ["parentProfileBundleIdentifier", "targetAppBundle.signableDescendants"],
        root / "SideStore/Core/Operations/PipelineOperations/ResignAppOperation.swift": ["WKCompanionAppBundleIdentifier", "WKAppBundleIdentifier", "stagedApplication"],
    }
    for path, needles in checks.items():
        text = path.read_text(encoding="utf-8")
        for needle in needles:
            if needle not in text:
                raise RuntimeError(f"validation failed: {needle!r} missing from {path}")
    print("watch-support structural validation passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("sidestore_root", type=Path)
    args = parser.parse_args()
    root = args.sidestore_root.resolve()
    apply(root)
    validate(root)


if __name__ == "__main__":
    main()
