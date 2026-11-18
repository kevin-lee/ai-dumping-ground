# Clear Writing

Write so that a reader gets the point on a quick skim. Every rule below serves that goal. If a rule makes a sentence harder to read, break the rule.

These rules add to `Simple-Global-Rules.md`. If the two files conflict, `Simple-Global-Rules.md` wins.

Sources: Joseph M. Williams and Joseph Bizup, *Style: The Basics of Clarity and Grace*, and Zonder Labs, "Why is AI Slop so Frustrating to Read?" (https://zonderlabs.com/slop).

## 1. Make the doer the subject and the action the verb

Every sentence is a small story: someone or something does something. Put that "someone" in the subject and that "something" in the verb.

- Before you write a sentence, ask "who does what?" Then write it in that order.
- Do not hide actions in nouns. Words like `arrival`, `request`, `failure`, `validation`, `implementation`, `investigation`, `availability` often hide a verb. Turn them back into verbs.
- Use the active voice. Use the passive voice only when the doer is unknown or does not matter.
- You are a character too. Write "I ran the tests", not "The tests were executed".
- Code is a character too. Write "`AuthHandler` checks the token", not "Token validation is performed".

| Unclear | Clear |
|---|---|
| A request for grapes was made upon the duck's arrival at the lemonade stand. | A duck walked up to a lemonade stand and asked, "Got any grapes?" |
| A failure was observed in the build. | The build failed. |
| Validation of the input is performed prior to insertion of the record. | The service validates the input before it inserts the record. |
| Investigation revealed that the cause was a missing import. | The build fails because `Foo.scala` does not import `cats.syntax.all.*`. |

## 2. Use plain, specific words

Use the words a colleague would say out loud to describe the same thing.

- Name things the way people normally name them. A lemonade stand is not a "beverage retailer".
- Do not stack nouns. Two nouns in a row is usually fine. Three or more is a warning. Rewrite "user-session entry boundary" as "when a user session starts".
- Do not invent labels. If you must coin a term, define it the first time. If the code already has a name for the thing (a function, a type, a file path), use that name in backticks.
- Make every `it`, `this`, `that` and `they` point to one obvious thing. If a reader could ask "this what?", name the thing.
- Use numbers and names instead of vague amounts. Write "3 of 12 tests fail", not "some tests fail".
- Use the same word for the same thing every time. Do not switch to a synonym for variety.
- Avoid vague words that sound important but say little: `robust`, `seamless`, `leverage`, `surface` (as a verb), `land` (as a verb), `load-bearing`, `holistic`, `streamline`, `unlock`, `key`, `crucial`, `comprehensive`. Say the specific thing instead.

| Unclear | Clear |
|---|---|
| The duck made a grape availability request as he arrived at the beverage retailer. | A duck walked up to a lemonade stand and asked, "Got any grapes?" |
| The database readiness check sits at the user-session entry boundary, before the authentication handler runs. | When a user session starts, the code checks that the database is ready. Then it authenticates the user. |
| Fixed the config-resolution fallback-path issue. | Fixed the bug where `loadConfig` ignored `~/.app.conf` when `APP_CONF` was not set. |

## 3. Put the point first and cut empty sentences

A reader should not have to hunt for the point.

- Start with the most important fact: the answer, the result, the decision, or the action the reader must take. Then give the reasons. Then give the details.
- In a sentence, start with what the reader already knows and end with what is new.
- Write one idea per sentence. If a sentence has "so", "which" and "because" in it, split it.
- Delete sentences that add nothing:
  - restating the question ("You asked about X.")
  - announcing what you will do ("Let me take a look.")
  - praise or filler ("Great question.", "It is worth noting that")
  - a closing summary that repeats the body
  - offers at the end ("Let me know if you need anything else.")
- Hedge once, only where you are really unsure, and say what you are unsure about. Do not stack hedges ("it might potentially be possible that").
- Do not add emphasis words (`very`, `really`, `significantly`, `importantly`). Do not bold whole sentences. If everything is emphasized, nothing is.

| Unclear | Clear |
|---|---|
| Nothing else depends on anything but the result, so I'll report as soon as the poll returns. | I'll report the result when the poll finishes. Nothing else is pending. |
| I've completed a thorough analysis of the codebase and identified several areas of interest. The main issue appears to be related to the way configuration is loaded. | The app ignores `~/.app.conf` because `loadConfig` reads only `APP_CONF`. |

## 4. Report work honestly and plainly

- Start a status report with the outcome: done, failed, or blocked.
- Say what you did in the past tense, with the doer: "I changed `X`. I ran `sbt test`. 2 tests fail."
- Say what you did not do or did not check. Do not imply that you verified something you did not run.
- Quote exact error text when it is short. Do not paraphrase errors.

## 5. Use formatting only when the content has that shape

- Use a numbered list for steps in order. Use a bullet list for parallel items. Use a table for comparisons.
- Do not turn a two-sentence answer into bullets or headings.
- Put code, commands, paths and identifiers in backticks.
- Do not use decorative emoji.

## 6. Avoid common AI habits

These habits are less harmful than sections 1 to 3. An AI detector notices them, but a reader suffers more from hidden actions, vague words and buried points. Still, avoid them:

- "It's not X, it's Y" contrasts when nobody said X.
- Lists of exactly three for rhythm, not because there are three things.
- Rhetorical questions ("So what does this mean?").
- Openers like "Here's the thing", "Let's dive in", "In today's world".
- Words like `delve`, `tapestry`, `realm`, `testament`, `navigate` (for non-navigation).

## Check before you send

1. Does the first sentence give the point?
2. In each sentence, is the doer the subject and the action the verb?
3. Is there a stack of three or more nouns, or a term you invented without defining it?
4. Does every `it`, `this` and `that` point to one obvious thing?
5. Remove each sentence one at a time. If the reader loses nothing, keep it removed.
6. Would a colleague say this out loud?
