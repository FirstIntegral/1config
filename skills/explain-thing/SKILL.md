---
name: explain-thing
description: Use when the user says explain_thing, or asks for an 80% STE brief, a diagram, or an HTML page that explains model output. Caveman stays the chat voice.
---

# explain-thing

Write a discardable explainer a person can check. The chat reply stays caveman. The files use 80% STE. This skill is not an ASD product. It does not certify ASD-STE100. ASD-STE100 is a trademark of ASD. ASD does not endorse this skill.

The official issue is free by request at https://asd-ste100.org/STE_downloads.html. Do not copy its dictionary into this repo, the explainer, or a prompt.

Output paths, the ignore rule, and the video ban are in the `explain_thing` trigger in `AGENTS.md`. Follow that contract. This file is how the sentences, the diagram, and the page are written.

## Resolve

1. A path the user gave is the root when that directory exists.
2. Otherwise walk up from the working directory to the nearest directory that contains `AGENTS.md` or `session_compact.md`. Stop before `$HOME`.
3. When the subject is this brain, the root is `~/.agents`.
4. When no project root exists, use `/tmp/explain-<slug>/` and say that in the chat reply.

Done when the root is one real directory.

## Ignore

Before any write:

- Our project: add a single `explain/` line to `.gitignore` when it is missing. Do not rewrite the rest of the file.
- Foreign checkout: do not edit their `.gitignore`. Add `/explain/` to `.git/info/exclude` when it is missing.
- Not a git repo: still write only under `explain/`, and say the directory is not ignored by git.

Done when `git check-ignore -q -- explain/brief.md` succeeds, or the root is not a git repo.

Rewrite the files on a later run. Do not leave a second copy.

## Sentences

80% STE means these rules. It does not mean the approved-word dictionary.

- Keep "the", "a", and "this".
- Write a full sentence. A fragment is not a sentence here.
- One idea in each sentence. One command in each procedural sentence.
- A procedural sentence has at most 20 words. A descriptive sentence has at most 25 words.
- A descriptive paragraph has one topic and at most 6 sentences.
- Use the active voice in a procedure.
- Use a command, the simple present, the simple past, the simple future, or an infinitive.
- A past participle is only an adjective: "the closed cover".
- Do not use a progressive verb. "The pump is stopping" is not allowed.
- Do not use a perfect verb. "The pump has stopped" is not allowed.
- Do not use the passive in a procedure. Write "Close the cover." A descriptive sentence may use the passive only when the actor is unknown.
- A noun cluster has at most 3 words. A path, a quoted error, a code identifier, and a technical name stay exact.
- Use the same word for the same thing.
- Use a vertical list when several conditions belong together.
- A line that can cause injury starts with `WARNING:`. A line that can cause damage starts with `CAUTION:`. Then the command. Then the risk.
- Do not invent a number. A count comes from a file you opened or a command you ran. When you cannot measure it, say you do not have the count.
- Quote a path, a command, and an error exactly, inside a fence when it is code.

First line of `explain/brief.md`, exact:

`Voice: 80% STE. Chat stays caveman. This file is not an ASD compliance claim.`

## Diagram

Write `explain/diagram.svg`.

- One SVG document. It opens by itself.
- Include `xmlns="http://www.w3.org/2000/svg"`. That attribute is not a network fetch.
- Do not use `<image>`, a remote font, or a linked stylesheet.
- A label is a noun phrase of at most 3 words, or one technical name.
- A sentence in the SVG follows the sentence rules.
- The picture shows the structure of the subject. It does not repeat the whole brief.

Done when the file is well-formed XML and a browser can open it.

## Page

Write `explain/page.html` only when the user asks for html, a page, or a webpage.

- One file. CSS is inline. The SVG is inline. A script is inline or absent.
- Do not load a network resource. No `src=`, no `href="http`, no `url(`, no `@import`.
- The words follow the sentence rules.
- The page is discardable. Do not treat it as the spec. `AGENTS.md` and `SETUP.md` stay the source of truth for this brain. A project spec stays in that project's tracked docs.

From the project root, this command must print nothing:

```bash
grep -E 'src=|href="https?:|url\(|@import' explain/page.html
```

## Chat

The reply stays caveman. Name the files you wrote. Do not paste the STE prose into the chat.

Copyright (c) 2026 Brusk Kawa Abdalla and https://github.com/FirstIntegral/1config
