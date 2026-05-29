# video-reader plugin — progress notes

## Status: WORKING (v0.2.3), pushed to https://github.com/21prnv/claude-plugins

The plugin is installed (cache: `~/.claude/plugins/cache/prnv-plugins/video-reader/`)
and verified end-to-end on a real screen recording.

## What it does
Lets Claude "watch" + "hear" a video. `extract_frames.sh` pulls timestamped
frames (ffmpeg); `transcribe.sh` makes a timestamped transcript (whisper.cpp).
The `read` skill reads both and answers over a shared timeline.

## Installed deps (this machine)
- ffmpeg 8.1.1 (`brew`), whisper-cli (`brew install whisper-cpp`)
- whisper model: `~/.cache/whisper-models/ggml-base.en.bin` (~141MB)

## Bugs fixed while testing on real recordings (all in extract_frames.sh)
1. Full-range YUV from screen recordings → mjpeg encoder rejected it (0 frames).
   Fix: `format=yuvj420p` in filter + `-pix_fmt yuvj420p`.
2. `mapfile` is bash 4+; macOS has bash 3.2. Fix: portable `while read` loop.
3. `count_frames` used `ls|wc` pipeline → tripped `pipefail`/`set -e` at 0 frames,
   aborting before the scene→interval fallback. Fix: pipeline-free loop counter.
4. Scene mode finding 0 cuts now auto-falls back to interval sampling.
5. Timestamps were all 0:00 — `metadata=print` emitted nothing. Fix: use
   `showinfo` at `-loglevel info`, capture stderr to $META, grep pts_time.

## Verified
- Real .mov (X/Twitter browsing in Brave): 17 frames, timestamps 0:00–0:08. ✓
- Frames are readable (saw the Twitter UI, AndroClaw post, etc.). ✓

## Known limitations / next steps
- Local cache at v0.2.3 source is current; if user already installed an older
  version, run `/plugin update` or re-add marketplace + `/reload-plugins`.
- transcribe.sh tested earlier on synthetic audio (worked); the X recording was
  silent (exit 3 = no audio stream, handled gracefully). Re-verify transcribe on
  a real recording WITH audio.
- v0.2.2 commit message was inaccurate (claimed showinfo but didn't change it);
  v0.2.3 corrects it. History is fine, just noting.
- Roadmap: --start/--end time range; montage/contact-sheet mode.

## How to use
```
/video-reader:read "<path to video>" <your question>
```
Or call the two scripts directly from the cache/scripts dir.
