# `explain_thing`

Read when: the user says `explain_thing`.

## `explain_thing` trigger

When the user says **`explain_thing`** (optionally a path or a subject), write a discardable explainer. Chat stays caveman. The files use 80% STE. Read `skills/explain-thing/SKILL.md` and follow it. That file owns the sentence rules.

| File | When |
|------|------|
| `explain/brief.md` | every run |
| `explain/diagram.svg` | every run |
| `explain/page.html` | only when the user asks for html, a page, or a webpage |

The root is the path they gave, else the project root, else `/tmp/explain-<slug>/` when there is no project. The brain root is `~/.agents` when the subject is this repo.

Before the write, `explain/` must be ignored. On our project, add `explain/` to `.gitignore` when the line is missing. Do not rewrite the file. On a foreign checkout, do not edit their `.gitignore`. Add `/explain/` to `.git/info/exclude` when it is missing. Do not commit the directory. Do not add it to `notes.allow`.

Do not copy the ASD-STE100 dictionary. Do not claim ASD compliance or ASD endorsement. Do not call a speech API. Do not make a video.

The chat reply names the files. It does not paste the STE prose.
