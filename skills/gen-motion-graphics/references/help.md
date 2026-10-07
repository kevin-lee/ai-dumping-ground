# Help text

Reply with everything below the line, exactly as written, and nothing else: no mode tag, no summary before or after. It is Markdown, so send it as it is and never wrap it in a code fence. The terminal renders the headings, tables, lists and code spans.

---

# gen-motion-graphics

Narrated motion-graphics videos, made in three modes.

## Start

| Command | Starts |
|---|---|
| `/gen-motion-graphics` | By asking how to start |
| `/gen-motion-graphics script <prompt>` | SCRIPT MODE with your prompt (also `text`, `narration`) |
| `/gen-motion-graphics audio <script.txt>` | AUDIO MODE with your own script |
| `/gen-motion-graphics video <audio> [script.txt]` | VIDEO MODE with your own audio |
| `/gen-motion-graphics help` | Shows this help |

## Modes

They run in this order. Say the phrase to switch.

### `ENTER SCRIPT MODE`

Writes the voice-over narration for a target duration.

- Optional: skip it by bringing your own script.

### `ENTER AUDIO MODE`

Speaks the script on this machine, offline.

- **English** (and Kokoro's other languages): Kokoro, default voice `af_heart`.
- **Korean:** Qwen3-TTS, default voice Sohee in a cheerful style. The style changes only the tone, never your words.
- Pick a voice or ask for samples, then one or more playback speeds: `1x`, `1.18x`, `1.30x`, or your own list such as `1, 1.3, 1.5`. A 1.18x file is 1.18 times shorter than the 1x file.
- Every file is checked against the script with a local Whisper model.
- Optional: skip it by bringing your own audio file.

### `ENTER VIDEO MODE`

Builds the video from the narration audio.

- **Pauses:** kept as recorded. It asks whether to trim them for a faster pace.
- **Music:** lo-fi on the beat. By default a CC0 track it finds, with drums it generates and locks to that track. Or an original beat it composes in code.
- **Sound effects:** light, on cuts, reveals and typing.
- **Motion graphics:** designed for every sentence, with something new on screen every second or so.
- **Captions:** always on. The HTML has a CC toggle and lights up each word as it is spoken. The MP4 has them burned in unless you say no.
- **Output:** a standalone HTML page and an MP4 (1920x1080, 60 fps, H.264, AAC, -14 LUFS).

The skill stays in a mode until you say the next phrase, so you can revise freely. You can go back at any time, for example with `ENTER SCRIPT MODE`. Files made after that point are then out of date.

## What to tell it

| Mode | Tell it |
|---|---|
| SCRIPT | Topic, target duration (for example 60 seconds), audience and tone, language, and sources for facts (this repository, docs, URLs) |
| AUDIO | Voice and speeds, or let it ask |
| VIDEO | Whether to trim the pauses (they stay by default), the look (colours, style), the music (a found track with a generated beat, the track alone, an original composed beat, a mood, or a track you have the rights to), sound effects (light, none, stronger), 1080p60 (default) or 4K60, and "no burned-in captions" if you want them only in the HTML |

## Output

| Where you run it | Folder |
|---|---|
| In a Git repository | `.ai/video/<short-summary>/output/` for the HTML page and the MP4, and `.ai/video/<short-summary>/sources/` for the script, audio, samples, music, license proof and build files |
| Elsewhere | `video/<short-summary>/output/` and `video/<short-summary>/sources/` |

Name a folder in your prompt to use it instead.

## Privacy

Speech and transcription run locally with the network blocked, so your script and audio never leave this machine. The network is used only to download models and packages once, and to find music and fonts.

## Requirements

- macOS or Linux, `uv`, `ffmpeg`, and Google Chrome (or Playwright's Chromium).
- First runs download the Kokoro model (about 350 MB), Whisper large-v3-turbo (about 1.6 GB) and, for Korean, the Qwen3-TTS 1.7B model (about 4.2 GB). You are asked before each.
