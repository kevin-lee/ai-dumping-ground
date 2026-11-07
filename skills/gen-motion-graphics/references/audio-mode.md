# AUDIO MODE

Turn the narration text into speech on this machine, in the voice and at the speeds the user picks. The text must never reach a third-party service (see "Privacy" in SKILL.md). So every command that runs a model on the text or the audio (speech, samples, the phoneme check and the speech check) runs through `scripts/offline.sh`. `trim_silence.py` in step 9 runs without it, because it only measures the audio and has no network code.

## 1. Input

- The narration is `sources/script/narration.txt` from SCRIPT MODE, or a text file the user gives. Copy a user file to `sources/script/narration.txt` and keep their original untouched. Also copy `display.json` or `lexicon.json` if they have them.
- Read it before speaking it. If it contains things a voice should not read (Markdown headings, bullets, stage directions, timestamps, URLs), point them out and offer a cleaned copy. Do not change it silently.

## 2. Engine

| Narration | Engine | Default voice |
|---|---|---|
| Korean (Hangul is most of the letters) | ask: `tts_qwen.py`, Qwen3-TTS 1.7B CustomVoice, or `tts_voxcpm.py`, VoxCPM2 | Qwen3-TTS: `Sohee` (the native Korean speaker). VoxCPM2: the `female` design |
| English | `tts_kokoro.py`, Kokoro-82M v1.0 | `af_heart` |
| Spanish, French, Hindi, Italian, Japanese, Brazilian Portuguese, Mandarin | Kokoro, with that language's voices (`ef_dora`, `ff_siwis`, `hf_alpha`, `if_sara`, `jf_alpha`, `pf_dora`, `zf_xiaoxiao`, ...) | the first in the list |
| German, Russian | Qwen3-TTS | ask, there is no native preset speaker |

For Korean, ask for the engine before anything else in this mode, unless the user already named one. Call `AskUserQuestion` with one question, "Which engine should speak the Korean narration?":

1. "Qwen3-TTS (Recommended)": preset native Korean speaker Sohee, with a choice of style. The user rated Sohee best in a blind test on 2026-11-07 (neutral 5 of 5, cheerful 4 of 5). Model about 4.2 GB.
2. "VoxCPM2": no preset speakers. The voice is made from a description, or cloned from a clip the user gives. 48 kHz. The user rated it second (4 of 5 for both). Model about 5 GB. Speaks about 10 % slower than Qwen3-TTS.

Do not offer other engines for Korean. VibeVoice, Supertonic 3, Chatterbox, OmniVoice and Ming-3.0 were rated lower in the same test, and OmniVoice's weights are non-commercial.

For other languages, tell the user which engine and voice set you will use, and why.

## 3. First run: packages and models

Generation runs offline, so everything must be on disk first. Check:

- Kokoro: `~/.cache/kokoro-onnx/kokoro-v1.0.onnx` (326 MB) and `voices-v1.0.bin` (28 MB).
- Qwen3-TTS: the model in the Hugging Face cache, `~/.cache/huggingface/hub/models--Qwen--Qwen3-TTS-12Hz-1.7B-CustomVoice` (4.2 GB). Only the 1.7B model can follow a speaking style, and it speaks in a bright, cheerful style by default. `Qwen3-TTS-12Hz-0.6B-CustomVoice` (2.5 GB) is the smaller fallback (pass `--model` with it). It cannot take a style, so its delivery stays neutral, and the user found that neutral tone "a bit curt and gruff". When only the 0.6B model is available, say so before generating and offer the 1.7B download.
- VoxCPM2: on Apple Silicon `~/.cache/huggingface/hub/models--mlx-community--VoxCPM2-bf16` (5 GB, run with mlx-audio), on other systems `models--openbmb--VoxCPM2` (5 GB, run with the `voxcpm` package and PyTorch).

Check only the engine that will speak. If something is missing, tell the user what will be downloaded (name, source, size, where it goes) and wait for their agreement. Then run the setup without `offline.sh`. It needs the network, never touches the text, and also installs the script's Python packages:

```sh
uv run --script <skill>/scripts/tts_kokoro.py --setup      # verifies SHA-256 against the GitHub release
uv run --script <skill>/scripts/tts_qwen.py --setup         # add --model ... for the 0.6B model
uv run --script <skill>/scripts/tts_voxcpm.py --setup
```

## 4. Check pronunciations before generating

The user caught a wrong "Scala" only after a whole video was made. Catch such words up front.

Known misreadings are fixed on every run, with no lexicon needed. Each script keeps them in a `PRONUNCIATIONS` table at its top:

- `tts_kokoro.py`, English voices: Scala is `skˈɑːlə` ("SKAH-luh"), not espeak's `skˈeɪlə` ("SKAY-luh"). This also covers "Scala 3", "Scala's" and "Scala Native".
- `tts_qwen.py` and `tts_voxcpm.py` (which uses the same table), Korean narration: Scala is spoken as 스칼라. Captions keep "Scala".

A `lexicon.json` entry for the same word overrides a built-in fix, and `null` switches it off (`{"Scala": null}`). When a word turns out to be wrong in general, not just in this video, tell the user it can go into the built-in table.

**Kokoro.** Make a list of words a voice may get wrong: product and project names, people's names, technical terms, acronyms, mixed-case words, and words with digits or dots. Show how espeak-ng will pronounce them:

```sh
<skill>/scripts/offline.sh uv run --script <skill>/scripts/tts_kokoro.py --phonemes "Scala, Kubernetes, nginx, Homebrew"
```

Compare each result with the real pronunciation. Put the wrong ones in `sources/script/lexicon.json`:

- `"ipa"`: espeak-style International Phonetic Alphabet (IPA), using the symbols and stress marks (ˈ ˌ) that `--phonemes` prints.
- `"say"`: a plain respelling.

Run `--phonemes` again with `--lexicon` to confirm. It prints "spoken as ..." for every word a built-in fix or the lexicon changes:

```json
{"nginx": {"say": "engine x"}, "Vite": {"say": "veet"}}
```

Ask the user only when you do not know how a name is said (a person's name, a brand, a made-up word). For an internal name, look up only an ordinary or public word inside it, alone ("atlas" from `atlas-billing-us-2`), never the whole name (see "Privacy" in SKILL.md). When you are not sure the word is public, ask the user whether you may look it up. If they say no, ask them how it is said.

**Qwen3-TTS and VoxCPM2** have no phoneme view. For names they may misread, add `"say"` respellings, often in Hangul (`{"Git": {"say": "깃"}}`). Writing English names in Hangul also helps the model with mixed Korean and English text. The speech check in step 8 shows whether it worked, and the user should still listen for them. In a test, VoxCPM2 read "GitHub" as "그탑", and `{"GitHub": {"say": "깃허브"}}` fixed it.

## 5. Ask for the voice and the speeds

Skip whatever the user already specified. Otherwise call `AskUserQuestion` once with two questions.

**Voice (Kokoro):**

1. "af_heart (Recommended)": warm American female, Kokoro's best-rated voice.
2. "af_bella": brighter and livelier American female, rated second best. The user chose it once for a more cheerful tone.
3. "am_michael": American male. Kokoro's male voices are rated lower than af_heart.
4. "No idea, give me samples": short samples of several voices reading lines from the script.

As "Other" the user can type any voice name (`--list-voices` lists all 54).

**Voice (Qwen3-TTS, Korean):**

1. "Sohee, cheerful (Recommended)": the native Korean female voice in a bright, friendly style, the default of the 1.7B model. For Korean the style instruction is written in Korean, which the user picked over the same style written in English.
2. "Sohee, warm presenter": a little calmer and more confident, like a friendly tech presenter (`--instruct warm`).
3. "Sohee, neutral": no style (`--instruct neutral`).
4. "No idea, give me samples": the same sentences in each style.

As "Other" the user can describe a style in their own words. Pass the description with `--instruct`. For Korean narration, keep it in Korean: Qwen documents English and Chinese instructions, but the user preferred the Korean-written cheerful style.

Style changes only the tone of the voice. Never change the user's wording to sound friendlier (for example 합니다체 to 해요체), because the user wants their own words with a cheerful tone. With the 0.6B model, the style choice has no effect.

**Voice (VoxCPM2, Korean):**

1. "Designed female (Recommended)": "a young Korean woman with a bright, warm and friendly voice, like a cheerful tech YouTuber". The user rated this voice 4 of 5.
2. "Designed male": "a Korean man in his thirties with a warm, calm and confident voice, like a friendly tech presenter". Not rated yet.
3. "Clone a voice": the user gives a clip of 5 to 15 s of clean speech and, if possible, its exact transcript. Clone only a voice the user has the right to use, such as their own. A Qwen3-TTS Sohee take also works as the clip (the clone of it was rated 4 of 5).
4. "No idea, give me samples": the two designs, plus a clone when the user has a clip.

As "Other" the user can describe a voice in their own words (gender, age, tone, pace). Pass it with `--design`. Write the description in English, as in the rated design. A designed voice changes with the seed. If the user does not like it, offer another seed (`--seed`) before another description. The style of a cloned voice can be changed with `--style` ("cheerful, slightly faster").

**Speeds** (`multiSelect: true`, so the user can pick several):

1. "1x (Default)"
2. "1.18x"
3. "1.30x"

Speeds work like playback speeds: the 1.18x file is 1.18 times shorter than the 1x file, pauses included. Put the estimated narration length into each description (the 1x estimate from the rates in `script-mode.md` with the pauses kept, divided by the speed). As "Other" the user can type a comma-separated list such as `1, 1.3, 1.5` (0.5 to 2.0).

## 6. Samples

When the user asks for samples:

1. Pick two sentences from the script, preferably ones with the tricky names.
2. Make the samples at the first chosen speed into `sources/audio/samples/`.
3. Open the comparison page (`open` on macOS, `xdg-open` on Linux).

```sh
<skill>/scripts/offline.sh uv run --script <skill>/scripts/tts_kokoro.py --text sources/script/narration.txt \
    --samples af_heart,af_bella,af_nicole,af_sarah,am_michael,am_fenrir,am_puck,bf_emma,bm_george \
    --sample-text "..." --lexicon sources/script/lexicon.json --out-dir sources/audio/samples
<skill>/scripts/offline.sh uv run --script <skill>/scripts/tts_qwen.py --text sources/script/narration.txt \
    --samples Sohee --styles cheerful,warm,neutral --lexicon sources/script/lexicon.json --out-dir sources/audio/samples
<skill>/scripts/offline.sh uv run --script <skill>/scripts/tts_voxcpm.py --text sources/script/narration.txt \
    --samples female,male [--ref-audio sources/audio/voice.wav --ref-text sources/audio/voice.txt] \
    --lexicon sources/script/lexicon.json --out-dir sources/audio/samples
```

For Korean with Qwen3-TTS, compare styles of Sohee, the native speaker. Other speakers (`--samples Sohee,Vivian,Serena`) are worth a sample only when the user asks for a different voice. Copy a clip the user gives for cloning to `sources/audio/` (with its transcript as `voice.txt`) and keep their original untouched.

Then ask again with the three most fitting voices as options, plus "Other".

## 7. Generate

One file per speed, named `narration-<voice>-<speed>x.wav` (24 kHz mono), or `narration-voxcpm-<voice>-<speed>x.wav` for VoxCPM2 (48 kHz mono, `<voice>` is the design name or `clone`):

```sh
<skill>/scripts/offline.sh uv run --script <skill>/scripts/tts_kokoro.py --text sources/script/narration.txt \
    --voice af_heart --speeds 1,1.18 --lexicon sources/script/lexicon.json --out-dir sources/audio
<skill>/scripts/offline.sh uv run --script <skill>/scripts/tts_qwen.py --text sources/script/narration.txt \
    --speaker Sohee --speeds 1,1.18 --out-dir sources/audio
<skill>/scripts/offline.sh uv run --script <skill>/scripts/tts_voxcpm.py --text sources/script/narration.txt \
    --design female --speeds 1,1.18 --lexicon sources/script/lexicon.json --out-dir sources/audio
<skill>/scripts/offline.sh uv run --script <skill>/scripts/tts_voxcpm.py --text sources/script/narration.txt \
    --ref-audio sources/audio/voice.wav --ref-text sources/audio/voice.txt --speeds 1,1.18 --out-dir sources/audio
```

How the speeds are made:

- **Kokoro** speaks faster natively. Its own speed setting is not proportional, and its response jumps above 1.3, so the script calibrates the setting against the 1x take. If needed, it time-stretches the small remainder with the pitch kept: the rubberband R3 engine when `rubberband` is installed, otherwise ffmpeg `atempo`. The printed line says how each file was made.
- **Qwen3-TTS and VoxCPM2** have no speed setting, so their faster files are time-stretched the same way.

Every file is normalized to peak at -1 dBFS. Qwen3-TTS and VoxCPM2 generate the text in chunks of whole sentences, never across a paragraph, and even out their loudness. They print the chunks with their numbers (`--list-chunks` shows them without generating). A designed VoxCPM2 voice would change from chunk to chunk, so only chunk 1 is spoken from the description, and every later chunk clones chunk 1.

## 8. Check what was spoken

You cannot listen, but the local Whisper model can. Check every file:

```sh
<skill>/scripts/offline.sh uv run --script <skill>/scripts/make_timings.py sources/audio/<file>.wav --check \
    --script sources/script/narration.txt
```

It lists each place where the transcript differs from the script. Differences only in spelling are fine: digits for numbers, joined words, and names you respelled in the lexicon. A wrong, garbled or missing word is not:

- **Kokoro** is deterministic. Fix the word with a lexicon entry (check it with `--phonemes`), then regenerate.
- **Qwen3-TTS and VoxCPM2** sample randomly, so a word can be wrong in one take and right in the next. Redo only that chunk with another seed (`--chunk-seeds 2=13`), or respell the word in the lexicon (`{"셸": {"say": "쉘"}}`). Then check again. Lexicon entries match names with particles attached ("macOS와" is matched by "macOS"). With a designed VoxCPM2 voice, the seed of chunk 1 sets the voice for the whole narration. So for a wrong word in chunk 1, use the lexicon, or tell the user that another seed for chunk 1 also changes the voice.

## 9. Report

- Measure each file with `uv run --script <skill>/scripts/trim_silence.py <file> --dry-run`. It prints the length with the pauses kept, which is VIDEO MODE's default, and with them trimmed, which VIDEO MODE offers.
- Give a table: file, speed, length with the pauses kept, length with them trimmed, and the expected video length for each (about 7 s more).
- Say that you cannot listen to audio, and what the Whisper check found. Name the words to listen for (the lexicon fixes and any names), and ask the user to check the pace and tone.
- Fixes stay in AUDIO MODE:
  - a wrong word: lexicon entry, then regenerate
  - another voice, speed or engine (for Korean, Qwen3-TTS or VoxCPM2)
  - more energy: `af_bella`, or for Kokoro a copy of the text with a few periods turned into "!" (only with the user's agreement), or for Qwen 1.7B another `--instruct` style, or for a cloned VoxCPM2 voice `--style`
  - a different Qwen or VoxCPM2 take: `--seed`, or `--chunk-seeds` for one part (with a designed VoxCPM2 voice, `--seed` also gives another voice)
- Close with: "Listen to the files, then say ENTER VIDEO MODE (and tell me which file to use)." The question about which file is needed only when there are several.
