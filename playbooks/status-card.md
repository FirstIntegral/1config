# The status card

Read when: you are about to speak the status of a project: at the end of `continue_project` and of `checkpoint_project`, and at every rewrite of `session_compact.md`.

### Status card

`continue_project` and `checkpoint_project` speak this card and then stop. It is the whole status. Do not read the rest of the compact aloud.

**How things are** — one sentence, at most 20 words. What this project is, and where it stands: working, stuck, or waiting.

**Left to do** — Speak every line under `## Left to do` in `session_compact.md`, in that order. Item 1 is the next action. Each line is one action, at most 20 words.

**Replies** — `continue_project` only. Speak each reply the fetch found, and each `## Replies` line in `session_compact.md` that does not contain `heard`. Speak every one of them, with no cap and no `N more` line. Each line is who, the number, and the outcome, at most 20 words. No replies: omit this heading.

**Since last time** — `continue_project` only, and only when the GitHub fetch runs. One line, `nothing new`, or at most 3 change lines (who, and what moved). No GitHub remote: omit this heading. A reply is not one of these lines.

Say nothing that is not already in `session_compact.md`, `docs/DECISIONS.md`, or that fetch. A `notes-sync-merge` compact keeps both machines' open items under `## Left to do`. Speak every one of those lines.

Every rewrite of `session_compact.md` puts `## How things are` and `## Left to do` at the top, above `## Models used`. Keep `## Replies` under `## Left to do` when any line lacks `heard`. Add a line for each maintainer reply fetched this session. Append `heard` only when the user said that number is heard. When a GitHub fetch ran, record `Fetched YYYY-MM-DD`. Fold `## Current state`, `## Where we left off`, and `## Open issues / blockers` into those two headings. Keep every open item. Continue speaks the card and does not rewrite the file. After the checkpoint card, one line: `Checkpoint saved — next step: <item 1>`, plus the pushed hash or the script's exact non-push reason. An early stop (missing path, notes exit 23, no session layout) speaks the stop reason and skips the card.
