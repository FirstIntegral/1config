# `writepaper_project`

Read when: the user says `writepaper_project`, or you change something a paper under `docs/paper/` asserts.

## `writepaper_project` trigger

When the user says **`writepaper_project`** (optionally `writepaper_project <path>` or with a topic/venue hint), write a **complete, full-length research paper about that project** — LaTeX, publication-grade, not a summary and not a README in disguise.

**Author block comes from git.** Run `git config --global --get user.name` and `git config --global --get user.email`. The name is the author. The email is the contact. If either is empty, stop and ask. Do not invent a name. Co-authors only when the user names them.

```latex
\author{NAME\thanks{\href{mailto:EMAIL}{EMAIL}}}
```

### Procedure

1. Resolve the project root (given path, else cwd walk-up stopping before `$HOME`). Read `session_compact.md`, `AGENTS.md`, `docs/DECISIONS.md`, then the actual **code, tests, benchmarks, logs, and result files**. Do not open a leftover `session_transcript.md`.
2. Scaffold `docs/paper/` from `~/.agents/paper-template/` (`main.tex`, `build.sh`, `figures/`, `lean/`) if not already there; otherwise extend what exists — never silently overwrite a paper in progress. First scaffold **includes** `lean/`. Existing `docs/paper/` without `lean/` is not backfilled.
3. Write the paper. Then **build it**: `bash docs/paper/build.sh` (latexmk → `main.pdf`; digit-refuse; `lake build` if `lean/` exists). Fix every LaTeX error, every digit-refuse miss, and every undefined reference/citation; a paper that does not compile is not delivered. `texlive-full` is installed — no package is missing, never stub one out.
4. Report: page count, section list, and an explicit **Gaps** list (what is `\TODO` and why).
5. Same turn: log paper-level choices (scope, claims, framing) in `docs/DECISIONS.md`, rewrite `session_compact.md`. Do not write `session_transcript.md`.

### Required structure (drop a section only if it truly does not apply, and say so)

Abstract · keywords · **Introduction** (motivation, gap, explicit contribution list) · **Background** (self-contained, no citations — see below) · **Preliminaries & notation** (symbol table; every symbol defined before use) · **Problem statement** (formal, with assumptions stated as such) · **Method / construction** · **Theory**: definitions, lemmas, theorems, propositions, corollaries — numbered `amsthm` environments, each with a proof (full proofs may move to an appendix, sketch in-line) · **Complexity / cost analysis** (time, space, sample, or numerical-error bounds as fitting) · **Algorithms** in pseudocode · **Implementation** (architecture, key design decisions from `DECISIONS.md`) · **Experimental setup** (hardware, software versions, seeds, datasets, hyperparameters) · **Results**: tables + figures with real numbers, `n`, mean ± CI or std, appropriate hypothesis test with its statistic, p-value and **effect size**, ablations · **Discussion** · **Limitations & threats to validity** · **Conclusion & future work** · **Appendices**: full proofs, extra derivations, and a **reproducibility appendix** (exact commands, commit hash, environment).

Use the science the project actually needs and do not water it down: formal statements over prose claims, derivations shown, units and error bars everywhere, `booktabs` tables, `pgfplots`/TikZ figures (generate data files from real runs), `algorithm2e` pseudocode, `siunitx` for quantities.

### HARD RULES for the content

- **No invented numbers.** Every reported measurement traces to something in the repo — a run you executed, a logged metric, a test output. If a number is needed and does not exist, either produce it by running the code, or write `\TODO{measure: …}` and list it under Gaps. Never fill a results table with plausible-looking values.
- **Digit refuse (default on new papers).** After latexmk, `build.sh` runs `~/.agents/hooks/digit-refuse.sh`. A measurement token in prose must already sit in a table or caption of that paper, exact characters. `digit-refuse.deny` lists tokens that must not be typeset at all. A number from 1900 to 2099 is checked like any other; a year the prose really names gets one `allow-year=<year>` line in `digit-refuse.cfg`. `\TODO{...}` is not a claim. Fuzzy match, a near number, an LLM read, or a repo-wide search exits 2 and writes nothing. A clean check is silent. A miss prints `file:line` and fails the build. Full rules: SETUP.md §5d. Existing papers are not backfilled.
- **NO REFERENCES AT ALL.** The paper is AI-written and self-contained: no bibliography, no `refs.bib`, no `\cite`, no numbered reference list, no "[1]"-style markers, no DOIs or arXiv IDs. If prior art must be mentioned, describe the idea in plain prose ("the standard fixed-point argument", "classical Runge–Kutta") without a citation key. A citation is never the reason to skip a derivation — derive it in the paper or state it as an assumption.
- **No overclaiming.** Theorems get proofs or they become conjectures. Empirical claims get the statistic that supports them. Scope conditions and failure cases go in Limitations, not omitted.
- Keep the paper a **living artifact**: re-running `writepaper_project` updates and extends it (new results, new sections), it does not restart from scratch.
- **Lean mirror — default on new papers.** First `writepaper_project` copies `~/.agents/paper-template/lean/` with the rest of `docs/paper/`. Do not backfill existing papers that have no `lean/`. Never overwrite a paper's existing Lean files. `leanlab` (PyPI) is unrelated.
  1. When `docs/paper/lean/` exists, `build.sh` runs `lake build` after latexmk (PATH prepends `~/.elan/bin`). Type errors fail the build. Missing `lake` → Gap, PDF still ships. Never `lake exe cache get` from `build.sh`; never compile Mathlib from source.
  2. Kernel-checked means that Lean declaration's axiom audit has no `sorryAx`. Unproved statements stay `sorry` and go on Gaps. Report `n/m kernel-checked Lean statements`; `build.sh` prints that count from `lean/axiom-audit.sh`. **Do not** claim the paper sentence was checked — `lake` green is not fidelity to LaTeX.
  3. 1:1 names: `\label{thm:foo}` ↔ `thm_foo` (or a listed rename). Delete `template_sanity` once real theorems exist.
  4. Conversion (so Lean does not prove a different claim): write the statement in Lean first and quote it in LaTeX, **or** decompose the LaTeX into a committed parts list and emit pedantic Lean from those rows, then script-diff the compiled signature. Do not freely restate then `lake build`. Until a mechanical xwalk exists, Gaps must include `statement-fidelity unmeasured` for every formalized theorem. Details: SETUP.md §5d.
  5. Mathlib only in that paper's `lakefile.toml` when statements need it (ℝ, polynomials, ODEs). Template stays core Lean.
  6. Same-turn "keep current" on non-theory edits does not require a Lean proof hunt. Theory-statement changes update the Lean mirror if `lean/` already exists.

### Keeping the paper current — HARD RULE once `docs/paper/` exists

After a project has a paper, **the paper is part of that project's definition of done.** Whenever anything scientifically relevant changes, update `docs/paper/` in the **same turn** as the change — no waiting for the user to re-say `writepaper_project`.

Scientifically relevant = anything the paper asserts: the method or algorithm, a definition, a theorem/lemma/proof, complexity, assumptions or their scope, experimental setup (hardware, versions, seeds, hyperparameters, datasets), any measured number, an ablation, a limitation, or a decision logged in `docs/DECISIONS.md` that the paper describes. Refactors, renames, tooling, and CI changes are **not** relevant unless they change a reported number or a stated claim.

Each such update: patch the affected sections (and the abstract/contributions if the claim moved), rebuild with `bash docs/paper/build.sh`, and say in one line what the paper now says differently. Numbers that went stale but have not been re-measured become `\TODO{measure: …}` — never left silently wrong.

`docs/paper/` **is committed** (it is product, not session state) — for `~/Projects/sites/*` the Sites rule in `~/.agents/AGENTS.md` still applies to `AGENTS.md` only.
