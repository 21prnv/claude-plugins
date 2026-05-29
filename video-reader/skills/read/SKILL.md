---
description: "Watch / read / analyze a video file. Use when the user gives a video (.mp4, .mov, .webm, .mkv, .avi, .gif) and asks what's in it, to summarize it, find a moment, read on-screen text, understand the narration, or debug a screen recording. Extracts timestamped frames AND a timestamped audio transcript with ffmpeg + whisper, then reads them together."
---

# Read a video

The user wants you to understand the contents of a video. You can't open video
files directly, but you CAN read images and text. This skill extracts:
- **timestamped frames** (so you can SEE the video), and
- a **timestamped transcript** (so you can "HEAR" the narration).

Both share the same timeline, so you can line up what's said with what's shown.

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

2. **Transcribe the audio** (unless the user only cares about visuals). Run:

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/transcribe.sh" "<video path>"
   ```

   - It extracts the audio and runs whisper.cpp locally, printing a transcript
     with `[hh:mm:ss --> hh:mm:ss]` timestamps.
   - Exit code 3 / "no audio stream" means the video is silent — just skip the
     transcript and continue with frames only.
   - "whisper.cpp not found" → tell the user `brew install whisper-cpp`.
   - "no whisper model found" → the script prints the exact curl command to
     download one (~150MB base.en); relay it and stop.
   - For higher accuracy on hard audio, mention they can download a larger model
     (e.g. `ggml-large-v3.bin`) and pass `--model <path>`.

3. **Read the manifest** the frame script printed — it maps each
   `frame_NNNN.jpg` to a timestamp. Frames live in the `FRAMES_DIR=...` path.

4. **Read the frames in order.** Use the `Read` tool on each `frame_*.jpg`.
   Read several per message (parallel tool calls) to go faster. Keep each
   frame's timestamp from the manifest.

5. **Answer over the merged timeline.** Combine what you SEE (frames) with what
   you HEAR (transcript), anchored to timestamps — e.g. "At 0:09 the narrator
   says 'watch the console' while the frame at 0:10 shows the error dialog."
   If the user asked a specific question, answer it directly and cite the
   relevant timestamp(s). Read on-screen text and quote narration verbatim when
   relevant.

## Notes

- Frames are still images — infer motion/sequence from consecutive frames.
- Transcription accuracy depends on the whisper model size; small models can
  mishear words. If a quoted word seems off, flag it as approximate.
- If 30 frames clearly aren't enough (fast action, dense text), tell the user
  and offer to re-run with a higher `--max-frames` or a narrower segment.
- Outputs go to temp dirs; mention the paths so the user can inspect or delete
  them.
