# prnv-plugins

A personal [Claude Code](https://code.claude.com) plugin marketplace.

## Plugins

| Plugin | Description |
|--------|-------------|
| [video-reader](./video-reader) | Let Claude "watch" a video by extracting timestamped frames with ffmpeg, then reading them as images. |

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

- `video-reader` needs ffmpeg: `brew install ffmpeg` (on Apple Silicon under
  Rosetta, use `arch -arm64 brew install ffmpeg`).
