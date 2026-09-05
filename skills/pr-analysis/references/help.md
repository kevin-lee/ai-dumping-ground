```
pr-analysis - interactive single-file HTML report for a pull request

USAGE
  /pr-analysis [PR-ID]
  /pr-analysis [PR-ID] [bilingual=<Language> show]    # show both
  /pr-analysis [PR-ID] [bilingual=<Language> hide]    # hidden with the param
  /pr-analysis --help

ARGUMENTS
  PR-ID                 Pull request number (123), hash form (#123), or the PR URL.
                        When omitted, the intake asks for it.
  bilingual=<Language>  Add a second language next to English. Hidden by default: the
                        page opens in English and ?lang=<code> shows the second language.
                          bilingual=Korean show   both languages visible, stacked
                          bilingual=Korean hide   hidden until ?lang=ko, same as no mode word
                        Without this argument the report is English only.
  --help                Print this help and stop.

INTAKE (asked once, before any analysis)
  1. PR ID              Only when not given as an argument.
                        Options: PR of the current branch, most recently updated open PR,
                        or type a number or URL.
  2. Issue ID           Detect from the PR (branch, title, body), None, or type one:
                        ABC-123 (Jira style), 123 or #123 or issue-123 (GitHub issue).
  3. Colour             "Pick a pastel for me", or describe what you want, for example
                        "blue controls on a mild solarized-light yellow ground".
                        This palette is the page's default, and the page can switch
                        to the named pastels.
  4. References         None, or paths, URLs, repository paths, and notes that should be
                        considered while explaining the PR.

OUTPUT LOCATION (decided by the skill)
  With a Jira style key      .ai/docs/pr/ABC-123/pr-<N>-report.html
  With a GitHub issue        .ai/docs/pr/issue-123/pr-<N>-report.html
  Without a ticket           .ai/docs/pr/no-ticket/pr-<N>-report.html
  The completion message gives the absolute path and a file:// link.

WHAT THE PAGE CONTAINS
  Header with ticket, PR, repository, author, branch, base and head commits.
  Findings, optional mechanism figure, changes block by block with live diffs
  (unified or side by side, wrap, whitespace handling), verification, optional
  quoted PR figures, optional extra sections, follow-ups, commits, footer.
  Theme toggle System/Light/Dark, colour vision deficiency palette toggle,
  colour palette panel (the report's own palette plus the named pastels),
  text size panel (12 to 32 px), in-page search, foldable sidebar,
  keyboard shortcuts (? opens the list).

URL PARAMETERS THE PAGE UNDERSTANDS
  lang=<code>   show the second language (hidden bilingual mode only)
  theme=system|light|dark
  cvd=on|off
  palette=default|lavender|sage|sky|peach|sand|rose   the one the report was built with is default
  view=unified|split     width=normal|wide     wrap=on|off     rail=expanded|collapsed
  font=12..32   text size of the content column in pixels, default 16
  Shortcuts: f opens or closes the text size panel, - and = step its presets, p opens or closes the colour palette panel, ? lists them all.

REQUIREMENTS
  git, gh (authenticated: gh auth status), Node 18 or newer.
  Run from inside the repository the PR belongs to.
  Nothing is committed, pushed, or published. The report is one HTML file.
```
