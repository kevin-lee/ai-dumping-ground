centralize-ai-output: keep AI agent outputs out of the project, in one central folder

USAGE
  /centralize-ai-output [status | migrate | link | install-rule | help]

STEPS
  status         Show the output folder, what is left in .ai/, the link state, and the
                 rule state of each agent. Then offer the steps that are not done yet.
  migrate        Move everything in the project's .ai/ into the output folder.
  link           Replace the empty .ai/ with a symbolic link to the output folder.
  install-rule   Add or update a rule in the global instruction files of Claude, Codex
                 and Gemini, so agents write their outputs into the output folder unless
                 you name another location. An outdated rule is shown with a diff.
                 For Cursor, it prints the text to paste.
  Each step starts with a dry run, and changes something only after you agree.

OUTPUT FOLDER
  ${AI_AGENT_OUTPUT_DIR:-~/.ai}/<project>
  <project> is <host>/<owner>/<repo> from the Git remote, or local/<name>-<hash>
  (folder name and a hash of the path) when there is no remote or no Git repository.
  Clones and worktrees of one repository share one folder. Symbolic links in the
  project path are kept.
  AI_AGENT_OUTPUT_DIR can be an absolute path, ~, or a path that starts with ~/,
  $HOME/ or ${HOME}/.

RULE CHECK
  When an installed rule is outdated or has broken markers, ai-output-dir.sh of this
  skill (the script that the rule runs) tells the agent to tell you.
  AI_AGENT_OUTPUT_RULE_CHECK=0 turns it off.

GITIGNORE
  A .ai/ pattern matches only a folder. After the link step, use .ai (no slash),
  so Git also ignores the symbolic link.

SCRIPTS (in the skill's scripts/ folder, run from the project folder)
  ai-output-dir.sh [--print-only | --root]
      Print the output folder (and create it), or only the root.
  migrate-ai-output.sh [--check | --apply] [--from <dir>] (<item>... | --all)
      Move old outputs. A dry run without an option. Never deletes, never overwrites.
  link-ai-folder.sh [--apply]
      Link .ai to the output folder. Removes only .DS_Store files and empty folders.
  install-rule.sh [--apply | --check] [--target claude|codex|gemini]... | --print
      Install the rule. Backs up each changed file as <file>.bak.<YYYYmmdd-HHMMSS>.
      --check lists only the outdated rules, and exits 3 when there is one.
