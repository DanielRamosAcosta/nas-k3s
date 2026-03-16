#!/bin/bash
set -euo pipefail

GOLDEN_DIR="$(git rev-parse --show-toplevel)/.golden"
CURRENT_DIR="$(mktemp -d)"

if [ ! -d "$GOLDEN_DIR" ]; then
  echo "ERROR: No golden master found. Run scripts/golden-export.sh first."
  exit 1
fi

echo "Exporting current manifests to $CURRENT_DIR..."
tk export "$CURRENT_DIR" environments/ \
  --recursive \
  --format '{{.apiVersion}}/{{.kind}}-{{.metadata.name}}'

echo "Comparing..."

# Remove non-deterministic files before comparing
# kubernetes-dashboard Helm chart generates random CSRF secrets on each export
find "$GOLDEN_DIR" "$CURRENT_DIR" -name '*kubernetes-dashboard*' -delete 2>/dev/null || true

DIFF_OUTPUT=$(diff -r "$GOLDEN_DIR" "$CURRENT_DIR" 2>&1 || true)

rm -rf "$CURRENT_DIR"

if [ -z "$DIFF_OUTPUT" ]; then
  echo "OK: No differences found. Refactor is safe."
  exit 0
else
  echo "FAIL: Differences detected:"
  echo ""
  echo "$DIFF_OUTPUT"
  exit 1
fi
