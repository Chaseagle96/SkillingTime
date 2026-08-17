# Experimental SideStore Apple Watch companion support

This directory contains a reproducible patch harness for the exact SideStore revision used during the Skilling Time investigation.

Pinned upstream revisions:

- SideStore: `e3f3a5b941ce657723a4939c89f2eea63bcfe263`
- AltSign: `c0031f042a388a3a2f16549f14c04417a2976765`

## What the patch changes

The stock signing path discovers only direct `PlugIns/*.appex` bundles. A companion watchOS application is instead embedded at `Watch/*.app`, with its Watch extension nested inside that app. The patch makes AltSign model that nested bundle graph, makes SideStore provision every signable descendant, prepares every nested bundle before signing, and rewrites the WatchKit relationship keys to the newly provisioned bundle identifiers.

The patch also adds an Apple Watch device type to AltSign's model. It deliberately does **not** guess an undocumented Apple Developer Portal request parameter for watchOS. SideStore continues using its existing iOS App Development provisioning-profile request path while the paired-Watch registration path is implemented separately.

## CI

`.github/workflows/build-patched-sidestore.yml` checks out the pinned public SideStore source and recursive submodules, verifies the pinned AltSign SHA, applies `apply_watch_support.py`, validates the diff, then builds SideStore using the same `scripts/ci/workflow.py build` entry point as SideStore's upstream pull-request workflow on Xcode 26.2.

A successful workflow artifact proves the patched signer compiles and packages. It does not by itself prove that a physical Apple Watch can install the companion app. Physical-device validation additionally requires the Watch UDID to be registered in the selected Apple development team and included in the applicable development provisioning profile.
