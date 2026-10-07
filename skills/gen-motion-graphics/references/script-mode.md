# SCRIPT MODE

Write `sources/script/narration.txt`: the exact words a TTS voice will speak over the video. Nothing else goes in it. A good script fits the target duration, sounds natural read aloud by a machine voice, and gives VIDEO MODE concrete things to show.

## 1. Inputs

- **Topic or prompt.** What the video is about and what it is for (channel intro, product intro, explainer, announcement).
- **Target duration.** Required, because it sets the length. If the prompt has none, call `AskUserQuestion` with "How long should the video be?" and the options "30 seconds", "60 seconds (Recommended)", "90 seconds" and "2 minutes". The user can type another length as Other. A range such as "60 to 90 seconds" is fine. Aim for the middle of it.
- **Language.** Write in the language of the request unless the user asks for another. Korean narration is spoken by Qwen3-TTS in AUDIO MODE. Everything below applies, and Korean notes are at the end.
- **Audience and tone.** Infer them (a YouTube intro is upbeat, confident and concrete). Ask only when the answer would change the script substantially.
- **Facts.** When the video is about a project in the current repository, read its README, docs and the code behind each claim. Read any files or URLs the user names. Every statement must be true. Do not invent features, numbers, users or quotes. If something is unclear, leave it out or ask.

## 2. Length budget

The finished video is about 2 s of music lead-in, then the narration, then an outro of 4 s plus up to one bar, ending on a bar line of the music. VIDEO MODE keeps the narration's pauses unless the user asks to trim them. So for a target of T seconds, plan about **T − 7 seconds of narration**, pauses included (for T ≥ 30).

English words per second of narration with the pauses kept, measured with Kokoro `af_heart` on a technical script (216 words with many names and spelled acronyms) and a plain one (71 words). Speeds work like playback speeds, so 1.18x is 1.18 times shorter:

| Speed chosen in AUDIO MODE | Technical | Plain language |
|---|---|---|
| 1.0x | 2.6 | 3.0 |
| 1.18x | 3.1 | 3.5 |
| 1.30x | 3.4 | 3.9 |

Words ≈ (T − 7) × rate. Plan for 1.0x unless the user mentions a faster pace. Examples at 1.0x for a technical script: 30 s needs about 60 words, 60 s about 140 words, 90 s about 215 words. `af_bella` reads about 3 % slower than `af_heart`. Trimming the pauses in VIDEO MODE makes English narration about 8 % shorter, if the user chooses it there.

Korean (Qwen3-TTS 1.7B, `Sohee` in the default cheerful style, measured): about 5.3 Hangul syllables per second with the pauses kept, so plan (T − 7) × 5.3 Hangul characters, not counting spaces, punctuation and Latin letters. Each English word inside the Korean text adds roughly 0.4 s. Trimming the pauses makes it about 10 % shorter. The 0.6B model pauses much longer: the same Korean text ran 39 s with it against 28 s with the 1.7B model.

Stay within about 5 % of the budget. The user can adjust the speed in AUDIO MODE, so being slightly long is better than padding.

## 3. Write for the ear

- **Plain text only.** No Markdown, headings, bullets, emojis, brackets, or quotation marks used for emphasis. Write one paragraph per idea. Blank lines between paragraphs are only for the reader. VIDEO MODE removes pauses, so each paragraph must open with a clear subject and still make sense when read straight after the previous one.
- **Only spoken words.** No stage directions ("[music]", "(pause)", "Scene 2:", "Narrator:"), no notes about what appears on screen, no timestamps.
- **Sentences:** mostly 8 to 18 words, active voice, concrete nouns and verbs. Vary the length for rhythm. Use a short punchy line now and then.
- **Shape:** a hook in the first sentence (the problem, a surprising fact, or a clear promise), then the subject, then three to five concrete points, then what makes it different, then a takeaway or call to action (where to get it, what to try). A 30-second script has room for the hook, two points and the close.
- **Make it visual.** Named things, steps, before and after, comparisons, and small lists of three to six items give VIDEO MODE material to animate. Abstract claims give it nothing.
- **No filler or hype:** "revolutionary", "seamless", "game-changing", "in today's fast-paced world", "whether you're a beginner or an expert".

## 4. Spoken forms

TTS reads text literally, so write what should be heard:

| Written | Write in the narration |
|---|---|
| `skills.sh`, `config.yaml` | skills dot S H, config dot yaml |
| Node.js, C++, C# | Node JS, C plus plus, C sharp |
| `&`, `%`, `/`, `+` | and, percent, reword or "slash", plus |
| v3.2, 2026, 1.5M | version three point two, twenty twenty-six, one and a half million |
| URLs, emails, handles | leave them out unless short and you know how they are said. They belong on screen |
| Acronyms spelled as letters | keep common ones (AI, API, CLI, URL, JSON). They are usually fine, and AUDIO MODE checks |

Keep real product and project names spelled correctly in the narration even if you suspect the voice will get them wrong ("Scala", "Kubernetes", "nginx"). AUDIO MODE checks pronunciations and fixes them with a lexicon, without touching the text. Respell in the text only when there is no other way.

Whenever a spoken form differs from how the thing is written, record it in `sources/script/display.json`, so VIDEO MODE's captions show the written form:

```json
[
  {"spoken": "skills dot S H", "written": "skills.sh"},
  {"spoken": "Node JS", "written": "Node.js"}
]
```

Each `spoken` value must match the narration word for word (case and punctuation do not matter). Skip the file when there is nothing to record.

## 5. Example

A 30-second intro for a fictional tool (71 words at 3.0 words per second is about 24 s of narration with the pauses kept, plus the lead-in and outro):

```
Every team has a folder of shell scripts that nobody else can find.

Meet Toolbox, one command that turns those scripts into a searchable menu for the whole team.

Point it at a Git repository, and Toolbox reads each script's comments to build the menu. Type a few letters, pick a script, and it runs with the right arguments every time.

It works on macOS and Linux and installs with Homebrew.
```

## 6. Save and report

1. Decide the video folder and slug (see "Where files go" in SKILL.md). Write `sources/script/narration.txt` (UTF-8, ending with a newline) and `display.json` if needed.
2. Show the full script in your reply. Users want to read it, not open a file.
3. Report the word count (Korean: characters). Give the estimated narration length at 1.0x, 1.18x and 1.30x with the pauses kept, and the resulting video length (narration + about 7 s). Mention that trimming the pauses in VIDEO MODE would make it about 8 % shorter (Korean about 10 %).
4. List the spoken-form choices you made and the names whose pronunciation AUDIO MODE should check.
5. If the script runs long, say which sentence is the easiest cut. If it runs short, say what could be added.
6. Close with: "Edit the script if you like, then say ENTER AUDIO MODE."

Revisions stay in SCRIPT MODE: rewrite the same file and report again.

## Korean notes

- Use 합니다체 by default: 소개합니다, 바꿔 줍니다, 설치할 수 있습니다. The user prefers it to 해요체. A softer ending in the hook is fine (하나쯤 있죠). Switch to 해요체 only when the user asks for it.
- A cheerful sound comes from the voice, not from the wording. AUDIO MODE speaks with a bright, cheerful style by default. Once the user found a take "a bit curt and gruff", and they meant the tone of the voice, not the word endings. So never rewrite the endings to sound friendlier. To sound livelier, change the voice style in AUDIO MODE.
- Write numbers the way they should be read when it matters (삼 년, 세 개, 이천이십육 년).
- English product names may stay in Latin letters. Qwen3-TTS reads mixed text, but check them in AUDIO MODE. For a name whose reading is uncertain, consider writing it in Hangul (스칼라) and adding a `display.json` entry back to the Latin spelling.
- Particles attach to names (Scala로, AI Skills는). That is fine for speech, and the captions keep them.
