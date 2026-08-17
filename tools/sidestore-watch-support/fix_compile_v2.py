#!/usr/bin/env python3
"""Compiler-fix pass for the experimental SideStore Watch patch."""
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
path = root / "SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift"
text = path.read_text(encoding="utf-8")
old = '            self.debugLog("[FetchProvisioningProfiles] Constructed mangled bundleID: \\(bundleID) (effectiveParent: \\(effectiveParentBundleID), team: \\(team.identifier))")\n'
new = '            self.debugLog("[FetchProvisioningProfiles] Constructed mangled bundleID: \\(bundleID) (parentProfile: \\(parentProfileBundleIdentifier ?? \"main\"), team: \\(team.identifier))")\n'
count = text.count(old)
if count != 1:
    raise RuntimeError(f"expected one stale effectiveParentBundleID log line, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print(f"patched compiler regression in {path}")
