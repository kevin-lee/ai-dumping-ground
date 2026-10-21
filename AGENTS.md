# AGENTS

Instructions for AI agents that change this repository.

## AI output folder

Before you change one of these files, read [docs/ai-output-folder-maintenance.md](docs/ai-output-folder-maintenance.md). It records the issues, the invariants, the decisions and the rejected options. A change made without them can break them again.

- `ai-output-dir.sh`, `ai-output-choices.sh` and `migrate-ai-output.sh` in `skills/riper-5/scripts/`, `skills/pr-analysis/scripts/`, `skills/gen-motion-graphics/scripts/` and `skills/centralize-ai-output/scripts/`
- `video-output-choices.sh` in `skills/gen-motion-graphics/scripts/`
- all files in `skills/centralize-ai-output/`
- the parts of `skills/riper-5/SKILL.md`, `skills/pr-analysis/SKILL.md` and `skills/gen-motion-graphics/SKILL.md` that choose the output folder
- `scripts/skills/test-ai-output-scripts.sh` and `scripts/skills/test-ai-output-scripts-linux.sh`

Update the document in the same change when your change adds, renames or removes a script, changes an invariant or a decision, or removes a limit. When a new file uses the output folder, add it to the list above.

## Skill folders

Do not put `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` or other notes for maintainers in `skills/<name>/`. `aiskills` installs the whole skill folder, so the file goes to every user, and the paths in it do not exist there. Put them at the repository root or in `docs/`.
