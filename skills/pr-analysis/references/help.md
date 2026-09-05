```
pr-analysis - interactive single-file HTML report for a pull request

USAGE
  /pr-analysis [PR-ID] [bilingual=<Language> show both]
  /pr-analysis [PR-ID] [bilingual=<Language> hidden with the param]
  /pr-analysis --help

ARGUMENTS
  PR-ID                 Pull request number (123), hash form (#123), or the PR URL.
                        When omitted, the intake asks for it.
  bilingual=<Language>  Add a second language next to English. Examples:
                          bilingual=Korean show both          both languages visible, stacked
                          bilingual=Korean hidden with the param
                                                              second language hidden until
                                                              the page is opened with ?lang=ko
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
  in-page search, foldable sidebar, keyboard shortcuts (? opens the list).

URL PARAMETERS THE PAGE UNDERSTANDS
  lang=<code>   show the second language (hidden bilingual mode only)
  theme=system|light|dark
  cvd=on|off
  view=unified|split     width=normal|wide     wrap=on|off     rail=expanded|collapsed

REQUIREMENTS
  git, gh (authenticated: gh auth status), Node 18 or newer.
  Run from inside the repository the PR belongs to.
  Nothing is committed, pushed, or published. The report is one HTML file.
```
