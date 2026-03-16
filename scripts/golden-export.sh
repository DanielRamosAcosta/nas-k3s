#!/bin/bash
set -euo pipefail

GOLDEN_DIR="$(git rev-parse --show-toplevel)/.golden"

rm -rf "$GOLDEN_DIR"
mkdir -p "$GOLDEN_DIR"

echo "Exporting golden master to $GOLDEN_DIR..."
tk export "$GOLDEN_DIR" environments/ \
  --recursive \
  --format '{{.apiVersion}}/{{.kind}}-{{.metadata.name}}'

echo "Golden master exported ($(find "$GOLDEN_DIR" -type f | wc -l | tr -d ' ') files)"
