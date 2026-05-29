# video-reader

A Claude Code plugin that lets Claude "watch" a video. Claude can't open a video
file, but it can read images — so this plugin uses **ffmpeg** to extract
timestamped frames, which Claude then reads in order.

## Requirements

- `ffmpeg` (and `ffprobe`): `brew install ffmpeg` on macOS.

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
     reasonable.
2. The script prints a manifest mapping each `frame_NNNN.jpg` to its timestamp.
3. Claude reads the frames in order and answers, citing timestamps.

## Limitations

- No audio — frames are silent stills.
- Frame sampling can miss fast events between samples; raise `--max-frames` or
  use `--scene` for dense content.

## Roadmap ideas

- Audio transcription (whisper.cpp / API) to add a spoken-word track.
- Extract a specific time range (`--start`/`--end`).
- A `montage` mode that tiles frames into one contact-sheet image (fewer reads).
