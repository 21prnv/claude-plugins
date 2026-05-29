#!/usr/bin/env bash
# Extract timestamped frames from a video so Claude can "read" them as images.
#
# Usage:
#   extract_frames.sh <video> [-o OUTDIR] [--max-frames N] [--width PX]
#                              [--scene] [--threshold T] [--fps F]
#
# Modes:
#   interval (default) : evenly samples the whole video. The interval is chosen
#                        automatically so the frame count stays <= --max-frames.
#   --scene            : only grabs frames where the picture changes a lot
#                        (good for screen recordings / slideshows / cut scenes).
#
# Prints a manifest (frame file -> timestamp) to stdout and writes it to
# OUTDIR/manifest.tsv. Frames are written as OUTDIR/frame_%04d.jpg.

set -euo pipefail

VIDEO=""
OUTDIR=""
MAX_FRAMES=30
WIDTH=768
MODE="interval"
SCENE_THRESHOLD="0.3"
FPS=""

usage() { sed -n '/^# Extract/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out)       OUTDIR="$2"; shift 2;;
    --max-frames)   MAX_FRAMES="$2"; shift 2;;
    --width)        WIDTH="$2"; shift 2;;
    --scene)        MODE="scene"; shift;;
    --threshold)    SCENE_THRESHOLD="$2"; shift 2;;
    --fps)          FPS="$2"; shift 2;;
    -h|--help)      usage; exit 0;;
    -*)             echo "Unknown option: $1" >&2; exit 2;;
    *)              if [[ -z "$VIDEO" ]]; then VIDEO="$1"; shift;
                    else echo "Unexpected argument: $1" >&2; exit 2; fi;;
  esac
done

# --- preflight ----------------------------------------------------------------
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ERROR: ffmpeg not found. Install it with:  brew install ffmpeg" >&2
  exit 127
fi
if [[ -z "$VIDEO" ]]; then echo "ERROR: no video path given." >&2; usage; exit 2; fi
if [[ ! -f "$VIDEO" ]]; then echo "ERROR: no such file: $VIDEO" >&2; exit 2; fi

if [[ -z "$OUTDIR" ]]; then
  OUTDIR="$(mktemp -d "${TMPDIR:-/tmp}/readvid.XXXXXX")"
fi
mkdir -p "$OUTDIR"

DUR="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO" 2>/dev/null || echo "")"
[[ -z "$DUR" || "$DUR" == "N/A" ]] && DUR="0"

fmt_ts() { # seconds -> H:MM:SS or M:SS
  awk -v s="$1" 'BEGIN{
    s=s+0; h=int(s/3600); m=int((s%3600)/60); sec=s-int(s/60)*60;
    if(h>0) printf "%d:%02d:%05.2f", h, m, sec; else printf "%d:%05.2f", m, sec;
  }'
}

MANIFEST="$OUTDIR/manifest.tsv"
: > "$MANIFEST"

# --- extract ------------------------------------------------------------------
if [[ "$MODE" == "scene" ]]; then
  META="$OUTDIR/_meta.txt"
  ffmpeg -nostdin -hide_banner -loglevel error -i "$VIDEO" \
    -vf "select='gt(scene,$SCENE_THRESHOLD)',scale=${WIDTH}:-1,metadata=print:file=$META" \
    -vsync vfr -q:v 3 "$OUTDIR/frame_%04d.jpg" -y

  # Pull pts_time for each selected frame, in order.
  mapfile -t TIMES < <(grep -o 'pts_time:[0-9.]*' "$META" 2>/dev/null | cut -d: -f2 || true)
  i=0
  for f in "$OUTDIR"/frame_*.jpg; do
    [[ -e "$f" ]] || continue
    t="${TIMES[$i]:-0}"
    printf '%s\t%ss\t%s\n' "$(basename "$f")" "$t" "$(fmt_ts "$t")" >> "$MANIFEST"
    i=$((i+1))
  done

  # If scene detection found too many, keep an evenly-spaced subset.
  COUNT=$(grep -c . "$MANIFEST" || echo 0)
  if (( COUNT > MAX_FRAMES )); then
    echo "NOTE: scene detection found $COUNT frames; keeping ~$MAX_FRAMES evenly spaced." >&2
    STEP=$(( (COUNT + MAX_FRAMES - 1) / MAX_FRAMES ))
    awk -v step="$STEP" 'NR % step == 1' "$MANIFEST" > "$MANIFEST.keep"
    # delete frames not kept
    comm -23 <(ls "$OUTDIR"/frame_*.jpg | xargs -n1 basename | sort) \
             <(cut -f1 "$MANIFEST.keep" | sort) | while read -r drop; do
      rm -f "$OUTDIR/$drop"
    done
    mv "$MANIFEST.keep" "$MANIFEST"
  fi
else
  if [[ -z "$FPS" ]]; then
    INTERVAL="$(awk -v d="$DUR" -v m="$MAX_FRAMES" 'BEGIN{
      if (d<=0) {print 1; exit}
      i=d/m; if(i<0.5) i=0.5; printf "%.4f", i }')"
  else
    INTERVAL="$(awk -v f="$FPS" 'BEGIN{printf "%.4f", 1/f}')"
  fi
  ffmpeg -nostdin -hide_banner -loglevel error -i "$VIDEO" \
    -vf "fps=1/${INTERVAL},scale=${WIDTH}:-1" -q:v 3 "$OUTDIR/frame_%04d.jpg" -y

  i=0
  for f in "$OUTDIR"/frame_*.jpg; do
    [[ -e "$f" ]] || continue
    t="$(awk -v i="$i" -v iv="$INTERVAL" 'BEGIN{printf "%.2f", i*iv}')"
    printf '%s\t%ss\t%s\n' "$(basename "$f")" "$t" "$(fmt_ts "$t")" >> "$MANIFEST"
    i=$((i+1))
  done
fi

NFRAMES=$(grep -c . "$MANIFEST" 2>/dev/null || echo 0)
echo "==================================================================="
echo "Extracted $NFRAMES frame(s) to:"
echo "  $OUTDIR"
echo "Video duration: ${DUR}s | mode: $MODE | frame width: ${WIDTH}px"
echo "Manifest (frame -> timestamp):"
echo "-------------------------------------------------------------------"
cat "$MANIFEST"
echo "==================================================================="
echo "FRAMES_DIR=$OUTDIR"
