# Writing rules for report text

These rules apply to every visible string you author in fragments and in the manifest. They exist because the page is shared with people who did not see the PR, often in a hurry, sometimes through a screen reader, and sometimes in a second language.

## Voice

- Write from the reader's side. Say what a change does to the system and why, not how the diff looks.
- Active voice. One idea per sentence. No praise, no filler, no "simply", no "just".
- Prefer concrete nouns: the file name, the function, the flag, the command.
- Never write `;` in prose. Split the sentence instead. Use `-` where you would reach for an em-dash. Quoted material (commit messages, PR body) stays verbatim even when it breaks these rules.
- Do not insert line breaks to fit a column width. Break only where a paragraph or list item ends.

## Acronyms

Expand every acronym or short form the first time it appears anywhere in the document, then use the short form: "Functional Programming (FP)", "Continuous Integration (CI)", "Amazon Web Services (AWS)". The check script lists all-caps tokens it could not find an expansion for. Common file extensions and language names (HTML, CSS, JSON, SQL) still get one expansion if they appear in prose.

## Verified versus quoted

Readers must always be able to tell what you confirmed from what you are repeating.

- Verified locally: state it plainly, and show the command in a `<pre>` in the verification section.
- Taken from the PR description or comments: say "from the PR" or "the PR reports", and put the source text in the quoted section with a `blockquote cite`.
- Not checked: say "not run here" and why.
- Never present a number from the PR as if you measured it.

## Bilingual text

- English first, then the second language. English carries the class `en`, the second language carries `l2`. Both are plain UTF-8, never `\uXXXX` escapes.
- Every `en` element has exactly one `l2` sibling with the same meaning, and the check script counts them. Code, commands, file names, and verbatim quotes are not translated and carry neither class.
- For headings and chips use nested spans: `<h3><span class="en">…</span><span class="l2">…</span></h3>`. For paragraphs and lists use sibling elements: `<p class="en">…</p><p class="l2">…</p>`.
- Keep numbers, identifiers, and links identical in both languages.

Language name to code table (used for the `bilingual=` argument):

| Name | Code | Name | Code | Name | Code |
|---|---|---|---|---|---|
| Korean | ko | Japanese | ja | Chinese | zh |
| Spanish | es | French | fr | German | de |
| Portuguese | pt | Italian | it | Vietnamese | vi |
| Thai | th | Indonesian | id | Hindi | hi |
| Arabic | ar | Russian | ru | Turkish | tr |
| Polish | pl | Dutch | nl | Swedish | sv |

Unknown names: use the lowercased name as the code and say so in the completion message.

## People and sensitive data

- Refer to people by GitHub handle, linked to their profile. Never write an email address. Full names only when they appear in the PR title itself.
- Before embedding a changed file, scan it for anything that looks like a credential: tokens, keys, passwords, connection strings, private keys, cloud account identifiers. Declare a `redact` rule in the manifest that replaces the value with `[REDACTED]` and keeps the key name so the diff still makes sense, then add a verification row saying what was redacted. The build applies the rule to the embedded text and the check applies the same rule before proving the text matches git. If the whole file is a credentials file, do not embed it: describe the change in the block notes and give the block a `range` of `[0, 0]` on both sides.
- Do not copy internal hostnames, customer data, or personal data from the PR body into the page. Summarize instead.

## Links

- The PR number, every commit hash, the ticket key, the author, and every changed file name are links. The build does this for the generated parts. In fragments, link file names to `<repoUrl>/blob/<headSha>/<path>` and commits to `<repoUrl>/commit/<sha>` using the values from `meta.json`.
- Link text says what it points to. Never "here" or "this link".
