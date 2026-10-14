#!/usr/bin/env node
// hooks/welcome.js — interactive 8-page first-install / overview walkthrough for 1config.
//
// Usage:
//   node ~/.agents/hooks/welcome.js            # interactive terminal walkthrough
//   node ~/.agents/hooks/welcome.js --self-test # non-interactive width & content check
const readline = require('readline');

const ESC = '\x1b[';
const ANSI = {
  reset: `${ESC}0m`,
  bold: `${ESC}1m`,
  dim: `${ESC}2m`,
  hideCursor: `${ESC}?25l`,
  showCursor: `${ESC}?25h`,
  clearScreen: `${ESC}2J${ESC}H`,
  cyan: `${ESC}38;5;75m`,
  brightCyan: `${ESC}38;5;117m`,
  emerald: `${ESC}38;5;78m`,
  amber: `${ESC}38;5;214m`,
  violet: `${ESC}38;5;140m`,
  white: `${ESC}38;5;255m`,
  slate: `${ESC}38;5;250m`,
  muted: `${ESC}38;5;242m`,
  darkGray: `${ESC}38;5;238m`,
  bgBadge: `${ESC}48;5;236m`,
};

function visibleLength(str) {
  return str.replace(/\x1b\[[0-9;?]*[a-zA-Z]/g, '').length;
}

function truncateVisible(str, maxVisible) {
  if (maxVisible <= 0) return '';
  if (visibleLength(str) <= maxVisible) return str;
  const regex = /(\x1b\[[0-9;?]*[a-zA-Z])|([^\x1b]+)/g;
  let result = '';
  let count = 0;
  let match;
  while ((match = regex.exec(str)) !== null) {
    if (match[1]) {
      result += match[1];
    } else if (match[2]) {
      const remaining = maxVisible - count;
      if (remaining <= 0) break;
      const chunk = match[2].slice(0, remaining);
      result += chunk;
      count += chunk.length;
    }
  }
  return result + ANSI.reset;
}

function padVisible(str, width) {
  const clipped = truncateVisible(str, width);
  const len = visibleLength(clipped);
  return len >= width ? clipped : clipped + ' '.repeat(width - len);
}

const BOX = { tl: '┌', tr: '┐', bl: '└', br: '┘', h: '─', v: '│', ml: '├', mr: '┤' };

function drawTopBorder(width, title = '', borderColor = ANSI.cyan) {
  const inner = width - 2;
  if (!title) return `${borderColor}${BOX.tl}${BOX.h.repeat(inner)}${BOX.tr}${ANSI.reset}`;
  const leftBars = 2;
  const maxTitleVis = Math.max(4, inner - leftBars - 2);
  const clippedTitle = truncateVisible(title, maxTitleVis - 2);
  const titleFormatted = ` ${clippedTitle} `;
  const titleLen = visibleLength(titleFormatted);
  const rightBars = Math.max(0, inner - leftBars - titleLen);
  return `${borderColor}${BOX.tl}${BOX.h.repeat(leftBars)}${ANSI.reset}${titleFormatted}${borderColor}${BOX.h.repeat(rightBars)}${BOX.tr}${ANSI.reset}`;
}

function drawDivider(width, borderColor = ANSI.cyan) {
  return `${borderColor}${BOX.ml}${BOX.h.repeat(width - 2)}${BOX.mr}${ANSI.reset}`;
}

function drawBottomBorder(width, footer = '', borderColor = ANSI.cyan) {
  const inner = width - 2;
  if (!footer) return `${borderColor}${BOX.bl}${BOX.h.repeat(inner)}${BOX.br}${ANSI.reset}`;
  const rightBars = 2;
  const maxFooterVis = Math.max(4, inner - rightBars - 2);
  const clippedFooter = truncateVisible(footer, maxFooterVis - 2);
  const footerFormatted = ` ${clippedFooter} `;
  const footerLen = visibleLength(footerFormatted);
  const leftBars = Math.max(0, inner - rightBars - footerLen);
  return `${borderColor}${BOX.bl}${BOX.h.repeat(leftBars)}${ANSI.reset}${footerFormatted}${borderColor}${BOX.h.repeat(rightBars)}${BOX.br}${ANSI.reset}`;
}

function drawBoxRow(content, width, borderColor = ANSI.cyan, padding = 2) {
  const inner = width - 2;
  const padStr = ' '.repeat(padding);
  const usable = inner - padding * 2;
  return `${borderColor}${BOX.v}${ANSI.reset}${padStr}${padVisible(content, usable)}${padStr}${borderColor}${BOX.v}${ANSI.reset}`;
}

function wrapText(text, maxWidth) {
  const words = text.split(' ');
  const lines = [];
  let current = '';
  for (const word of words) {
    if (!current) current = word;
    else if (current.length + 1 + word.length <= maxWidth) current += ' ' + word;
    else {
      lines.push(current);
      current = word;
    }
  }
  if (current) lines.push(current);
  return lines;
}

function formatSnippetItems(items, usableInnerWidth, keyColor) {
  const maxKeyLen = items.reduce((max, it) => Math.max(max, it.key.length), 0);
  const sep = ' -> ';
  const prefixWidth = maxKeyLen + sep.length;
  const valWidth = Math.max(20, usableInnerWidth - prefixWidth);
  const out = [];

  for (const item of items) {
    const cleanVal = item.val.replace(/^\s*->\s*/, '');
    const keyPadded = item.key.padEnd(maxKeyLen, ' ');
    const wrappedVal = wrapText(cleanVal, valWidth);
    wrappedVal.forEach((vLine, idx) => {
      if (idx === 0) {
        out.push(`${keyColor}${keyPadded}${ANSI.reset}${ANSI.muted}${sep}${ANSI.reset}${ANSI.slate}${vLine}${ANSI.reset}`);
      } else {
        out.push(`${' '.repeat(prefixWidth)}${ANSI.slate}${vLine}${ANSI.reset}`);
      }
    });
  }
  return out;
}

const PAGES = [
  {
    id: 'welcome',
    badge: 'PAGE 1 OF 8  |  WELCOME & TOOL PARITY',
    title: 'Welcome to 1config.',
    subtitle: 'Canonical AI-terminal brain at ~/.agents/ for Claude Code, Grok, OpenCode, and Cursor Code.',
    borderColor: ANSI.cyan,
    accentColor: ANSI.brightCyan,
    sentences: [
      'Welcome to 1config.',
      '1config is a single canonical brain at ~/.agents/ that unifies Claude Code, Grok, OpenCode, and Cursor Code under one rules file, one permission policy, and one setup script.',
      'Running setup.sh symlinks ~/.agents/AGENTS.md into every tool\'s expected global path (plus generates ~/.cursor/rules/1config.mdc with alwaysApply: true) and fans out permissions.json into their respective configs.',
      'Tool parity is a hard rule: a feature that works in one tool and not the others is treated as a bug, and verify.sh checks all four tools on every run.',
      'Skills split into three homes: 5 tracked process skills in ~/.agents/skills/ (adapted from obra/superpowers, linked into Claude via setup.sh 1b), gitignored machine-local skills (omarchy, vigil, diagnose-crash), and design skills in ~/Projects/skills/.',
    ],
    snippetTitle: 'Canonical fan-out (~/.agents/)',
    snippetItems: [
      { key: 'AGENTS.md', val: '~/.claude/CLAUDE.md, ~/.grok/AGENTS.md, ~/.config/opencode/AGENTS.md, ~/.cursor/AGENTS.md' },
      { key: 'permissions.json', val: 'Claude settings.json, Grok config.toml, OpenCode opencode.jsonc (external_directory=allow)' },
      { key: 'sync.sh', val: 'Runs setup.sh + verify.sh + GPG-signed commit + push to origin in BRAIN_REMOTE' },
    ],
  },
  {
    id: 'agents-md',
    badge: 'PAGE 2 OF 8  |  GLOBAL VS LOCAL AGENTS.MD',
    title: 'Two-Tier AGENTS.md, Self-Healing Memory & Kept Out',
    subtitle: 'Global rules, project ADRs, disabled tool memory stores, stray merging, and Kept Out boundaries.',
    borderColor: ANSI.violet,
    accentColor: ANSI.violet,
    sentences: [
      'Global ~/.agents/AGENTS.md stays lean (~1.4% of a 1M-token window, well under the 3% ceiling) and holds cross-project rules, workflow triggers, and machine toolchains.',
      'Each repository has its own <repo>/AGENTS.md for project conventions and docs/DECISIONS.md for architecture decisions enforced by single-active Policy keys (superseded entries carry superseded-by).',
      'Project CLAUDE.md files are forbidden because they hide AGENTS.md from Claude Code 2.1.277+ native loading; hooks/load-project-agents.sh checks version, instruction mode, and parent suppressors so AGENTS.md (capped at 20KB) is never double-injected into context.',
      'Tool-internal memory stores (~/.grok/memory and Claude topic files) are disabled and wiped by daily cron guards that stage residue into PENDING.md; if a tool breaks a symlink, merge-strays.sh quarantines it and feeds it to a headless LLM (filtering retired tokens in hooks/kill-tokens.deny).',
      'Kept out by design: no SOUL.md/USER.md/IDENTITY.md split (Caveman mode is the voice), no agent-readable daily diary (transcript stays private), and no personal mail/calendar heartbeat.',
    ],
    snippetTitle: 'Repo-aware rules & Kept Out boundaries',
    snippetItems: [
      { key: 'Sites (~/Projects/sites/*)', val: 'AGENTS.md is gitignored so agent rules stay private; docs/DECISIONS.md is committed' },
      { key: 'Forks (fork-parents.txt)', val: 'Notes go in .git/info/exclude (never upstream .gitignore); checkpoint exits 14 before push' },
      { key: 'Kept out of 1config', val: 'No SOUL.md/USER.md/IDENTITY.md, no agent-readable daily diary, no mail/calendar heartbeat' },
    ],
  },
  {
    id: 'sessions',
    badge: 'PAGE 3 OF 8  |  TRANSCRIPTS, COMPACT & NOTES SYNC',
    title: 'Session Transcript vs. Compact & Cross-Machine Notes',
    subtitle: 'Strict transcript privacy, cumulative model tracking, and 3-way offline note merging.',
    borderColor: ANSI.emerald,
    accentColor: ANSI.emerald,
    sentences: [
      'Every project separates human session logs from AI handoff state using two gitignored files in the project root.',
      'session_transcript.md is an append-only chronological log written exclusively for the human; AI agents append at milestones but are strictly forbidden from reading it (enforced by hooks/rule-oracles.sh).',
      'session_compact.md is the AI handoff file, rewritten at milestones and before context compaction with current status, next steps, and a cumulative Models used list.',
      'Untracked project files (plus optional paths in notes.allow, excluding secrets/.env/keys) sync across machines through a private machine-notes repo (NOTES_REMOTE) keyed by lowercase host/owner/repo via hooks/notes-sync.sh.',
      'When two machines edit session_compact.md offline, notes-sync.sh keeps both copies under notes-sync-merge without an LLM call so neither machine\'s open items are lost.',
    ],
    snippetTitle: 'Session file contract & notes-sync.sh',
    snippetItems: [
      { key: 'session_compact.md', val: 'AI handoff (read first on session start, rewritten at milestones, tracks model + effort)' },
      { key: 'session_transcript.md', val: 'Human-only narrative log (write-only for agents; rule-oracles.sh blocks hook reads)' },
      { key: 'hooks/notes-sync.sh', val: 'Syncs untracked notes via NOTES_REMOTE; dedupes log prefixes & merges offline compact edits' },
    ],
  },
  {
    id: 'triggers',
    badge: 'PAGE 4 OF 8  |  TRIGGERS & DETERMINISTIC CHECKPOINTS',
    title: 'Project Lifecycle Triggers & Checkpoint Gates',
    subtitle: 'create_project, continue_project, checkpoint_project, and global_brain_update.',
    borderColor: ANSI.amber,
    accentColor: ANSI.amber,
    sentences: [
      'create_project <name> scaffolds ~/Projects/<name> from project-template/ (verified by hooks/rule-oracles.sh) and never runs git init or creates a remote.',
      'continue_project <path> checks memory and symlink residue flags, pulls cross-machine notes via notes-sync.sh, and reads session_compact.md, AGENTS.md, and docs/DECISIONS.md in order.',
      'checkpoint_project rewrites session_compact.md, appends a wrap-up entry to session_transcript.md, backfills docs/DECISIONS.md, and executes hooks/checkpoint.sh.',
      'checkpoint.sh enforces deterministic exit codes (0, 3, 10 through 23): git config always wins over AGENTS.md, session file leaks exit 20, and failed pushes never rebase or force-push.',
      'global_brain_update targets ~/.agents/ itself and requires running setup.sh and sync.sh in the same turn, plus regenerating setup-infographic.svg if architecture flows changed and evaluating whether hooks/welcome.js should mention the change.',
    ],
    snippetTitle: 'hooks/checkpoint.sh exit gates',
    snippetItems: [
      { key: 'Exit 0 / 3', val: 'Remote backup pushed / clean tree (then runs notes-sync.sh push for untracked notes)' },
      { key: 'Exit 12 / 14 / 15', val: 'Committed locally (no remote / foreign owner in fork-parents.txt) or tracked notes (15)' },
      { key: 'Exit 20 / 22 / 23', val: 'Refused: unignored session files (20), target is ~/.agents (22), or notes conflict (23)' },
    ],
  },
  {
    id: 'paper-writing',
    badge: 'PAGE 5 OF 8  |  PAPER WRITING & DIGIT-REFUSE',
    title: 'Publication-Grade LaTeX Papers & Digit-Refuse',
    subtitle: 'writepaper_project, zero external bibliography, and mechanical anti-hallucination checks.',
    borderColor: ANSI.cyan,
    accentColor: ANSI.brightCyan,
    sentences: [
      'writepaper_project scaffolds docs/paper/ from paper-template/ and compiles a full research paper via latexmk using texlive-full / texlive-meta (booktabs, pgfplots/TikZ, algorithm2e, siunitx) or tectonic.',
      'Author name and email are pulled directly from git config user.name and user.email; if either is empty, the build stops and asks rather than inventing a name.',
      'Papers are strictly self-contained with zero references: \\cite, refs.bib, DOIs, and arXiv IDs are banned, so prior art and derivations must be written out in plain prose and math.',
      'After latexmk, build.sh runs hooks/digit-refuse.py: it unfolds \\frac{a}{b} -> a/b, macros (6 passes), and \\input files, classifies every char into prose/table/caption/mask, and requires every prose measurement token (fractions, decimals, %, scientific, 13--2, 3+ digit ints; skipping years and 02-23-20174 IDs) to match a table or caption character-for-character (plus pdftotext check for digit-refuse.deny; --fuzzy/--near/--llm exit 2).',
      'Once docs/paper/ exists, it is part of the definition of done: any change to an algorithm, theorem, setup, or measured metric requires rebuilding the paper in the same turn (unmeasured numbers stay \\TODO{measure: ...} under Gaps).',
    ],
    snippetTitle: 'Paper verification rules (docs/paper/build.sh)',
    snippetItems: [
      { key: 'No references', val: 'Zero \\cite or refs.bib allowed; all derivations and assumptions stated inline' },
      { key: 'digit-refuse.py', val: 'Unfolds \\frac & macros; prose measurement tokens must match table/caption char-for-char (--fuzzy exits 2)' },
      { key: 'Living artifact', val: 'Scientifically relevant code or metric edits must update and rebuild main.pdf same-turn' },
    ],
  },
  {
    id: 'math-lean',
    badge: 'PAGE 6 OF 8  |  MATH FORMALIZATION & LEAN 4',
    title: 'Lean 4 Theorem Mirror & Kernel Verification',
    subtitle: 'Pinned lean-toolchain, 1:1 theorem mapping, sorryAx auditing, and statement fidelity.',
    borderColor: ANSI.violet,
    accentColor: ANSI.violet,
    sentences: [
      'Every new writepaper_project scaffold includes docs/paper/lean/ pinned to an exact leanprover/lean4:vX.Y.Z release in lean-toolchain (never stable or nightly).',
      'Lean 4 runs in user-space (~/.elan/bin/lean and lake) installed via hooks/install-elan.sh without root or curl-pipe-sh.',
      'LaTeX theorem labels map 1:1 to Lean declarations (for example, \\label{thm:foo} maps to thm_foo), and build.sh runs lake build automatically after latexmk.',
      'A theorem only counts as kernel-checked when its Lean declaration passes lake build with zero sorryAx in its axiom audit; unproved statements stay sorry and are listed under Gaps.',
      'To prevent Lean from proving a trivially different claim than the paper, statements are written in Lean first and quoted in LaTeX, or decomposed into a committed parts list and script-diffed (Mathlib is opt-in via lake exe cache get).',
    ],
    snippetTitle: 'Lean 4 verification pipeline (docs/paper/lean/)',
    snippetItems: [
      { key: '1:1 Mapping', val: '\\label{thm:foo} <-> thm_foo in Lean (reports n/m kernel-checked statements)' },
      { key: 'Axiom Audit', val: 'Checks compiled declarations for sorryAx; unproved claims go to Gaps list' },
      { key: 'Statement Fidelity', val: 'Flags statement-fidelity unmeasured in Gaps until mechanical LaTeX-to-Lean xwalk passes' },
    ],
  },
  {
    id: 'omarchy-plugin',
    badge: 'PAGE 7 OF 8  |  OMARCHY DESKTOP PLUGIN, DOTS & HUD',
    title: 'Omarchy Bar Plugin (firstintegral.1config), Dots & Brain HUD',
    subtitle: 'Ring mark bar widget, 17-tile Vitals board, Fix-with-Grok, local Spend ledger, and omarchy-dots.',
    borderColor: ANSI.emerald,
    accentColor: ANSI.emerald,
    sentences: [
      'On Omarchy machines, setup.sh installs omarchy-plugin/firstintegral.1config/ into ~/.config/omarchy/plugins/ and registers the ring mark icon on the right side of the bar (paired with FirstIntegral/omarchy-dots and the Vigil rm-root guard plugin).',
      'Clicking the ring icon opens a 760x820 Brain HUD anchored under the bar, starting on the Vitals page (key v) with the Spend page one key away (key s).',
      'The Vitals board runs 17 live local checks: checkout files, clean worktree, BRAIN_REMOTE match, HEAD vs origin/main, 4 rules symlinks, permissions, hooks, scaffolds, boot slip, cron guards, autostart, machine-notes, 4 CLIs, TeX, Lean, GPG signing, and plugin sync.',
      'Any failed vital turns the verdict to fault and pulses the bar dot; clicking a fault tile opens its detail lines, and pressing f (or Fix with Grok) launches a terminal running grok in ~/.agents pre-loaded with those exact fault lines.',
      'The Spend view (usage.py) does precision local token & cost accounting: sums OpenCode SQLite step-finish parts (input+output+reasoning+cache.read+cache.write + $ cost, avoiding session-table double-counting), sums 4 Claude token buckets, keeps Grok creditUsagePercent on 0-100 (so 1.0% never rescales to 100%), and base32-decodes Grok Bot .blob stems while dropping slices whose nextResetMs passed during hibernation.',
    ],
    snippetTitle: 'Omarchy HUD controls (firstintegral.1config)',
    snippetItems: [
      { key: '[v / g] Vitals view', val: '17 live machine & brain health checks; [f] launches Grok in ~/.agents to fix faults' },
      { key: '[s] Spend (usage.py)', val: 'OpenCode step-finish SQLite tokens+$, Claude 4-bucket sum, Grok 0-100%, Grok Bot base32 + hibernation guard' },
      { key: '[m / a / u / r] Keys', val: '[m] Model rows   [a] Quiet tools   [u] Refresh limits   [r] Re-read close-slip.txt' },
    ],
  },
  {
    id: 'under-the-hood',
    badge: 'PAGE 8 OF 8  |  AUTONOMY, GPG, UPDATER, STALENESS & HERDS',
    title: 'Autonomy, Headless GPG, Boot Updater, Staleness Watch & Herds',
    subtitle: 'Red lines, loopback GPG, CLI updater, watch-stale.sh, preview servers, Caveman & Herd Boards.',
    borderColor: ANSI.amber,
    accentColor: ANSI.amber,
    sentences: [
      '1config enables bash_without_prompt and edit_without_prompt by default (reversible via gitignored local.json) with a PreToolUse heredoc-rewrite.py hook for Claude, while Red Lines (destructive acts or anything leaving the machine) still wait for an explicit yes.',
      'Every commit is GPG-signed without GUI popups or AI co-author lines: gpg-git.sh signs in loopback mode using a dedicated gpg-signing keyring collection, and gpg-keyring.py (via vendored jeepney) scans raw *.keyring files on disk if D-Bus breaks.',
      'updater/ (boot-check.sh, update-apps.sh, on-resume.sh, system-sleep-shim.sh, refresh-inventory.py) upgrades grok/claude/opencode on @reboot and suspend-resume (skipping mise-managed shims) and writes live versions to gitignored inventory.local.md.',
      'Detached jobs must be armed same-turn with watch-stale.sh <pid> <log> (cries STALE only when both log growth and /proc/<pid>/stat fields 14+15 utime+stime after the last ")" use <1s CPU across 10m; idle preview servers are excluded), while Caveman mode stays always on (full).',
      'At login, boot-dashboard unlocks GPG first, fast-forwards ~/.agents (running setup.sh if pulled), syncs omarchy-dots, and writes close-slip.txt (cleared incrementally by close-slip.sh); for multi-agent work, Herd Boards coordinate waves on a flock-locked wall where every post ends with a fixed parseable vote token.',
    ],
    snippetTitle: 'Under-the-hood hooks & daemons (~/.agents/)',
    snippetItems: [
      { key: 'gpg-git.sh / gpg-keyring.py', val: 'Loopback GPG signing + direct on-disk keyring recovery via jeepney, zero AI attribution' },
      { key: 'updater/ + inventory.local', val: 'Boot & suspend-resume CLI updater; writes live versions to gitignored inventory.local.md' },
      { key: 'watch-stale.sh / Herd wall', val: '10m dual-signal (log + CPU) job monitor; flock-locked multi-wave wall for agent herds' },
    ],
  },
];

function renderHeader(width, pageIndex, totalPages) {
  const pager = PAGES.map((p, i) => {
    const num = `${i + 1}`;
    if (i < pageIndex) return `${ANSI.emerald}[${num}]${ANSI.reset}`;
    if (i === pageIndex) return `${ANSI.bold}${ANSI.brightCyan}[${num}/${totalPages} ${p.id}]${ANSI.reset}`;
    return `${ANSI.muted}[${num}]${ANSI.reset}`;
  }).join(' ');

  return [
    drawTopBorder(width, `${ANSI.bold}${ANSI.white}1config${ANSI.reset} ${ANSI.muted}| Page ${pageIndex + 1} of ${totalPages}${ANSI.reset}`, ANSI.darkGray),
    drawBoxRow(`${ANSI.bold}${ANSI.white}Welcome to 1config.${ANSI.reset}  ${ANSI.muted}|${ANSI.reset}  ${pager}`, width, ANSI.darkGray),
    drawBottomBorder(width, `${ANSI.muted}[<- / ->] Navigate Pages   [q] End Walkthrough${ANSI.reset}`, ANSI.darkGray),
  ].join('\n');
}

function renderControlFooterBox(width, pageIndex, totalPages, isAnimating) {
  const prevLabel = pageIndex > 0
    ? `${ANSI.brightCyan}[<- Left]${ANSI.reset} ${ANSI.slate}Page ${pageIndex}${ANSI.reset}`
    : `${ANSI.muted}[<- Left] --${ANSI.reset}`;

  const nextLabel = isAnimating
    ? `${ANSI.amber}[Right ->]${ANSI.reset} ${ANSI.white}Finish page${ANSI.reset}`
    : pageIndex < totalPages - 1
      ? `${ANSI.brightCyan}[Right ->]${ANSI.reset} ${ANSI.slate}Page ${pageIndex + 2}${ANSI.reset}`
      : `${ANSI.emerald}[Right -> / Enter]${ANSI.reset} ${ANSI.white}Finish & Exit${ANSI.reset}`;

  const midLabel = `${ANSI.muted}[R] Replay  [1-${totalPages}] Jump${ANSI.reset}`;
  const quitLabel = `${ANSI.muted}[Q / Esc] End${ANSI.reset}`;

  const row = `${prevLabel}  ${ANSI.muted}|${ANSI.reset}  ${nextLabel}  ${ANSI.muted}|${ANSI.reset}  ${midLabel}  ${ANSI.muted}|${ANSI.reset}  ${quitLabel}`;
  return [
    drawTopBorder(width, `${ANSI.muted}Controls (Page ${pageIndex + 1} of ${totalPages})${ANSI.reset}`, ANSI.darkGray),
    drawBoxRow(row, width, ANSI.darkGray),
    drawBottomBorder(width, '', ANSI.darkGray),
  ].join('\n');
}

let activeKeyResolver = null;
let queuedAction = null;

function setupKeyboardListener() {
  if (!process.stdin.isTTY) return;
  readline.emitKeypressEvents(process.stdin);
  process.stdin.setRawMode(true);
  process.stdin.resume();

  process.stdin.on('keypress', (str, key) => {
    if (!key) return;
    if (key.ctrl && key.name === 'c') {
      process.stdout.write(ANSI.showCursor + '\n');
      process.exit(0);
    }

    let action = null;
    if (key.name === 'right' || key.name === 'l' || key.name === 'n' || key.name === 'return' || key.name === 'enter' || key.name === 'space') {
      action = 'right_or_finish';
    } else if (key.name === 'left' || key.name === 'h' || key.name === 'b') {
      action = 'prev';
    } else if (key.name === 'r') {
      action = 'replay';
    } else if (key.name === 'q' || key.name === 'escape') {
      action = 'quit';
    } else if (str && str >= '1' && str <= String(PAGES.length)) {
      action = `jump:${parseInt(str, 10) - 1}`;
    }

    if (action) {
      if (activeKeyResolver) {
        const resolve = activeKeyResolver;
        activeKeyResolver = null;
        resolve(action);
      } else {
        queuedAction = action;
      }
    }
  });
}

function sleepInterruptible(ms) {
  if (queuedAction) {
    const act = queuedAction;
    queuedAction = null;
    return Promise.resolve(act);
  }
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      if (activeKeyResolver === onKey) activeKeyResolver = null;
      resolve(null);
    }, ms);
    const onKey = (action) => {
      clearTimeout(timer);
      resolve(action);
    };
    activeKeyResolver = onKey;
  });
}

function waitForNavigationAction() {
  if (!process.stdin.isTTY) return Promise.resolve('right_or_finish');
  if (queuedAction) {
    const act = queuedAction;
    queuedAction = null;
    return Promise.resolve(act);
  }
  return new Promise((resolve) => {
    activeKeyResolver = (action) => {
      activeKeyResolver = null;
      resolve(action);
    };
  });
}

function buildStaticPageLines(page, pageIndex, totalPages, width) {
  const bColor = page.borderColor;
  const aColor = page.accentColor;
  const usableOuterWidth = width - 6;
  const usableSentenceWidth = width - 10;
  const out = [];

  out.push(...renderHeader(width, pageIndex, totalPages).split('\n'));
  out.push('');
  out.push(drawTopBorder(width, `${ANSI.bgBadge}${aColor}${ANSI.bold} ${page.badge} ${ANSI.reset}`, bColor));
  out.push(drawBoxRow('', width, bColor));
  for (const tLine of wrapText(page.title, usableOuterWidth)) {
    out.push(drawBoxRow(`${ANSI.bold}${ANSI.white}${tLine}${ANSI.reset}`, width, bColor));
  }
  for (const subLine of wrapText(page.subtitle, usableOuterWidth)) {
    out.push(drawBoxRow(`${aColor}${subLine}${ANSI.reset}`, width, bColor));
  }
  out.push(drawBoxRow('', width, bColor));
  out.push(drawDivider(width, bColor));
  out.push(drawBoxRow('', width, bColor));

  for (let sIdx = 0; sIdx < page.sentences.length; sIdx++) {
    const wrappedLines = wrapText(page.sentences[sIdx], usableSentenceWidth);
    for (let lIdx = 0; lIdx < wrappedLines.length; lIdx++) {
      const prefixDone = lIdx === 0 ? `${ANSI.emerald}*${ANSI.reset} ` : '  ';
      out.push(drawBoxRow(`${prefixDone}${ANSI.white}${wrappedLines[lIdx]}${ANSI.reset}`, width, bColor));
    }
    if (sIdx < page.sentences.length - 1) {
      out.push(drawBoxRow('', width, bColor));
    }
  }

  out.push(drawBoxRow('', width, bColor));
  if (page.snippetItems && page.snippetItems.length > 0) {
    const innerWidth = width - 6;
    const usableInner = innerWidth - 6;
    const formattedSnippetLines = formatSnippetItems(page.snippetItems, usableInner, aColor);
    out.push(drawBoxRow(drawTopBorder(innerWidth, `${ANSI.muted}${page.snippetTitle}${ANSI.reset}`, ANSI.darkGray), width, bColor, 2));
    for (const sLine of formattedSnippetLines) {
      out.push(drawBoxRow(drawBoxRow(sLine, innerWidth, ANSI.darkGray, 2), width, bColor, 2));
    }
    out.push(drawBoxRow(drawBottomBorder(innerWidth, '', ANSI.darkGray), width, bColor, 2));
    out.push(drawBoxRow('', width, bColor));
  }
  out.push(drawBottomBorder(width, `${ANSI.emerald}Page ${pageIndex + 1} of ${totalPages} complete (Press -> for next)${ANSI.reset}`, bColor));
  out.push('');
  out.push(...renderControlFooterBox(width, pageIndex, totalPages, false).split('\n'));
  return out;
}

function renderFullStaticPage(page, pageIndex, totalPages, width) {
  process.stdout.write(ANSI.clearScreen);
  for (const line of buildStaticPageLines(page, pageIndex, totalPages, width)) {
    console.log(line);
  }
}

function runSelfTest() {
  if (PAGES.length !== 8) {
    console.error(`FAIL: expected 8 pages, got ${PAGES.length}`);
    process.exit(1);
  }
  for (const w of [80, 92, 100, 106]) {
    for (let i = 0; i < PAGES.length; i++) {
      const lines = buildStaticPageLines(PAGES[i], i, PAGES.length, w);
      for (let idx = 0; idx < lines.length; idx++) {
        const l = lines[idx];
        if (!l) continue;
        const vLen = visibleLength(l);
        if (vLen !== w) {
          console.error(`FAIL: page ${i + 1} width ${w} line ${idx} has visibleLength=${vLen} != ${w}`);
          process.exit(1);
        }
      }
    }
  }
  console.log('welcome.js self-test: PASS (8 pages, strict border alignment across 80..106 cols)');
  process.exit(0);
}

async function renderPageAnimated(page, pageIndex, totalPages, width, skipInitialAnimation = false) {
  if (skipInitialAnimation) {
    renderFullStaticPage(page, pageIndex, totalPages, width);
    return null;
  }

  const charDelay = 34;
  const sentencePause = 950;
  const bColor = page.borderColor;
  const aColor = page.accentColor;
  const usableOuterWidth = width - 6;
  const usableSentenceWidth = width - 10;

  process.stdout.write(ANSI.clearScreen);
  console.log(renderHeader(width, pageIndex, totalPages));
  console.log('');
  console.log(drawTopBorder(width, `${ANSI.bgBadge}${aColor}${ANSI.bold} ${page.badge} ${ANSI.reset}`, bColor));
  console.log(drawBoxRow('', width, bColor));
  for (const tLine of wrapText(page.title, usableOuterWidth)) {
    console.log(drawBoxRow(`${ANSI.bold}${ANSI.white}${tLine}${ANSI.reset}`, width, bColor));
  }
  for (const subLine of wrapText(page.subtitle, usableOuterWidth)) {
    console.log(drawBoxRow(`${aColor}${subLine}${ANSI.reset}`, width, bColor));
  }
  console.log(drawBoxRow('', width, bColor));
  console.log(drawDivider(width, bColor));
  console.log(drawBoxRow('', width, bColor));

  for (let sIdx = 0; sIdx < page.sentences.length; sIdx++) {
    const wrappedLines = wrapText(page.sentences[sIdx], usableSentenceWidth);
    for (let lIdx = 0; lIdx < wrappedLines.length; lIdx++) {
      const lineText = wrappedLines[lIdx];
      const prefixActive = lIdx === 0 ? `${aColor}>${ANSI.reset} ` : '  ';
      const prefixDone = lIdx === 0 ? `${ANSI.emerald}*${ANSI.reset} ` : '  ';

      for (let c = 1; c <= lineText.length; c++) {
        const partial = lineText.slice(0, c);
        const cursor = c < lineText.length ? `${aColor}_${ANSI.reset}` : '';
        process.stdout.write('\r' + drawBoxRow(`${prefixActive}${ANSI.white}${partial}${ANSI.reset}${cursor}`, width, bColor));
        const interrupt = await sleepInterruptible(charDelay);
        if (interrupt) {
          if (interrupt === 'right_or_finish') {
            renderFullStaticPage(page, pageIndex, totalPages, width);
            return null;
          }
          return interrupt;
        }
      }
      process.stdout.write('\r' + drawBoxRow(`${prefixDone}${ANSI.white}${lineText}${ANSI.reset}`, width, bColor) + '\n');
    }
    if (sIdx < page.sentences.length - 1) {
      console.log(drawBoxRow('', width, bColor));
      const interrupt = await sleepInterruptible(sentencePause);
      if (interrupt) {
        if (interrupt === 'right_or_finish') {
          renderFullStaticPage(page, pageIndex, totalPages, width);
          return null;
        }
        return interrupt;
      }
    }
  }

  console.log(drawBoxRow('', width, bColor));
  if (page.snippetItems && page.snippetItems.length > 0) {
    const interruptBeforeSnippet = await sleepInterruptible(350);
    if (interruptBeforeSnippet) {
      if (interruptBeforeSnippet === 'right_or_finish') {
        renderFullStaticPage(page, pageIndex, totalPages, width);
        return null;
      }
      return interruptBeforeSnippet;
    }

    const innerWidth = width - 6;
    const usableInner = innerWidth - 6;
    const formattedSnippetLines = formatSnippetItems(page.snippetItems, usableInner, aColor);
    console.log(drawBoxRow(drawTopBorder(innerWidth, `${ANSI.muted}${page.snippetTitle}${ANSI.reset}`, ANSI.darkGray), width, bColor, 2));
    for (const sLine of formattedSnippetLines) {
      console.log(drawBoxRow(drawBoxRow(sLine, innerWidth, ANSI.darkGray, 2), width, bColor, 2));
      const interruptLine = await sleepInterruptible(120);
      if (interruptLine) {
        if (interruptLine === 'right_or_finish') {
          renderFullStaticPage(page, pageIndex, totalPages, width);
          return null;
        }
        return interruptLine;
      }
    }
    console.log(drawBoxRow(drawBottomBorder(innerWidth, '', ANSI.darkGray), width, bColor, 2));
    console.log(drawBoxRow('', width, bColor));
  }

  console.log(drawBottomBorder(width, `${ANSI.emerald}Page ${pageIndex + 1} of ${totalPages} complete (Press -> for next)${ANSI.reset}`, bColor));
  console.log('');
  console.log(renderControlFooterBox(width, pageIndex, totalPages, false));
  return null;
}

async function main() {
  if (process.argv.includes('--self-test')) {
    runSelfTest();
    return;
  }

  const seenPages = new Set();

  process.stdout.write(ANSI.hideCursor);
  process.on('SIGINT', () => {
    process.stdout.write(ANSI.showCursor + '\n');
    process.exit(0);
  });

  setupKeyboardListener();

  try {
    let currentPage = 0;
    let forceAnimate = false;

    while (currentPage >= 0 && currentPage < PAGES.length) {
      const width = Math.min(106, Math.max(80, (process.stdout.columns || 106) - 2));
      const page = PAGES[currentPage];
      const alreadySeen = seenPages.has(currentPage) && !forceAnimate;
      forceAnimate = false;

      let immediateAction = await renderPageAnimated(
        page,
        currentPage,
        PAGES.length,
        width,
        alreadySeen
      );
      seenPages.add(currentPage);

      const action = immediateAction || (await waitForNavigationAction());

      if (action === 'quit') {
        break;
      } else if (action === 'right_or_finish') {
        if (currentPage < PAGES.length - 1) {
          currentPage++;
        } else {
          break;
        }
      } else if (action === 'prev') {
        currentPage = Math.max(0, currentPage - 1);
      } else if (action === 'replay') {
        forceAnimate = true;
      } else if (action && action.startsWith('jump:')) {
        const target = parseInt(action.split(':')[1], 10);
        if (target >= 0 && target < PAGES.length) {
          currentPage = target;
        }
      }
    }
  } finally {
    process.stdout.write(ANSI.showCursor + '\n');
  }
}

main();
