#!/usr/bin/env bash
# Extract timestamped frames from a video so Claude can "read" them as images.
#
# Usage:
#   extract_frames.sh <video> [-o OUTDIR] [--max-frames N] [--width PX]
#                              [--scene] [--threshold T] [--fps F]
#
# Modes:
#   interval (default) : evenly samples the whole video. The interval is chosen
#                        automatically so the frame count stays near --max-frames.
#   --scene            : only grabs frames where the picture changes a lot
#                        (good for screen recordings / slideshows / cut scenes).
#                        Falls back to interval sampling if it finds nothing.
#
# Timestamps are the ACTUAL presentation time of each extracted frame, read back
# from ffmpeg. Prints a manifest (frame file -> timestamp) to stdout and writes
# it to OUTDIR/manifest.tsv. Frames: OUTDIR/frame_%04d.jpg.

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

count_frames() { # count frames without a pipeline that can trip pipefail/set -e
  local n=0 f
  for f in "$OUTDIR"/frame_*.jpg; do [[ -e "$f" ]] && n=$((n+1)); done
  echo "$n"
}

MANIFEST="$OUTDIR/manifest.tsv"
META="$OUTDIR/_meta.txt"

# run_extract <select-filter> : runs ffmpeg, returns number of frames produced.
# format=yuvj420p / -pix_fmt yuvj420p: screen recordings use full-range YUV that
# the mjpeg encoder otherwise rejects. The showinfo filter logs each output
# frame's real pts_time to stderr (at info level), which we capture to $META.
run_extract() {
  local select="$1"
  rm -f "$OUTDIR"/frame_*.jpg "$META"
  ffmpeg -nostdin -hide_banner -loglevel info -i "$VIDEO" \
    -vf "${select},scale=${WIDTH}:-1,format=yuvj420p,showinfo" \
    -fps_mode vfr -pix_fmt yuvj420p -q:v 3 "$OUTDIR/frame_%04d.jpg" -y 2>"$META" || true
  count_frames
}

interval_filter() { # echoes an fps filter sized to MAX_FRAMES (or --fps)
  local interval
  if [[ -n "$FPS" ]]; then
    interval="$(awk -v f="$FPS" 'BEGIN{printf "%.4f", 1/f}')"
  else
    interval="$(awk -v d="$DUR" -v m="$MAX_FRAMES" 'BEGIN{
      if (d<=0){print 1; exit} i=d/m; if(i<0.5)i=0.5; printf "%.4f", i }')"
  fi
  echo "fps=1/${interval}"
}

# --- extract ------------------------------------------------------------------
# Scene mode is great for slideshows / hard cuts, but talking-head and
# screen-demo videos have few cuts, leaving big visual gaps. So if scene
# detection yields fewer frames than ~1 per 10s (a "sparse" result), fall back
# to even interval sampling for reliable coverage.
USED_MODE="$MODE"
if [[ "$MODE" == "scene" ]]; then
  N="$(run_extract "select='gt(scene,$SCENE_THRESHOLD)'")"
  MIN_COVERAGE="$(awk -v d="$DUR" -v m="$MAX_FRAMES" 'BEGIN{
    t=int(d/10); if(t<1)t=1; if(t>m)t=m; print t }')"
  if [[ "$N" -lt "$MIN_COVERAGE" ]]; then
    echo "NOTE: scene detection found only $N frame(s) (threshold $SCENE_THRESHOLD) — too sparse for a ${DUR}s video; falling back to interval sampling for even coverage." >&2
    USED_MODE="interval (scene too sparse: $N frame(s))"
    N="$(run_extract "$(interval_filter)")"
  fi
else
  N="$(run_extract "$(interval_filter)")"
fi

# --- build manifest from actual timestamps ------------------------------------
# (portable read loop; macOS bash 3.2 has no `mapfile`)
TIMES=()
while IFS= read -r line; do TIMES+=("$line"); done \
  < <(grep -o 'pts_time:[0-9.]*' "$META" 2>/dev/null | cut -d: -f2 || true)

: > "$MANIFEST"
i=0
for f in "$OUTDIR"/frame_*.jpg; do
  [[ -e "$f" ]] || continue
  t="${TIMES[$i]:-0}"
  printf '%s\t%ss\t%s\n' "$(basename "$f")" "$t" "$(fmt_ts "$t")" >> "$MANIFEST"
  i=$((i+1))
done

# --- if too many frames, keep an evenly-spaced subset -------------------------
COUNT="$(count_frames)"
if [[ "$COUNT" -gt "$MAX_FRAMES" ]]; then
  echo "NOTE: found $COUNT frames; keeping ~$MAX_FRAMES evenly spaced." >&2
  STEP=$(( (COUNT + MAX_FRAMES - 1) / MAX_FRAMES ))
  awk -v step="$STEP" 'NR % step == 1' "$MANIFEST" > "$MANIFEST.keep"
  comm -23 <(ls "$OUTDIR"/frame_*.jpg | xargs -n1 basename | sort) \
           <(cut -f1 "$MANIFEST.keep" | sort) | while read -r drop; do
    rm -f "$OUTDIR/$drop"
  done
  mv "$MANIFEST.keep" "$MANIFEST"
  COUNT="$(count_frames)"
fi

rm -f "$META"

# --- report -------------------------------------------------------------------
echo "==================================================================="
echo "Extracted $COUNT frame(s) to:"
echo "  $OUTDIR"
echo "Video duration: ${DUR}s | mode: ${USED_MODE} | frame width: ${WIDTH}px"
echo "Manifest (frame -> timestamp):"
echo "-------------------------------------------------------------------"
cat "$MANIFEST"
echo "==================================================================="
echo "FRAMES_DIR=$OUTDIR"
