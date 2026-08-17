#!/usr/bin/env python3
"""Extend the experimental Watch patch into SideStore's Apple portal path.

The legacy Developer Portal endpoints used by AltSign classify iPhone/iPad
provisioning under DTDK_Platform=ios. Apple development profiles support
watchOS companions alongside the iOS app, so Watch device/profile requests
must follow that existing iOS path instead of being emitted with no platform.

This pass also keeps already-registered Watch devices visible during SideStore
authentication. It does not fabricate a paired-Watch UDID; registration of a
missing Watch still requires an actual identifier from the device.
"""
from pathlib import Path
import sys


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


root = Path(sys.argv[1]).resolve()

api_path = root / "Dependencies/AltSign/Sources/ALTAppleAPI+Operations.swift"
api = api_path.read_text(encoding="utf-8")
api = replace_once(
    api,
    "if type.contains(.iphone) || type.contains(.ipad) {\n            parameters[\"DTDK_Platform\"] = \"ios\"",
    "if type.contains(.iphone) || type.contains(.ipad) || type.contains(.appleWatch) {\n            parameters[\"DTDK_Platform\"] = \"ios\"",
    "Watch device registration platform",
)
api = replace_once(
    api,
    "if deviceType.contains(.iphone) || deviceType.contains(.ipad) {\n            parameters[\"DTDK_Platform\"] = \"ios\"",
    "if deviceType.contains(.iphone) || deviceType.contains(.ipad) || deviceType.contains(.appleWatch) {\n            parameters[\"DTDK_Platform\"] = \"ios\"",
    "Watch provisioning profile platform",
)
api_path.write_text(api, encoding="utf-8")
print(f"patched {api_path}")

auth_path = root / "SideStore/Core/Operations/StandaloneOperations/AuthenticationOperation.swift"
auth = auth_path.read_text(encoding="utf-8")
auth = replace_once(
    auth,
    """        let devices = try await DeveloperPortalService.shared.fetchDevices(for: team, types: [.iphone, .ipad], session: session)\n        if let device = devices.first(where: { $0.identifier == udid }) {\n""",
    """        let devices = try await DeveloperPortalService.shared.fetchDevices(for: team, types: [.iphone, .ipad, .appleWatch], session: session)\n        let registeredWatches = devices.filter { $0.type.contains(.appleWatch) }\n        if !registeredWatches.isEmpty {\n            self.debugLog(\"[Authentication] Found \\(registeredWatches.count) registered Apple Watch device(s) on team: \\(registeredWatches.map { $0.name })\")\n        }\n        if let device = devices.first(where: { $0.identifier == udid }) {\n""",
    "Authentication registered Watch visibility",
)
auth_path.write_text(auth, encoding="utf-8")
print(f"patched {auth_path}")

# Structural assertions guard against silently producing a non-Watch build.
api_check = api_path.read_text(encoding="utf-8")
auth_check = auth_path.read_text(encoding="utf-8")
assert "type.contains(.appleWatch)" in api_check
assert "deviceType.contains(.appleWatch)" in api_check
assert "types: [.iphone, .ipad, .appleWatch]" in auth_check
assert "registeredWatches" in auth_check
print("Watch Developer Portal structural validation passed")
