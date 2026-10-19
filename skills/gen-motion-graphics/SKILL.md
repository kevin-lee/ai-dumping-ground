---
name: gen-motion-graphics
description: Make narrated motion-graphics videos (YouTube intros, explainers, product promos) in three sequential modes. SCRIPT MODE writes a voice-over narration sized to a target duration. AUDIO MODE turns it into speech on this machine with the network blocked (Kokoro, or Qwen3-TTS for Korean), with a choice of voice, samples and speeds. VIDEO MODE asks whether to trim the pauses (they stay by default), adds beat-matched royalty-free lo-fi music, and builds a standalone HTML animation plus a YouTube-ready MP4, or only the HTML when the user chooses it. Use it whenever the user runs /gen-motion-graphics, says "ENTER SCRIPT MODE", "ENTER AUDIO MODE" or "ENTER VIDEO MODE", or asks for a narration script for a video, a local text-to-speech voice-over, or an animated video made from narration audio, even if they do not name the skill.
---

# gen-motion-graphics

Turn a topic into a finished, narrated motion-graphics video through three modes that run in order:

1. **SCRIPT MODE** writes the voice-over text. Optional: skipped when the user brings a script.
2. **AUDIO MODE** speaks it with a local text-to-speech (TTS) model. Optional: skipped when the user brings audio.
3. **VIDEO MODE** analyses the audio and builds the video: standalone HTML and an MP4, or only the HTML.

`<skill>` below means this skill's directory. The helper scripts are in `<skill>/scripts/`. The Python ones run with `uv run --script` (they declare their own dependencies) and print their usage with `--help`.

## Starting

The text after `/gen-motion-graphics` selects the starting point. A shorthand works only here, when the skill starts. Later, modes change only through the phrases in "Modes".

| Argument | Start |
|---|---|
| none | Ask how to start (below) |
| `script`, `text`, or `narration` (plus an optional prompt) | SCRIPT MODE, using the rest as the prompt |
| `audio` (plus a text file) | AUDIO MODE. A narration text file is required. If none was given, ask for it |
| `video` (plus an audio file and an optional script) | VIDEO MODE. An audio file is required. If none was given, ask for it |
| `help`, `--help`, `-h` | Reply with the Markdown below the line in `references/help.md`, as it is (never in a code fence), and stop |

A message that says "ENTER SCRIPT MODE" (or AUDIO, VIDEO) also starts the skill, in that mode.

With an argument or a mode phrase, ask the location question alone, before the first file is written, unless "Where files go" says to skip it.

With no argument, call `AskUserQuestion` once with two questions. The first is "How do you want to start?" with these options:

1. "Write a script (SCRIPT MODE)": a narration from a topic and a target duration.
2. "I have a script": the user gives a text file, then AUDIO MODE.
3. "I have an audio file": the user gives an audio file (and optionally its script), then VIDEO MODE.
4. "Help": reply with the help text as for `help` above, and stop.

The second is the location question in "Where files go". If the user picks "Help", ignore the second answer.

When a required file is missing, ask for its path. Offer any candidates found under `<base>/*/sources/` when `<base>` is already chosen, else under `./video/*/sources/`, `<output>/video/*/sources/` and `.ai/video/*/sources/` (newest first), and let the user type a path as "Other".

## Modes

- While the skill is active, the very first line of every response is the current mode in brackets, before any summary: `[MODE: SCRIPT]`, `[MODE: AUDIO]` or `[MODE: VIDEO]`. The user then always knows which mode the session is in.
- Stay in the current mode until the user says "ENTER SCRIPT MODE", "ENTER AUDIO MODE" or "ENTER VIDEO MODE". Inside a mode, take any number of revisions ("shorter", "try af_bella", "make the music calmer") without changing mode. Do not move to the next mode on your own, even when the current one is done. The user may want to edit the files first. If they ask for the next mode's work in other words ("now make the audio"), answer in one line with the phrase to say, and wait.
- Order is SCRIPT, then AUDIO, then VIDEO. A mode may be skipped only when its input exists: AUDIO MODE needs a narration text file, and VIDEO MODE needs a narration audio file. If the user asks for a mode whose input is missing, say what is missing and offer to produce it in the previous mode or to take a file from them.
- Going back is allowed. If the script changes after the audio was made, or the audio after the video, say which outputs are now out of date.
- At the end of each mode, give a short summary: what was made, where it is, and what the user should check (read the script, listen to the audio, watch the video). Then name the phrase for the next mode, for example "Edit the script if you like, then say ENTER AUDIO MODE."

Read the reference for a mode when you enter it, not before:

| Mode | Read |
|---|---|
| SCRIPT | `references/script-mode.md` |
| AUDIO | `references/audio-mode.md` |
| VIDEO | `references/video-mode.md`, which points to `engine-api.md`, `motion-design.md` and `music.md` when it needs them |

## Where files go

Each video gets one folder, `<base>/<slug>/`. The user chooses `<base>` once, at the start, and the later modes reuse it.

Get the central folder first: `sh <skill>/scripts/ai-output-dir.sh --print-only` prints `<output>`, the AI output folder of the current project. It is `${AI_AGENT_OUTPUT_DIR:-~/.ai}/<project key>`. The key is `<host>/<owner>/<repo>` from the Git remote, or `local/<folder name>-<hash of the absolute path>` when there is no remote or no Git repository. Do not calculate it yourself. If the script exits with an error, show the message and leave out option 2 below.

Ask "Where should the video files be stored?" with these options, each with the absolute path that it gives:

1. "Current folder": `<base>` is `<absolute current folder>/video`. In a Git repository, add to the description that the files can be committed by accident unless `video/` is ignored.
2. "Central AI output folder": `<base>` is `<output>/video`. Show the full path, for example `/Users/me/.ai/github.com/owner/repo/video/<slug>/`, and say that `<slug>` comes from the video's content.
3. "Other": the user types a folder. `<base>` is that folder. Expand a leading `~`. A relative path is relative to the current folder. Say the resulting absolute path.

Do not ask, and tell the user which folder is used, when:

- The user's prompt names a location. That location is `<base>`.
- An input file is inside an existing video folder (a folder with `sources/` and `output/`, under a folder named `video`). Use that video folder again.

Ask again only if the user asks to change the location. When the first file is written for the central folder, run `sh <skill>/scripts/ai-output-dir.sh` once to create it. If a sandbox blocks a write, tell the user to allow writes to that folder (`sh <skill>/scripts/ai-output-dir.sh --root` prints the central root).

Video folders in the project are an expected place, not old files. Never offer to move them to the central folder.

`<slug>` is a short kebab-case summary of the video's content, for example `ai-skills-intro` or `sourdough-basics-explainer`. When starting from an audio file without a script, transcribe it first (VIDEO MODE does this anyway) and name the folder after its content. If the folder already exists for a different video, add `-2`, `-3`, and so on. If it holds the same video from an earlier session, reuse it and tell the user.

```
<video folder>/
├── output/                       what the user asked for
│   ├── <slug>.html               standalone page: plays with no other file
│   └── <slug>.mp4                YouTube-ready video (not made for "HTML only")
└── sources/                      everything made along the way
    ├── script/                   narration.txt, display.json, lexicon.json
    ├── audio/                    narration-<voice>-<speed>x.wav
    │   └── samples/              voice samples and index.html to compare them
    ├── music/                    the downloaded track, MUSIC.md (license and credit), music.json
    └── build/                    narration.wav, timings, mix, video.json, scenes/, fonts/, stills/
```

Copy files the user provides into `sources/` (never move or modify their originals), so the folder is complete on its own. Do not delete or overwrite the user's own files. When regenerating something you made earlier in the same video folder, overwriting your own output is fine.

## Privacy: nothing confidential goes to a third party

The narration can hold confidential information on purpose, to explain it. The user does not want it, or anything made from it, sent to a third-party service. Anthropic, which runs this conversation, is not a third party, and neither are the organization's own tools (below). Internal names and addresses may be shown and spoken in the video. This rule is only about where they are sent. So:

- Generate speech and transcribe audio only with the local models in this skill, and run those steps through `<skill>/scripts/offline.sh`. It blocks all network access for the command (with `sandbox-exec` on macOS, `unshare` or `firejail` on Linux). If it cannot block the network on this system, ask the user before running without it.
- The network is used only to download packages and models once (the `--setup` steps, which never include the text), to read sources the user points to, and to find and download music and fonts.
- Never paste the narration, or long parts of it, into a web search, a web fetch, or any other third-party service.
- Never put a key, password, token, internal name, internal host name or internal URL into a web search, a web fetch of a site outside the organization, Claude in Chrome, or a Model Context Protocol (MCP) server of a third-party service such as context7. Internal names are project, product, team, system and customer names that are not public. If you do not know whether a name is public, treat it as internal. One word is enough to leak it.
- One exception, for pronunciation: you may look up how to say one ordinary or public word that is part of an internal name, alone. For `atlas-billing-us-2`, look up "atlas", never `atlas-billing-us-2`. Never look up a word that only the organization uses. When you are not sure, ask the user whether you may look the word up. If they say no, ask them how it is said.
- The organization's own MCP servers, for example Jira, Slack, Notion, and GitHub for the organization's repositories, may receive the narration, internal names, internal host names and internal URLs, for example to read the ticket or the page that the video explains. Never write any of it where people outside the organization can read it: a public repository or issue, a channel shared with another company, or an email to someone outside. If you do not know whether a server belongs to the organization, ask the user.
- Never write a key, password or token into any MCP server, the organization's own included. A secret in a ticket, a message or a page spreads to everyone who can read it.

## Modes in brief

**SCRIPT MODE:** needs a topic and a target duration (ask if the duration is missing). Writes `sources/script/narration.txt`: plain text, only the words to be spoken, no stage directions, sized to the duration. Spoken forms of names and symbols go in `display.json` so captions show the written form. Details in `references/script-mode.md`.

**AUDIO MODE:** Kokoro for English (and Kokoro's other languages), Qwen3-TTS for Korean. Check pronunciations first, ask for a voice (or make samples) and one or more speeds, then write one WAV per speed. Details in `references/audio-mode.md`.

**VIDEO MODE:** ask whether to trim the pauses (by default they stay as recorded), about the look, music and sound effects, and then whether to make the HTML and the MP4 (the default, with the MP4's format) or only the HTML (unless already given). Then prepare the narration, time every word, and find and license-check a CC0 lo-fi track, laying a generated beat on top that is locked to it (the default), or compose an original beat in code. Mix and master to -14 LUFS, write the scenes on the bundled engine with light sound effects, check and review stills, build the HTML, and render the MP4 unless the user chose "HTML only". Captions are always on: the HTML has a CC toggle with each word highlighted as it is spoken, and the MP4 (when it is made) has them burned in unless the user says otherwise. Details in `references/video-mode.md`.

## Scripts

| Script | Does |
|---|---|
| `offline.sh <command>` | Runs a command with the network blocked |
| `tts_kokoro.py` | Kokoro speech, voice samples, phoneme check, `--setup` |
| `tts_qwen.py` | Qwen3-TTS speech for Korean, samples, `--setup` |
| `trim_silence.py` | Cuts the silence before the first word and after the last, shortens the pauses only with `--trim-pauses` (any input format), writes a time map |
| `make_timings.py` | Local Whisper word timings aligned to the script, `timings.txt` sheet |
| `fetch_music.py` | Downloads a track from its FMA or OpenGameArt page, checks the license, writes `MUSIC.md` with proof |
| `compose_music.py` | Composes an original lo-fi beat in code, timed to the narration, with its `music.json` |
| `analyze_music.py` | Tempo, a beat grid precise to about a millisecond, the drop, per-bar drum levels, swing |
| `mix_audio.py` | Beat-aligned music edit, a generated beat locked to a found track, ducking, synthesized sound effects, ending, mastering, `mix.json` |
| `fetch_font.py` | Downloads and subsets a Google Fonts family for embedding |
| `build_html.py` | Assembles the standalone page from `assets/template.html` and the scenes |
| `render_video.py` | `--check` lint and secret scan, `--stills` for review, `--export-sfx` sound-effect list, parallel MP4 render |
