#!/usr/bin/env python3
"""Add crash-resistant, user-retrievable tracing to the experimental Watch build.

SideStore can disappear during a Watch-enabled install without producing an iOS
crash report.  This pass writes checkpoints synchronously to
Documents/SideStoreWatchTrace.log so the last completed stage survives a hard
termination. SideStore's upstream Info.plist already enables Files document
sharing and opening documents in place.
"""
from pathlib import Path
import sys


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


root = Path(sys.argv[1]).resolve()

fetch_path = root / "SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift"
fetch = fetch_path.read_text(encoding="utf-8")

trace_helper = r'''import CoreData

// Persistent diagnostic trace for the experimental Apple Watch signing path.
// FileHandle.synchronizeFile() is intentional: if iOS kills SideStore without a
// normal crash, the latest checkpoint should already be on disk.
let watchInstallTraceLock = NSLock()

func appendWatchInstallTrace(_ message: String) {
    watchInstallTraceLock.lock()
    defer { watchInstallTraceLock.unlock() }

    let fileManager = FileManager.default
    guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let traceURL = documentsURL.appendingPathComponent("SideStoreWatchTrace.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    guard let data = "\(timestamp) \(message)\n".data(using: .utf8) else { return }

    if !fileManager.fileExists(atPath: traceURL.path) {
        fileManager.createFile(atPath: traceURL.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: traceURL) else { return }
    handle.seekToEndOfFile()
    handle.write(data)
    handle.synchronizeFile()
    handle.closeFile()
}

func resetWatchInstallTrace(_ message: String) {
    let fileManager = FileManager.default
    if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
        try? fileManager.removeItem(at: documentsURL.appendingPathComponent("SideStoreWatchTrace.log"))
    }
    appendWatchInstallTrace(message)
}

'''
fetch = replace_once(fetch, "import CoreData\n\n", trace_helper, "persistent trace helper")
fetch = replace_once(
    fetch,
    '        debugLog("[FetchProvisioningProfilesOperation] execute() started")\n',
    '        resetWatchInstallTrace("FETCH_PROFILES_EXECUTE_BEGIN")\n        debugLog("[FetchProvisioningProfilesOperation] execute() started")\n',
    "fetch execute begin trace",
)
fetch = replace_once(
    fetch,
    '        self.debugLog("[FetchProvisioningProfiles] Preparing main provisioning profile for \\(targetAppBundle.bundleIdentifier)...")\n',
    '        appendWatchInstallTrace("MAIN_PROFILE_BEGIN source=\\(targetAppBundle.bundleIdentifier) target=\\(effectiveBundleId)")\n        self.debugLog("[FetchProvisioningProfiles] Preparing main provisioning profile for \\(targetAppBundle.bundleIdentifier)...")\n',
    "main profile begin trace",
)
fetch = replace_once(
    fetch,
    '        self.debugLog("[FetchProvisioningProfiles] Main profile prepared successfully for \\(effectiveBundleId), expiration: \\(String(describing: profile.expirationDate))")\n',
    '        self.debugLog("[FetchProvisioningProfiles] Main profile prepared successfully for \\(effectiveBundleId), expiration: \\(String(describing: profile.expirationDate))")\n        appendWatchInstallTrace("MAIN_PROFILE_END profile=\\(profile.bundleIdentifier)")\n',
    "main profile end trace",
)
fetch = replace_once(
    fetch,
    '                    for child in parent.application.signableChildren {\n                        let childProfile = try await self.prepareProvisioningProfile(\n',
    '                    for child in parent.application.signableChildren {\n                        appendWatchInstallTrace("CHILD_PROFILE_BEGIN source=\\(child.bundleIdentifier) parent=\\(parent.application.bundleIdentifier) deviceType=\\(child.deviceType.rawValue)")\n                        let childProfile = try await self.prepareProvisioningProfile(\n',
    "child profile begin trace",
)
fetch = replace_once(
    fetch,
    '                        self.debugLog("[FetchProvisioningProfiles] Added nested profile: \\(logicalBundleID) -> \\(childProfile.bundleIdentifier)")\n',
    '                        self.debugLog("[FetchProvisioningProfiles] Added nested profile: \\(logicalBundleID) -> \\(childProfile.bundleIdentifier)")\n                        appendWatchInstallTrace("CHILD_PROFILE_END logical=\\(logicalBundleID) profile=\\(childProfile.bundleIdentifier)")\n',
    "child profile end trace",
)
fetch = replace_once(
    fetch,
    '        self.debugLog("[FetchProvisioningProfiles] Total profiles prepared: \\(profiles.count) -> keys: \\(Array(profiles.keys))")\n        return profiles\n',
    '        self.debugLog("[FetchProvisioningProfiles] Total profiles prepared: \\(profiles.count) -> keys: \\(Array(profiles.keys))")\n        appendWatchInstallTrace("FETCH_PROFILES_SUCCESS count=\\(profiles.count)")\n        return profiles\n',
    "profile success trace",
)
fetch = replace_once(
    fetch,
    '        self.debugLog("[FetchProvisioningProfiles] Registering App ID with name \'\\(preferredName)\' and bundleID \'\\(bundleID)\'...")\n',
    '        appendWatchInstallTrace("APP_ID_REGISTER_BEGIN bundle=\\(bundleID) source=\\(targetAppBundle.bundleIdentifier) deviceType=\\(targetAppBundle.deviceType.rawValue)")\n        self.debugLog("[FetchProvisioningProfiles] Registering App ID with name \'\\(preferredName)\' and bundleID \'\\(bundleID)\'...")\n',
    "App ID register begin trace",
)
fetch = replace_once(
    fetch,
    '        self.debugLog("[FetchProvisioningProfiles] App ID registered successfully: \\(appID.bundleIdentifier) (\\(appID.identifier))")\n',
    '        self.debugLog("[FetchProvisioningProfiles] App ID registered successfully: \\(appID.bundleIdentifier) (\\(appID.identifier))")\n        appendWatchInstallTrace("APP_ID_REGISTER_END bundle=\\(appID.bundleIdentifier)")\n',
    "App ID register end trace",
)
fetch = replace_once(
    fetch,
    '        self.debugLog("[FetchProvisioningProfiles] Fetching provisioning profile for App ID \\(appID.bundleIdentifier)...")\n',
    '        appendWatchInstallTrace("PROFILE_REQUEST_BEGIN appID=\\(appID.bundleIdentifier) deviceType=\\(targetAppBundle.deviceType.rawValue)")\n        self.debugLog("[FetchProvisioningProfiles] Fetching provisioning profile for App ID \\(appID.bundleIdentifier)...")\n',
    "profile request begin trace",
)
fetch = replace_once(
    fetch,
    '        self.debugLog("[FetchProvisioningProfiles] Provisioning profile fetched for \\(appID.bundleIdentifier) (Name: \\(profile.name), Expiration: \\(String(describing: profile.expirationDate)))")\n',
    '        self.debugLog("[FetchProvisioningProfiles] Provisioning profile fetched for \\(appID.bundleIdentifier) (Name: \\(profile.name), Expiration: \\(String(describing: profile.expirationDate)))")\n        appendWatchInstallTrace("PROFILE_REQUEST_END appID=\\(appID.bundleIdentifier) profile=\\(profile.bundleIdentifier)")\n',
    "profile request end trace",
)
fetch_path.write_text(fetch, encoding="utf-8")
print(f"patched {fetch_path}")

resign_path = root / "SideStore/Core/Operations/PipelineOperations/ResignAppOperation.swift"
resign = resign_path.read_text(encoding="utf-8")
resign = replace_once(
    resign,
    '        debugLog("[ResignAppOperation] execute() started")\n',
    '        appendWatchInstallTrace("RESIGN_EXECUTE_BEGIN")\n        debugLog("[ResignAppOperation] execute() started")\n',
    "resign execute begin trace",
)
resign = replace_once(
    resign,
    '        let appBundleURL = try await self.prepareAppBundle(for: appBundle, profiles: profiles, appexBundleIds: context.appexBundleIds ?? [:])\n',
    '        appendWatchInstallTrace("PREPARE_APP_BEGIN profiles=\\(profiles.count) descendants=\\(appBundle.signableDescendants.count)")\n        let appBundleURL = try await self.prepareAppBundle(for: appBundle, profiles: profiles, appexBundleIds: context.appexBundleIds ?? [:])\n        appendWatchInstallTrace("PREPARE_APP_END path=\\(appBundleURL.lastPathComponent)")\n',
    "prepare app trace",
)
resign = replace_once(
    resign,
    '        let resignedURL = try await self.resignAppBundle(at: appBundleURL, team: team, certificate: certificate, profiles: Array(profiles.values))\n',
    '        appendWatchInstallTrace("SIGN_BEGIN profiles=\\(profiles.count)")\n        let resignedURL = try await self.resignAppBundle(at: appBundleURL, team: team, certificate: certificate, profiles: Array(profiles.values))\n        appendWatchInstallTrace("SIGN_END ipa=\\(resignedURL.lastPathComponent)")\n',
    "sign trace",
)
resign = replace_once(
    resign,
    '        guard let profile = context.useMainProfile ? profiles.values.first : profiles[identifier] else {\n            throw ALTError(.missingProvisioningProfile)\n        }\n',
    '        guard let profile = context.useMainProfile ? profiles.values.first : profiles[identifier] else {\n            appendWatchInstallTrace("PREPARE_BUNDLE_MISSING_PROFILE logical=\\(identifier) path=\\(bundle.bundleURL.lastPathComponent)")\n            throw ALTError(.missingProvisioningProfile)\n        }\n        appendWatchInstallTrace("PREPARE_BUNDLE logical=\\(identifier) profile=\\(profile.bundleIdentifier) path=\\(bundle.bundleURL.path)")\n',
    "bundle preparation trace",
)
resign = replace_once(
    resign,
    '        self.debugLog("[ResignAppOperation] Resigned app \\(self.context.bundleIdentifier) to \\(resignedAppBundle.bundleIdentifier).")\n',
    '        self.debugLog("[ResignAppOperation] Resigned app \\(self.context.bundleIdentifier) to \\(resignedAppBundle.bundleIdentifier).")\n        appendWatchInstallTrace("RESIGN_SUCCESS final=\\(resignedAppBundle.bundleIdentifier)")\n',
    "resign success trace",
)
resign_path.write_text(resign, encoding="utf-8")
print(f"patched {resign_path}")

auth_path = root / "SideStore/Core/Operations/StandaloneOperations/AuthenticationOperation.swift"
auth = auth_path.read_text(encoding="utf-8")
auth = replace_once(
    auth,
    '        let registeredWatches = devices.filter { $0.type.contains(.appleWatch) }\n',
    '        let registeredWatches = devices.filter { $0.type.contains(.appleWatch) }\n        appendWatchInstallTrace("AUTH_REGISTERED_WATCHES count=\\(registeredWatches.count) names=\\(registeredWatches.map { $0.name }.joined(separator: ","))")\n',
    "registered Watch authentication trace",
)
auth_path.write_text(auth, encoding="utf-8")
print(f"patched {auth_path}")

# Structural assertions make CI fail instead of silently shipping an untraced build.
for path, needles in {
    fetch_path: ["SideStoreWatchTrace.log", "MAIN_PROFILE_BEGIN", "CHILD_PROFILE_BEGIN", "PROFILE_REQUEST_BEGIN", "FETCH_PROFILES_SUCCESS"],
    resign_path: ["PREPARE_APP_BEGIN", "PREPARE_BUNDLE", "SIGN_BEGIN", "SIGN_END", "RESIGN_SUCCESS"],
    auth_path: ["AUTH_REGISTERED_WATCHES"],
}.items():
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            raise RuntimeError(f"persistent trace validation failed: {needle!r} missing from {path}")

info = (root / "AltStore/Info.plist").read_text(encoding="utf-8")
assert "<key>UIFileSharingEnabled</key>" in info and "<true/>" in info
assert "<key>LSSupportsOpeningDocumentsInPlace</key>" in info
print("persistent Watch trace validation passed")
