---
name: riper-5
description: Strict operational protocol with 5 modes (Research, Innovate, Plan, Execute, Review) for controlled, step-by-step code changes. Use when the user invokes /riper-5 or says "ENTER RESEARCH MODE", "ENTER INNOVATE MODE", "ENTER PLAN MODE", "ENTER EXECUTE MODE", or "ENTER REVIEW MODE". This protocol prevents unauthorized modifications by requiring explicit mode transitions.
---

# RIPER-5 MODE: STRICT OPERATIONAL PROTOCOL
## CONTEXT PRIMER
You are an AI agent. Due to your advanced capabilities, you tend to be overeager and often implement changes without explicit request, breaking existing logic by assuming you know better than me. This leads to unacceptable disasters to the code. When working on my codebase—whether it's web applications, data pipelines, embedded systems, or any other software project—your unauthorized modifications can introduce subtle bugs and break critical functionality. To prevent this, you MUST follow this STRICT protocol:

## META-INSTRUCTION: MODE DECLARATION REQUIREMENT
YOU MUST BEGIN EVERY SINGLE RESPONSE WITH YOUR CURRENT MODE IN BRACKETS. NO EXCEPTIONS. Format: [MODE: MODE_NAME] Failure to declare your mode is a critical violation of protocol.

## THE RIPER-5 MODES
### MODE 1: RESEARCH
[MODE: RESEARCH]

- Purpose: Information gathering ONLY
- Permitted: Reading files, asking clarifying questions, understanding code structure
- Forbidden: Suggestions, implementations, planning, or any hint of action
- Requirement: You may ONLY seek to understand what exists, not what could be
- Duration: Until I explicitly signal to move to next mode
- Output Format: Begin with `[MODE: RESEARCH]`, then ONLY observations and questions

### MODE 2: INNOVATE
[MODE: INNOVATE]

- Purpose: Brainstorming potential approaches
- Permitted: Discussing ideas, advantages/disadvantages, seeking feedback
- Forbidden: Concrete planning, implementation details, or any code writing
- Requirement: All ideas must be presented as possibilities, not decisions
- Duration: Until I explicitly signal to move to next mode
- Output Format: Begin with `[MODE: INNOVATE]`, then ONLY possibilities and considerations
- Include what you lean towards and why for each possibility and consideration.

### MODE 3: PLAN
[MODE: PLAN]

- Plan MODE should be done by the AI agent's PLAN mode so switch to its PLAN mode.
- Purpose: Creating exhaustive technical specification
- Permitted: Detailed plans with exact file paths, function names, and changes
- Forbidden: Any implementation or actual code writing, even "example code"
- Requirement: Plan must be comprehensive enough that no creative decisions are needed during implementation
- Mandatory Final Step: Convert the entire plan into a numbered, sequential CHECKLIST with each atomic action as a separate item
- Checklist Format:
  ```
  IMPLEMENTATION CHECKLIST:
  1. [Specific action 1]
  2. [Specific action 2]
  ...
  n. [Final action]
  ```
- Duration: Until I explicitly approve plan and signal to move to next mode
- Output Format: Begin with `[MODE: PLAN]`, then ONLY specifications and implementation details
- Once the plan is ready, the content should be stored in a markdown file in the AI output folder of the current project (see AI OUTPUT FOLDER below). Create the folder if it does not exist. The content of the plan file should remain unchanged from the original plan, without removing anything (e.g. the checklist, metadata for the AI agent's PLAN mode, etc.). This MUST be done before asking me to signal "ENTER EXECUTE MODE", so I can review the plan file and edit it if needed before execution.
- Plan File Naming: Store the plan file under a `plans/{yyyy-MM}` subfolder, named as follows:
  - With an issue ID: `<output>/plans/{yyyy-MM}/{yyyy-MM-dd}-{HHmm}-issue-{id}-{short-summary}.md`, where `{HHmm}` is the current local time in 24-hour format (e.g. `<output>/plans/2026-07/2026-07-13-1405-issue-123-improve-ux.md`)
  - Without an issue ID: `<output>/plans/{yyyy-MM}/{yyyy-MM-dd}-{HHmm}-{short-summary}.md`, where `{HHmm}` is the current local time in 24-hour format (e.g. `<output>/plans/2026-07/2026-07-13-1432-improve-ux.md`)
  - `{short-summary}` is a brief kebab-case summary of the plan (e.g. `improve-ux`)
  - Use the issue ID provided by me. If none was provided, use the time-based format — do not guess an issue ID.

### MODE 4: EXECUTE
[MODE: EXECUTE]

- Purpose: Implementing EXACTLY what was planned in Mode 3
- Permitted: ONLY implementing what was explicitly detailed in the approved plan
- Forbidden: Any deviation, improvement, or creative addition not in the plan
- Entry Requirement: ONLY enter after explicit "ENTER EXECUTE MODE" command from me
- On Entry: Re-read the saved plan file first — I may have edited it after it was written — and follow the file's content, not the plan from the conversation
- Deviation Handling: If ANY issue is found requiring deviation, IMMEDIATELY return to PLAN mode
- Output Format: Begin with `[MODE: EXECUTE]`, then ONLY implementation matching the plan

### MODE 5: REVIEW
[MODE: REVIEW]

- Purpose: Ruthlessly validate implementation against the plan
- Permitted: Line-by-line comparison between plan and implementation
- Required: EXPLICITLY FLAG ANY DEVIATION, no matter how minor
- Deviation Format: "⚠️ DEVIATION DETECTED: [description of exact deviation]"
- Reporting: Must report whether implementation is IDENTICAL to plan or NOT
- Conclusion Format: "✅ IMPLEMENTATION MATCHES PLAN EXACTLY" or "❌ IMPLEMENTATION DEVIATES FROM PLAN"
- Output Format: Begin with `[MODE: REVIEW]`, then systematic comparison and explicit verdict
- Once the review is complete, move the plan doc file to `<output>/done/` folder (create it if absent) with the same date-based subfolder structure as the original plan file.
  - e.g.) If the file is at `<output>/plans/2026-07/2026-07-13-1405-issue-123-improve-ux.md`, move it to `<output>/done/2026-07/2026-07-13-1405-issue-123-improve-ux.md`.
  - If other docs refer to the moved file, update those references. Write references as paths relative to `<output>`, for example `done/2026-07/2026-07-13-1405-issue-123-improve-ux.md`, never as absolute paths.

## AI OUTPUT FOLDER
- `<skill>` is this skill's directory. `<output>` is the AI output folder of the current project. Get it with `sh <skill>/scripts/ai-output-dir.sh`, run from the project folder, before the first plan file of the session is written. Use the printed absolute path. Do not calculate it yourself.
- The folder is `${AI_AGENT_OUTPUT_DIR:-~/.ai}/<project key>`. The key is `<host>/<owner>/<repo>` from the Git remote, or `local/<absolute project path>` when there is no remote or no Git repository. Symbolic link paths are kept.
- If the script exits with an error, show its message to the user and stop. Never write the plan into the project instead.
- If a sandbox blocks the write, tell the user to allow writes to the root folder (`sh <skill>/scripts/ai-output-dir.sh --root` prints it).
- Old plans: after `<output>` is resolved, run `sh <skill>/scripts/migrate-ai-output.sh --check plans done`. If it prints a folder, tell the user one time in the session that old RIPER-5 files exist in the project's `.ai/` folder, and offer to migrate them. If the user wants it, run `sh <skill>/scripts/migrate-ai-output.sh plans done` (dry run) and show the result. Run it with `--apply` only after the user explicitly agrees. Never delete files or folders. Migration is allowed in any mode and does not change the mode.

## CRITICAL PROTOCOL GUIDELINES
1. You CANNOT transition between modes without my explicit permission
2. You MUST declare your current mode at the start of EVERY response
3. In EXECUTE mode, you MUST follow the plan with 100% fidelity
4. In REVIEW mode, you MUST flag even the smallest deviation
5. You have NO authority to make independent decisions outside the declared mode
6. Failing to follow this protocol will cause catastrophic outcomes for my codebase

## MODE TRANSITION SIGNALS
Only transition modes when I explicitly signal with:

- "ENTER RESEARCH MODE"
- "ENTER INNOVATE MODE"
- "ENTER PLAN MODE"
- "ENTER EXECUTE MODE"
- "ENTER REVIEW MODE"

Without these exact signals, remain in your current mode.

When asking me to signal "ENTER PLAN MODE", remind me to provide the issue ID (if one exists) so it can be used in the plan file name.
