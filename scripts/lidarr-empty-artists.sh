#!/usr/bin/env bash
set -euo pipefail

LIDARR_API="http://localhost:8686/api/v1"
LIDARR_KEY=$(kubectl exec -n arr lidarr-0 -- cat /config/config.xml | sed -n 's/.*<ApiKey>\([^<]*\)<.*/\1/p')

echo "Fetching artists with 0 tracks on disk..."
command curl -s "$LIDARR_API/artist?apikey=$LIDARR_KEY" \
  | jq -r '.[] | select(.statistics.trackFileCount == 0 or .statistics.trackFileCount == null) | "\(.artistName)\t\(.statistics.totalTrackCount // 0) monitored"' \
  | sort -f \
  | column -t -s $'\t'

echo ""
command curl -s "$LIDARR_API/artist?apikey=$LIDARR_KEY" \
  | jq '[.[] | select(.statistics.trackFileCount == 0 or .statistics.trackFileCount == null)] | length' \
  | xargs -I{} echo "Total: {} artists with 0 tracks on disk"
