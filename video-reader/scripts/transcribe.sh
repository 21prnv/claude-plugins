#!/usr/bin/env bash
# Transcribe the audio of a video/audio file into a timestamped transcript,
# so Claude can "hear" the narration and line it up with extracted frames.
#
# Pipeline: ffmpeg extracts 16kHz mono WAV -> whisper.cpp transcribes locally.
#
# Usage:
#   transcribe.sh <video> [-o OUTDIR] [--model PATH] [--lang LANG]
#
# Options:
#   -o, --out DIR   Output dir (defaults to a temp dir).
#   --model PATH    Path to a whisper ggml .bin model. If omitted, searches
#                   common locations and falls back to ~/.cache/whisper-models.
#   --lang LANG     Language code (default: en). Use "auto" to auto-detect.
#
# Writes OUTDIR/transcript.txt (timestamped) and prints it to stdout.

set -euo pipefail

VIDEO=""
OUTDIR=""
MODEL=""
LANG="en"

usage() { sed -n '/^# Transcribe/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--out)   OUTDIR="$2"; shift 2;;
    --model)    MODEL="$2"; shift 2;;
    --lang)     LANG="$2"; shift 2;;
    -h|--help)  usage; exit 0;;
    -*)         echo "Unknown option: $1" >&2; exit 2;;
    *)          if [[ -z "$VIDEO" ]]; then VIDEO="$1"; shift;
                else echo "Unexpected argument: $1" >&2; exit 2; fi;;
  esac
done

# --- preflight ----------------------------------------------------------------
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ERROR: ffmpeg not found. Install it with:  brew install ffmpeg" >&2
  exit 127
fi

WHISPER=""
for c in whisper-cli whisper-cpp main; do
  if command -v "$c" >/dev/null 2>&1; then WHISPER="$c"; break; fi
done
if [[ -z "$WHISPER" ]]; then
  echo "ERROR: whisper.cpp not found. Install it with:  brew install whisper-cpp" >&2
  exit 127
fi

if [[ -z "$VIDEO" ]]; then echo "ERROR: no input file given." >&2; usage; exit 2; fi
if [[ ! -f "$VIDEO" ]]; then echo "ERROR: no such file: $VIDEO" >&2; exit 2; fi

# --- locate a model -----------------------------------------------------------
if [[ -z "$MODEL" ]]; then
  for m in \
    "$HOME/.cache/whisper-models/ggml-base.en.bin" \
    "$HOME/.cache/whisper-models/"ggml-*.bin \
    /opt/homebrew/share/whisper-cpp/ggml-*.bin \
    ./models/ggml-*.bin; do
    if [[ -f "$m" ]]; then MODEL="$m"; break; fi
  done
fi
if [[ -z "$MODEL" || ! -f "$MODEL" ]]; then
  cat >&2 <<EOF
ERROR: no whisper model (.bin) found. Download one, e.g. base.en (~150MB):

  mkdir -p ~/.cache/whisper-models
  curl -L -o ~/.cache/whisper-models/ggml-base.en.bin \\
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin

Or pass --model /path/to/ggml-model.bin
EOF
  exit 2
fi

# --- check the input actually has an audio stream -----------------------------
HAS_AUDIO="$(ffprobe -v error -select_streams a -show_entries stream=index \
  -of csv=p=0 "$VIDEO" 2>/dev/null | head -1 || true)"
if [[ -z "$HAS_AUDIO" ]]; then
  echo "NOTE: no audio stream found in this file — nothing to transcribe." >&2
  exit 3
fi

if [[ -z "$OUTDIR" ]]; then
  OUTDIR="$(mktemp -d "${TMPDIR:-/tmp}/readvid-audio.XXXXXX")"
fi
mkdir -p "$OUTDIR"

# --- extract audio: 16kHz mono WAV (what whisper expects) ---------------------
WAV="$OUTDIR/audio.wav"
ffmpeg -nostdin -hide_banner -loglevel error -i "$VIDEO" \
  -vn -ac 1 -ar 16000 -c:a pcm_s16le "$WAV" -y

# --- transcribe ---------------------------------------------------------------
OUTBASE="$OUTDIR/transcript"
LANGARG=()
[[ "$LANG" != "auto" ]] && LANGARG=(-l "$LANG")

# -otxt writes <OUTBASE>.txt ; whisper-cli prints [hh:mm:ss --> hh:mm:ss] lines
# to stdout, which we also keep as the timestamped transcript.
"$WHISPER" -m "$MODEL" -f "$WAV" "${LANGARG[@]}" -otxt -of "$OUTBASE" \
  >"$OUTBASE.timed.txt" 2>/dev/null || {
    echo "ERROR: transcription failed." >&2; exit 1; }

# Prefer the timestamped stdout capture; fall back to the plain .txt.
FINAL="$OUTBASE.timed.txt"
if [[ ! -s "$FINAL" ]]; then FINAL="$OUTBASE.txt"; fi

echo "==================================================================="
echo "Transcript (model: $(basename "$MODEL")):"
echo "-------------------------------------------------------------------"
cat "$FINAL"
echo "==================================================================="
echo "TRANSCRIPT_FILE=$FINAL"
echo "AUDIO_DIR=$OUTDIR"
