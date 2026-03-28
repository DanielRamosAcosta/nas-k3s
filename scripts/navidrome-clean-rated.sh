#!/usr/bin/env bash
# Removes rated songs from the "Sin evaluar" playlist in Navidrome.
# Usage: ./scripts/navidrome-clean-rated.sh [--dry-run]
set -euo pipefail

NAMESPACE="media"
POD="navidrome-0"
DB="/data/navidrome.db"
PLAYLIST_ID="QVqmtVlZbnWtOhzKAYe2p6"
USER_NAME="dani"
DRY_RUN=false

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

query() {
  kubectl exec -n "$NAMESPACE" "$POD" -- sqlite3 "$DB" "$1"
}

# Count rated songs still in the playlist
COUNT=$(query "
  SELECT COUNT(*) FROM playlist_tracks pt
  JOIN annotation a ON a.item_id = pt.media_file_id
  JOIN user u ON a.user_id = u.id
  WHERE pt.playlist_id = '$PLAYLIST_ID'
    AND u.user_name = '$USER_NAME'
    AND a.item_type = 'media_file'
    AND a.rating > 0;
")

if [[ "$COUNT" -eq 0 ]]; then
  echo "No hay canciones evaluadas en la playlist. Nada que limpiar."
  exit 0
fi

echo "Canciones evaluadas a eliminar: $COUNT"

if $DRY_RUN; then
  echo "(dry-run) Se eliminarían estas canciones:"
  query "
    SELECT mf.artist || ' - ' || mf.title || ' (' || a.rating || '★)'
    FROM playlist_tracks pt
    JOIN media_file mf ON pt.media_file_id = mf.id
    JOIN annotation a ON a.item_id = pt.media_file_id
    JOIN user u ON a.user_id = u.id
    WHERE pt.playlist_id = '$PLAYLIST_ID'
      AND u.user_name = '$USER_NAME'
      AND a.item_type = 'media_file'
      AND a.rating > 0
    ORDER BY mf.artist, mf.title;
  "
  exit 0
fi

query "
BEGIN TRANSACTION;

-- Delete rated tracks from playlist
DELETE FROM playlist_tracks
WHERE playlist_id = '$PLAYLIST_ID'
AND media_file_id IN (
  SELECT a.item_id FROM annotation a
  JOIN user u ON a.user_id = u.id
  WHERE u.user_name = '$USER_NAME'
    AND a.item_type = 'media_file'
    AND a.rating > 0
);

-- Reindex positions
UPDATE playlist_tracks
SET id = (
  SELECT COUNT(*) FROM playlist_tracks pt2
  WHERE pt2.playlist_id = '$PLAYLIST_ID'
    AND pt2.rowid <= playlist_tracks.rowid
)
WHERE playlist_id = '$PLAYLIST_ID';

-- Update playlist metadata
UPDATE playlist SET
  song_count = (SELECT COUNT(*) FROM playlist_tracks WHERE playlist_id = '$PLAYLIST_ID'),
  duration = (SELECT COALESCE(SUM(mf.duration), 0) FROM playlist_tracks pt JOIN media_file mf ON pt.media_file_id = mf.id WHERE pt.playlist_id = '$PLAYLIST_ID'),
  size = (SELECT COALESCE(SUM(mf.size), 0) FROM playlist_tracks pt JOIN media_file mf ON pt.media_file_id = mf.id WHERE pt.playlist_id = '$PLAYLIST_ID'),
  updated_at = datetime('now')
WHERE id = '$PLAYLIST_ID';

COMMIT;
"

REMAINING=$(query "SELECT song_count FROM playlist WHERE id = '$PLAYLIST_ID';")
echo "Eliminadas $COUNT canciones. Quedan $REMAINING en la playlist."
