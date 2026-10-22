---
name: research-paper-writing
description: Use when writepaper_project is in progress or a docs/paper or paper-template file is being edited, and only for prose and claim checks. Digit-refuse owns numbers.
---
# Research Paper Writing

## 1config

Load this only inside `writepaper_project`, or while editing `docs/paper/` or `paper-template/`. Prose and claim checks only.

- Digit-refuse owns measurement tokens. Do not invent a number. A missing measurement is `\TODO{measure: ...}` in the paper, not a guessed table cell.
- No bibliography, no `\cite`, no numbered reference list, no DOI, no arXiv id. Prior art is plain prose.
- Do not replace the required section list in `AGENTS.md`. This skill checks flow and whether a claim has evidence.
- `references/examples/` and `references/does-my-writing-flow-source.md` are not in this copy. The paragraph check below is the flow test.
- Section guides under `references/` are shape and wording. The rules in this section win when a guide says to cite a paper or to write a metric.

## Overview

Use this skill to rewrite a research paper into a reviewer-friendly, high-clarity draft.
Prioritize first-impression quality (figures/tables/layout), logical flow, and evidence-backed claims.

## Core Workflow

1. Clarify the paper story before sentence-level edits.
2. Use section-specific guidance in `references/`.
3. Rewrite paragraph-by-paragraph with one message per paragraph.
4. Run reverse outlining after writing each section.
5. Check every major claim in Abstract/Introduction against experimental evidence that already exists. Do not invent a number to make the claim true.
6. Run final-paper adversarial review with `references/paper-review.md`.

## Global Principles

1. Keep one paragraph for one message only.
2. State the paragraph message in the first sentence.
3. Make nouns self-contained; define new terms before reusing them.
4. Maintain sentence-to-sentence flow (cause, contrast, consequence, or refinement).
5. Iterate with adversarial self-review: read as a skeptical reviewer.
6. Treat visual quality as core content, not decoration.
7. Use a clean teaser and pipeline figure.
8. Use readable, minimal-ink tables.
9. Keep formatting consistent and tidy.

## Paragraph Clarity Check (Important)

Use this quick test whenever the user asks whether a paragraph "flows" or is clear.

1. Read as an external reader:
   - Does this paragraph have one explicit message?
   - Does the first sentence state what this paragraph will do?
   - Are all key nouns/terms readable without hidden context?
   - Does each sentence connect to the previous one with a clear relation (cause, contrast, consequence, refinement, example)?
2. Run reverse outlining for the current section:
   - Write down thesis/main claim.
   - Write down each paragraph topic sentence.
   - Write down the evidence/explanation points under each paragraph.
   - Check mapping: topic sentence -> thesis, and evidence -> topic sentence.
   - Revise or remove any paragraph that cannot be mapped cleanly.
3. If flow is still weak, add temporary section headers and explicit transition phrases during revision, then remove unnecessary headers before finalizing.

## Section Guides

Load only the needed section file:

- Introduction: `references/introduction.md`
- Abstract: `references/abstract.md`
- Related work, as plain prose with no citations: `references/related-work.md`
- Method: `references/method.md`
- Experiments, structure and claims only: `references/experiments.md`
- Conclusion: `references/conclusion.md`
- Paper review: `references/paper-review.md`

## Paper Review Core Points

Use `references/paper-review.md` for the full checklist and workflow.

1. Add an end-of-draft self-review question list in five dimensions:
   - contribution,
   - writing clarity,
   - experimental strength,
   - evaluation completeness,
   - method design soundness.
2. Treat claim-evidence alignment as a hard constraint, especially for Abstract and Introduction.
3. Perform adversarial writing: review as a skeptical reviewer and resolve every high-risk question.
4. Revise until major rejection risks are explicitly addressed. A claim with no measurement becomes `\TODO{measure: ...}` or a weaker sentence. It does not gain a new number.

## Execution Rules

1. Build a mini-outline before drafting prose.
2. For each subsection, explicitly include motivation, design, and technical advantage when applicable.
3. Avoid writing style that looks like incremental patching of a naive baseline.
4. Keep terminology stable across the full paper.
5. If a claim cannot be supported by results, weaken or remove the claim.
6. Before finalizing, append and answer a five-dimension self-review question list, then revise the paper based on unresolved items.
7. Do not load all section references at once; load only the specific section guide needed for the current edit target.

## Output Contract

When asked to rewrite or draft sections, return:

1. A compact section outline (3-7 bullets).
2. Revised paragraphs with explicit paragraph roles (opening/challenge/method/advantage/evidence/limitation).
3. A short self-review checklist covering clarity, flow, terminology consistency, unsupported claims, and missing evidence.
4. A claim-evidence map for each major claim in the revised text using `Claim: ... | Evidence: ... | Status: supported/needs evidence`.

---

Adapted from [Master-cai/Research-Paper-Writing-Skills](https://github.com/Master-cai/Research-Paper-Writing-Skills) `research-paper-writing` at commit `77e7c2c1ba06f7d71844873147665437a03aac1b`. MIT License, Copyright (c) 2026 Master-cai. See UPSTREAM.md.
