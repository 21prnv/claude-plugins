---
description: "Watch / read / analyze a video file. Use when the user gives a video (.mp4, .mov, .webm, .mkv, .avi, .gif) and asks what's in it, to summarize it, find a moment, read on-screen text, or debug a screen recording. Extracts timestamped frames with ffmpeg and reads them as images."
---

# Read a video

The user wants you to understand the contents of a video. You can't open video
files directly, but you CAN read images. This skill extracts timestamped frames
with ffmpeg so you can read them.

## Input

`$ARGUMENTS` contains a video path and (optionally) a question or instructions.
- The first thing that looks like a file path is the **video**.
- Anything else is the **user's question** (e.g. "what error shows up?", "summarize", "find the login screen").
- If no path is present, ask the user for one.

## Steps

1. **Extract frames.** Run the helper script. Start with defaults; for screen
   recordings, slideshows, or anything with distinct scenes, add `--scene`:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/extract_frames.sh" "<video path>" --scene
   ```

   Useful flags:
   - `--max-frames N` (default 30) — hard cap on frames extracted.
   - `--scene` — only grab frames where the picture changes a lot.
   - `--threshold T` (default 0.3) — scene sensitivity; lower = more frames.
   - `--width PX` (default 768) — frame width.
   - `-o DIR` — output dir (defaults to a temp dir).

   If the script reports `ffmpeg not found`, tell the user to run
   `brew install ffmpeg` (macOS) and stop.

2. **Read the manifest** the script prints — it maps each `frame_NNNN.jpg` to a
   timestamp. The frames live in the `FRAMES_DIR=...` path it prints.

3. **Read the frames in order.** Use the `Read` tool on each `frame_*.jpg`.
   Read several per message (parallel tool calls) to go faster. Keep the
   timestamp from the manifest associated with each frame.

4. **Answer.** Describe what happens across the video, anchoring observations to
   timestamps (e.g. "At 0:42 an error dialog appears"). If the user asked a
   specific question, answer it directly and cite the relevant timestamp(s).
   Read on-screen text verbatim when relevant.

## Notes

- Frames are still images — you'll infer motion/sequence from consecutive
  frames, and you cannot hear audio. Say so if the answer depends on sound.
- If 30 frames clearly aren't enough to answer (fast action, dense text), tell
  the user and offer to re-run with a higher `--max-frames` or a narrower
  segment.
- Frames are written to a temp dir; mention the path so the user can inspect or
  delete them.
