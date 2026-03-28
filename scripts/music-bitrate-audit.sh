#!/bin/bash
# music-bitrate-audit.sh - Detect and fix fake high-bitrate MP3s
#
# Method: measures energy drop between a reference band (4-6kHz) and high-frequency
# test bands. A genuine high-bitrate file has gradual rolloff. A re-encoded file
# has a steep cliff where the original encoding cut off frequencies.
#
# We look at the slope of energy drop between consecutive bands.
# A sudden jump in drop rate indicates the original cutoff frequency.

set -euo pipefail

MUSIC_DIR="/cold-data/media/music/library/all"
DRY_RUN=true
LIMIT=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --limit)    LIMIT="$2"; shift 2 ;;
    --dry-run)  DRY_RUN="$2"; shift 2 ;;
    --dir)      MUSIC_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--limit N] [--dry-run true|false] [--dir PATH]"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Test frequencies (Hz)
TEST_FREQS=(14000 15000 16000 17000 18000 19000 20000)

# Steep slope threshold (dB drop per 1kHz band).
# Normal rolloff: ~2-4 dB/kHz. Encoding cutoff: >6 dB/kHz.
SLOPE_THRESHOLD=6

get_mean_volume() {
  local file="$1"
  local freq="$2"
  ffmpeg -v info -nostats -i "$file" -t 20 \
    -af "highpass=f=${freq}:poles=2,highpass=f=${freq}:poles=2,highpass=f=${freq}:poles=2,volumedetect" \
    -f null - 2>&1 | grep -oP 'mean_volume: \K[-0-9.]+' || echo ""
}

estimate_bitrate_from_cutoff() {
  local cutoff=$1
  if   (( cutoff >= 20000 )); then echo 320
  elif (( cutoff >= 19000 )); then echo 256
  elif (( cutoff >= 18000 )); then echo 192
  elif (( cutoff >= 16000 )); then echo 128
  else echo 96
  fi
}

get_declared_bitrate() {
  local file="$1"
  local br
  br=$(ffprobe -v quiet -select_streams a:0 \
    -show_entries stream=bit_rate -of csv=p=0 "$file" 2>/dev/null | head -1 | tr -d '[:space:]')
  if [[ -z "$br" || "$br" == "N/A" ]]; then
    br=$(ffprobe -v quiet -show_entries format=bit_rate -of csv=p=0 "$file" 2>/dev/null | head -1 | tr -d '[:space:]')
  fi
  br="${br:-0}"
  if ! [[ "$br" =~ ^[0-9]+$ ]]; then
    echo 0
    return
  fi
  echo $(( br / 1000 ))
}

detect_cutoff() {
  local file="$1"

  # Collect energy at each test frequency
  local volumes=()
  for freq in "${TEST_FREQS[@]}"; do
    local vol
    vol=$(get_mean_volume "$file" "$freq")
    if [[ -z "$vol" ]]; then
      echo "ERROR"
      return
    fi
    volumes+=("$vol")
  done

  # Strategy: find the lowest frequency where energy drops to silence (-85dB)
  # or where there's a steep slope (>SLOPE_THRESHOLD dB/kHz)
  local cutoff_freq=20000
  local SILENCE=-85

  # First check: find where signal hits silence floor
  for (( i=0; i<${#volumes[@]}; i++ )); do
    local vol_int
    vol_int=$(awk "BEGIN {printf \"%.0f\", ${volumes[$i]}}")
    if (( vol_int <= SILENCE )); then
      cutoff_freq=${TEST_FREQS[$i]}
      break
    fi
  done

  # Second check: steep slope detection (catches cases above silence floor)
  for (( i=0; i<${#volumes[@]}-1; i++ )); do
    local curr="${volumes[$i]}"
    local next="${volumes[$((i+1))]}"
    local freq_curr="${TEST_FREQS[$i]}"
    local freq_next="${TEST_FREQS[$((i+1))]}"

    local slope
    slope=$(awk "BEGIN {printf \"%.1f\", ($curr - ($next)) / (($freq_next - $freq_curr) / 1000)}")
    local slope_int=${slope%%.*}

    if (( slope_int >= SLOPE_THRESHOLD )); then
      local slope_cutoff=${TEST_FREQS[$((i+1))]}
      # Take the lower (more conservative) cutoff
      if (( slope_cutoff < cutoff_freq )); then
        cutoff_freq=$slope_cutoff
      fi
      break
    fi
  done

  echo "$cutoff_freq"
}

reencode_file() {
  local file="$1"
  local target_br="$2"
  local tmp="${file%.mp3}.tmp.mp3"

  ffmpeg -v quiet -y -i "$file" -c:a libmp3lame -b:a "${target_br}k" -map_metadata 0 "$tmp" && \
    mv "$tmp" "$file"
}

# --- Main ---

echo "=== Music Bitrate Audit ==="
echo "Directory: $MUSIC_DIR"
echo "Dry run:   $DRY_RUN"
echo "Limit:     $( (( LIMIT > 0 )) && echo "$LIMIT" || echo "none" )"
echo "Slope threshold: ${SLOPE_THRESHOLD} dB/kHz"
echo ""
printf "%-6s %-6s %-8s %-6s %-10s %s\n" "NUM" "STATUS" "DECLARED" "REAL" "CUTOFF" "FILE"
printf "%s\n" "------------------------------------------------------------------------------------"

count=0
fakes=0
errors=0

while IFS= read -r -d '' file; do
  (( LIMIT > 0 && count >= LIMIT )) && break
  count=$((count + 1))

  rel_path="${file#"$MUSIC_DIR"/}"
  declared=$(get_declared_bitrate "$file")

  # Skip files already at low bitrate (nothing to detect)
  if (( declared > 0 && declared <= 128 )); then
    printf "%-6s %-6s %-8s %-6s %-10s %s\n" "[$count]" "SKIP" "${declared}k" "-" "-" "$rel_path"
    continue
  fi

  cutoff=$(detect_cutoff "$file" 2>/dev/null) || cutoff="ERROR"

  if [[ "$cutoff" == "ERROR" ]]; then
    printf "%-6s %-6s %-8s %-6s %-10s %s\n" "[$count]" "ERROR" "${declared}k" "-" "-" "$rel_path"
    errors=$((errors + 1))
    continue
  fi

  estimated=$(estimate_bitrate_from_cutoff "$cutoff")

  if (( estimated < declared )); then
    fakes=$((fakes + 1))
    printf "%-6s %-6s %-8s %-6s %-10s %s\n" "[$count]" "FAKE" "${declared}k" "~${estimated}k" "~${cutoff}Hz" "$rel_path"
    if [[ "$DRY_RUN" == "false" ]]; then
      reencode_file "$file" "$estimated"
      echo "        ↳ re-encoded to ${estimated}k"
    fi
  else
    printf "%-6s %-6s %-8s %-6s %-10s %s\n" "[$count]" "OK" "${declared}k" "~${estimated}k" "~${cutoff}Hz" "$rel_path"
  fi

done < <(find "$MUSIC_DIR" -type f -iname '*.mp3' -print0 | sort -z)

echo ""
echo "=== Summary ==="
echo "Analyzed: $count"
echo "Fakes:    $fakes"
echo "Errors:   $errors"
echo "Dry run:  $DRY_RUN"
