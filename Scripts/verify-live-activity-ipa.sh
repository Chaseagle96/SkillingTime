#!/bin/bash
set -euo pipefail
# Pass the IPA path, or run from a folder containing SkillingTime-*.ipa to use
# the newest one.
IPA="${1:-}"
if [[ -z "$IPA" ]]; then
  IPA=$(ls -t SkillingTime-*.ipa 2>/dev/null | head -n 1 || true)
fi
if [[ -z "$IPA" || ! -f "$IPA" ]]; then
  echo "IPA not found: ${IPA:-<none>}. Pass the IPA path as the first argument." >&2
  exit 1
fi
unzip -t "$IPA" >/dev/null
CONTENTS=$(mktemp)
trap 'rm -f "$CONTENTS"' EXIT
unzip -l "$IPA" > "$CONTENTS"
grep -Fq 'Payload/SkillingTime.app/' "$CONTENTS"
grep -Fq 'Payload/SkillingTime.app/PlugIns/SkillingTimeWidgets.appex/' "$CONTENTS"
grep -Fq 'Payload/SkillingTime.app/PlugIns/SkillingTimeWidgets.appex/SkillingTimeWidgets' "$CONTENTS"
echo "Verified archive structure: $IPA contains SkillingTime.app and SkillingTimeWidgets.appex."
