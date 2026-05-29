# video-reader

A Claude Code plugin that lets Claude "watch" AND "hear" a video. Claude can't
open a video file, but it can read images and text — so this plugin uses
**ffmpeg** to extract timestamped frames and **whisper.cpp** to produce a
timestamped transcript. Claude reads both, lined up on a shared timeline.

## Requirements

- `ffmpeg` (and `ffprobe`): `brew install ffmpeg`
- `whisper-cpp` (for audio): `brew install whisper-cpp`
- A whisper model (~150MB, one-time):
  ```bash
  mkdir -p ~/.cache/whisper-models
  curl -L -o ~/.cache/whisper-models/ggml-base.en.bin \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
  ```
  For better accuracy, download `ggml-large-v3.bin` instead and pass
  `--model <path>` to the transcribe script.

## Use

```
/video-reader:read ./demo.mp4 what error appears and when?
/video-reader:read ./recording.mov --scene summarize the workflow
```

Or just ask in plain language ("what happens in screencast.mp4?") and Claude
will invoke the skill.

## How it works

1. `scripts/extract_frames.sh` samples frames with ffmpeg:
   - **interval mode** (default): evenly samples the whole clip, auto-choosing
     the interval so the frame count stays under `--max-frames` (default 30).
   - **scene mode** (`--scene`): only grabs frames where the picture changes a
     lot — ideal for screen recordings and slideshows.
   - Frames are downscaled (`--width`, default 768px) to keep vision-token cost
     reasonable, and a manifest maps each `frame_NNNN.jpg` to its timestamp.
2. `scripts/transcribe.sh` extracts the audio (16kHz mono WAV) and runs
   whisper.cpp locally to produce a `[hh:mm:ss --> hh:mm:ss]` transcript.
   Silent videos are detected and skipped.
3. Claude reads the frames and the transcript together and answers, citing
   timestamps — pairing what's shown with what's said.

## Limitations

- Frames are still images; fast events between samples can be missed — raise
  `--max-frames` or use `--scene`.
- Transcription accuracy depends on the whisper model size; small models can
  mishear words (e.g. "console" → "castle"). Use a larger model for hard audio.

## Roadmap ideas

- Extract a specific time range (`--start`/`--end`).
- A `montage` mode that tiles frames into one contact-sheet image (fewer reads).
