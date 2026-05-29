# prnv-plugins

A personal [Claude Code](https://code.claude.com) plugin marketplace.

## Plugins

| Plugin | Description |
|--------|-------------|
| [video-reader](./video-reader) | Let Claude "watch" and "hear" a video: timestamped frames via ffmpeg + a timestamped transcript via whisper.cpp. |

## Install

In Claude Code:

```
/plugin marketplace add 21prnv/claude-plugins
/plugin install video-reader@prnv-plugins
```

Then use it:

```
/video-reader:read ./demo.mp4 what happens in this video?
```

## Requirements

- `video-reader` needs ffmpeg (`brew install ffmpeg`) and, for audio
  transcription, whisper-cpp (`brew install whisper-cpp`) plus a whisper model.
  See the [plugin README](./video-reader) for the one-line model download.
