# VIDEO MODE

Build the video from the narration audio: prepare it (its pauses stay as recorded unless the user wants them trimmed), time every word, add beat-matched music, design the motion graphics on the bundled engine, check them, and render.

Final output (in `output/`):

- `<slug>.html`: a standalone page with a player. Fonts, timings and audio are inlined, so it plays with no other file.
- `<slug>.mp4`: 1920x1080, 60 fps, H.264 High, yuv420p, BT.709, with AAC 48 kHz stereo (384 kbps target), mastered to -14 LUFS. These are YouTube's recommended upload settings.

Everything else goes in `sources/`. Paths below are relative to the video folder, and `S=<skill>/scripts`.

## 0. Intake

- **Audio:** use the file the user named. If AUDIO MODE produced several, ask which, listing each with its length. Copy a user file into `sources/audio/`.
- **Script:** `sources/script/narration.txt` if it exists, or a file the user gives (copy it there). Without a script, the transcript is used, and step 3 explains how.
- **Lengths:** measure the audio before asking, so the pause question can name both lengths: `uv run --script $S/trim_silence.py sources/audio/<file> --dry-run`.
- **Preferences:** skip whatever the prompt already says. Ask the rest with `AskUserQuestion`. It takes at most four questions per call, so ask the first four together and the format in a second call. When the prompt already answered some, one call is enough.
  1. **Pauses:** "Keep the pauses (Recommended)" (the narration plays as recorded, with only the silence before the first word and after the last cut), "Trim the pauses" (each pause becomes 0.12 to 0.26 s, for a faster pace). Put the measured length into each description. As Other: for example a lighter trim. Never trim without asking. Keeping the pauses is the default.
  2. **Look:** "Dark pastel (Recommended)" (deep navy, peach, lavender and mint accents, soft glow, light grain: the look of the user's earlier intro), "Light and clean", "Bold and colourful". As Other: a description or brand colours.
  3. **Music:** "Lo-fi track + generated beat (Recommended)" (a found CC0 track, fast, rhythmic and smooth, with drums synthesized for this video and locked to it), "Original beat only" (composed in code for this video, so it fits the narration exactly, with no license to check), "Lo-fi track only" (the found track as it is), "No music". As Other: calmer, a mood, or a track the user has the rights to.
  4. **Sound effects:** "Light (Recommended)" (whooshes on cuts, pops as things appear, an impact on the big reveal, typing ticks), "None", "Stronger".
  5. **Format:** "1080p, 60 fps (Recommended)", "4K, 60 fps" (sharper on YouTube because 4K uploads get a better codec, about 4x the render time), "1080p, 30 fps".
- **Captions are always on,** so never ask about them. The HTML has them with a CC toggle (the button and the `c` key), and each word lights up as it is spoken. The MP4 has them burned in, unless the user asks to leave them out (`--no-captions` in step 10).
- Preferences the user gives (here or in the prompt) override the defaults in this file.

## 1. Prerequisites

`uv`, `ffmpeg` and Google Chrome (or Playwright's Chromium: `uv run --with playwright playwright install chromium`). The Whisper model must be cached. If `~/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo` is missing (Apple Silicon), tell the user it is about 1.6 GB, then run `uv run --script $S/make_timings.py --setup`.

## 2. Prepare the narration

```sh
uv run --script $S/trim_silence.py sources/audio/<file> sources/build/narration.wav sources/build/trim-map.json [--trim-pauses]
```

By default the pauses stay as recorded. Only the silence before the first word goes, and the silence after the last word shrinks to a short tail, so the first word lands exactly at the lead-in. Add `--trim-pauses` only when the user chose to trim them: each pause then becomes 0.12 to 0.26 s, depending on how long it was. With it, `--pause-scale 1.2` relaxes a cut that feels breathless, and `0.85` tightens it further. Report the length before and after.

## 3. Time every word

```sh
$S/offline.sh uv run --script $S/make_timings.py sources/build/narration.wav sources/build/timings.json \
    --script sources/script/narration.txt --display sources/script/display.json --offset 2.0
```

- Drop `--display` if there is no such file. `--offset` is the lead-in, the video time of the first word, and must equal `--lead-in` in step 5 (2.0 s by default).
- It prints how much of the script matched what Whisper heard. Below 80 % usually means the wrong script or a bad recording. Investigate before continuing.
- Read `sources/build/timings.txt`. It lists every sentence with start and end times and is the basis for the storyboard.
- Without a script, Whisper's own words are used. Review them for misspelled names and fix those through a `display.json`. If the video folder has no name yet, name it now from the content.

## 4. Music

Decide the drop first: by default, the first drum downbeat lands on the first word. When the narration opens with a problem and then names the product, landing the drop on the name is often stronger. The problem then plays over the quiet intro and the drums arrive with the reveal, as in the user's earlier intro. Say which you chose.

**A found track** (with or without the generated beat). Read `references/music.md`. It covers where to find a fitting CC0 track, how to verify its license, and how to record proof in `sources/music/MUSIC.md`. Then analyse the track:

```sh
uv run --script $S/analyze_music.py sources/music/<track>.mp3 sources/music/music.json
```

It prints the tempo, the drop (the first bar where the drums play), whether the track's beat is steady enough for a generated beat on top, and a per-bar table of overall level and drum level. Use the table to decide:

- **The drop:** `--drop <the analysed drop> --drop-at <video time of the first word or the name>`, then put the reveal visuals on `beat(0)`.
- **Cuts:** whole bars removed so a section change lands on a turn in the narration. In the user's earlier intro, one bar of a breakdown was cut so the drums came back exactly on the reveal "Scala Native". Calculate: video time = lead-in + (source time − drop) − cut length. Skip cuts when nothing lines up nicely. The generated beat follows the edit, with a fill and a crash wherever the drums come back.
- **Length:** a short track loops whole bars automatically.

**An original beat only, composed in code.** No search, no license, and the arrangement fits this narration exactly:

```sh
uv run --script $S/compose_music.py --narration sources/build/narration.wav --lead-in 2.0 \
    --drop-at <video time of the drop> --out sources/music/original-beat.wav --analysis sources/music/music.json \
    [--bpm 92] [--style upbeat|calm] [--breaks A:B] [--seed 7]
```

It writes the track in video time, so mix it with `--drop <drop> --drop-at <drop>` (the same value twice). `--breaks` takes the drums out over a turn in the narration. `--seed` picks the key, chord progression and small variations. Write `sources/music/MUSIC.md` saying it is an original composition made by this skill from synthesized sounds, with the command, seed and key, so the user can dedicate it to the public domain or keep it. Read `references/music.md` for the options.

## 5. Mix and master

```sh
uv run --script $S/mix_audio.py sources/build/narration.wav --music sources/music/<track>.mp3 \
    --analysis sources/music/music.json --lead-in 2.0 --out-dir sources/build [--cut A:B] [--outro 4] [--beat light|strong|off]
```

- It writes `master.wav` (for the MP4), `master.mp3` (for the page) and `mix.json`. `mix.json` holds the length, the narration span, the beat grid in video time and the drum activity, and the page reads all of it.
- Check the printed loudness (about -14 LUFS, peak at or under -1 dBFS) and the segment plan.
- With a found track, it lays the generated beat on top (`--beat light` by default, `strong` for more drive, `off` for the track as it is) and prints how it locked to the track: the shift, and how many kicks and claps it moved onto the track's own hits. A line "beat: left out, because ..." means the track's beat is not steady enough. Tell the user, and offer another track.
- The music plays alone for the lead-in, sits 7 dB lower under the narration, dips a further 6 dB under each phrase, and closes on a bar line with a low-pass sweep and fade. The ending waits for the first bar line at least `--outro` seconds (default 4) after the last word, so the end card lasts 4 s plus up to one bar.
- `--bed-db`, `--duck-db`, `--outro` and `--fade` adjust that.
- Without music, leave out `--music` and `--analysis`.

## 6. Storyboard

Read `references/motion-design.md`, then write `sources/build/storyboard.md`. Give one row per scene:

- the cue phrase that starts it, and its time range
- the narration it covers
- the visual idea and the main elements, with the words they enter on
- the transition in, and the chapter label if any

Aim for a scene change every 4 to 7 s at the turns in the narration, and something new within each scene every 0.3 to 1 s: every noun, verb and list item gets its own entrance on its word. The intro the user approved had 66 visual moments in 28.5 s (see "Density" in `motion-design.md`). The storyboard keeps the scenes coherent. Write it before any scene code.

On-screen text must be as true as the narration. Take commands, URLs, file names, numbers and names from the script, the user's sources or the project itself. When a detail is unknown (an install command, a URL), show what is known ("Homebrew") or a plainly generic placeholder, and list every invented illustration (example file names, sample data) in the final report, so the user can check them.

Never show a key, password, token or other secret, on screen or in the captions, even when a source shows one. Use a placeholder that is plainly fake, such as `<API_TOKEN>` or `••••••••`. If the narration itself reads out a secret, tell the user: only a new narration (ENTER SCRIPT MODE) takes it out of the voice. Step 9 checks for secrets. Internal names, internal host names and internal URLs may be shown and spoken in the video. The privacy rule in SKILL.md is only about where they are sent.

## 7. Scenes, video settings, fonts

Read `references/engine-api.md`. Write `sources/build/scenes/scenes.html`, `scenes.css` and `scenes.js`, and `sources/build/video.json`. Then fetch the fonts. Re-run this whenever the text on screen changes, because only the characters used are kept:

```sh
uv run --script $S/fetch_font.py "Inter" sources/build/fonts --text sources/build/scenes sources/build/timings.json
uv run --script $S/fetch_font.py "JetBrains Mono" sources/build/fonts --text sources/build/scenes sources/build/timings.json
```

Copy the printed `fonts` entries into `video.json`, with paths relative to it (`fonts/...`). For Korean, use a Hangul family for the `ui` role, such as "Noto Sans KR", "IBM Plex Sans KR" or "Gothic A1" ("Black Han Sans" or "Do Hyeon" for headlines). Latin-only fonts have no Hangul.

## 8. Build the page

```sh
python3 $S/build_html.py --video sources/build/video.json --mix sources/build/mix.json --timings sources/build/timings.json \
    --audio sources/build/master.mp3 --scenes sources/build/scenes --out output/<slug>.html
```

The page's Content Security Policy blocks every request to another address, so nothing from the video can leave through the page, also not while `render_video.py` runs it in Chrome. The builder also refuses scene files that load something from outside or leave the page for another address.

**Sound effects** (unless the user chose none) take one more round, because the scenes say where they go. The engine adds a whoosh for every `cut()`, an impact for every `flash()` and a pop for every lone `ring()`, and scenes add others with `sfx()` (see `engine-api.md`). Export them from the built page, mix again with them, and build again:

```sh
uv run --script $S/render_video.py output/<slug>.html --export-sfx sources/build/sfx.json
uv run --script $S/mix_audio.py ... --sfx sources/build/sfx.json [--sfx-level medium]   # the step 5 command plus these
python3 $S/build_html.py ...                                                          # the command above again
```

Repeat the three commands whenever the scenes change.

## 9. Check, then look at the frames

```sh
uv run --script $S/render_video.py output/<slug>.html --check
uv run --script $S/render_video.py output/<slug>.html --stills auto --out-dir sources/build/stills --debug
```

`--check` runs every frame at 0.25 s steps in a few seconds. Fix every ERROR. Also fix the `captions`, `edge` and `overflow` notes unless an element is meant to sit there (it ignores brief contact while things fly in or out). Its `motion` line gives the elements entering per second and the longest stretch with nothing new. The intro the user approved measured 3.5 per second and 1.25 s. Under about 2 per second, or a stretch over 2 s, means adding beats to the storyboard there.

`--check` also lists every `secret`: text that looks like a key, password or token, on screen, in the captions or anywhere in the page source, comments in `scenes.js` included. It never prints a secret in full. A secret makes it exit with 1: replace it with a placeholder. Only the user can decide that a match is not a secret.

`--stills auto` saves the middle of every scene and the moment just after every cut, and contact sheets of four stills each at half size (`sheet-01.png`, ...). `--debug` prints the time, scene and current word in the corner. Look at every sheet with the Read tool, open a single still where something needs a closer look, and fix what you see. A session can view only so many images: when a view comes back as "[media removed: request limit]", wait and view it again. Never change the layout on a guess about a frame you did not see:

- text clipped, overlapping, or too small to read on a phone (labels under 22 px, body text under 26 px)
- an empty or static-looking frame, or a crowded one (more than about seven words of on-screen text besides the captions)
- weak contrast
- things colliding with the captions
- a visual that does not match the words being spoken (add stills at specific cues: `--stills 12.3,18.9`)

Rebuild and re-check after each round. To judge motion, render a short preview clip and offer it to the user. JPEG frames make it quicker:

```sh
uv run --script $S/render_video.py output/<slug>.html --audio sources/build/master.wav --out sources/build/preview.mp4 \
    --from 10 --to 20 --format jpeg
```

## 10. Render the video

```sh
uv run --script $S/render_video.py output/<slug>.html --audio sources/build/master.wav --out output/<slug>.mp4
```

- Add `--scale 2` for 4K, `--fps 30` for 30 fps, and `--no-captions` when captions should stay out of the video.
- Run it in the background and pass progress on to the user. It prints a progress line every 10 s, so watch it with a Monitor. The user asked "Still doing?" during an earlier 18-minute render, so do not go quiet.
- Parallel workers (default: half the CPU cores, up to 8) render about 30 to 45 frames per second at 1080p on an Apple M-series Mac. A 75 s video at 60 fps takes 2 to 3 minutes. 4K takes about 4 times as long. The video bitrate is held to about 24 Mbit/s on average (80 at 4K), still twice YouTube's recommendation, which keeps the file a manageable size (about 90 MB for 30 s). Each worker's segment is limited on its own, so short peaks go higher.

## 11. Verify

```sh
ffprobe -v error -show_entries stream=codec_name,profile,width,height,r_frame_rate,pix_fmt,color_space,sample_rate,channels -show_entries format=duration -of compact output/<slug>.mp4
ffmpeg -hide_banner -nostats -i output/<slug>.mp4 -af ebur128=peak=true -f null - 2>&1 | grep -A8 Summary
ffmpeg -v error -y -ss 12 -i output/<slug>.mp4 -frames:v 1 sources/build/stills/mp4-12s.png
```

- Confirm the streams, the length (the same as `mix.json`) and the loudness.
- Look at two or three frames taken from the MP4.

## 12. Report

- The two output files with absolute paths, length, resolution and frame rate, and file sizes.
- Whether the narration's pauses were kept or trimmed.
- The music: title, artist, license, and the optional credit line, plus the generated beat's setting (light, strong or off). Point to `sources/music/MUSIC.md` and add its Content ID advice.
- A short scene list from the storyboard.
- What the user should check, and how revisions work. Revisions stay in VIDEO MODE:
  - a visual change means editing the scenes, then rebuild, check and render again
  - a different track means mixing again, then rebuild
  - a narration change means going back with ENTER SCRIPT MODE or ENTER AUDIO MODE
