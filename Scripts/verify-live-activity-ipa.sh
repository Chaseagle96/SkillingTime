#!/bin/bash
set -euo pipefail
IPA="${1:-SkillingTime-v0.3.1-LiveActivity.ipa}"
if [[ ! -f "$IPA" ]]; then
  echo "IPA not found: $IPA" >&2
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
