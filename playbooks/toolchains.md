# Machine toolchains

Read when: the task needs TeX, Lean, or the Android SDK, or something asks you to install one of them.

## Machine toolchains (this machine)

- **TeX: `texlive-full` / `texlive-meta` installed** (Ubuntu/Debian pkg `texlive-full`; Omarchy/Arch `texlive-meta`). Full scheme — every CTAN package, every engine, all fonts. Write scientific papers, posters, TikZ/PGFPlots, beamer, bibliographies directly; **never** ask the user to install a LaTeX package, and never fall back to a Markdown-only deliverable for lack of TeX.
  - Engines: `pdflatex`, `xelatex`, `lualatex`, `tex` · build: `latexmk` (preferred, handles reruns) · bib: `biber`, `bibtex` · index: `makeindex` · also `texcount`, `latexdiff`.
  - `tectonic` also installed (`~/.local/bin`) — self-contained one-shot builds; use when a project's build script already calls it.
  - All of the above are allowlisted (no prompt). Package installs (`tlmgr install`) are not — and with `texlive-full` should never be needed.
- **Lean 4: `elan` → `lean` + `lake`** (user-space, `~/.elan`). Not a distro package. Per-project pin via `docs/paper/lean/lean-toolchain`. Kernel-checks Lean encodings of paper theorems; **never** ask the user to install Lean by hand — if `elan` is missing, run `bash ~/.agents/hooks/install-elan.sh` (download-then-run, no root, does not edit shell rc). Never AUR `elan-lean`, never distro `lean4`, never `curl | sh`.
  - Manager: `elan` · compiler: `lean` · build: `lake` (`lake build`). Mathlib is **opt-in per paper**, never in the brain template. `lake exe cache get` only when that paper's lakefile requires Mathlib; cache miss → fail closed, never compile Mathlib from source in a paper turn.
  - Pin: exact `leanprover/lean4:vX.Y.Z`. Never `stable`/`nightly`.
  - PATH: `~/.elan/bin`. Paper `build.sh` prepends it. Do not symlink into `~/.local/bin`.
  - Allowlisted. The install hook is the only install path. `leanlab` (PyPI) is unrelated — do not install it.
- **Android SDK, when a project needs one:** `$HOME/Android/Sdk` only. Never `$HOME/android-sdk`, never a second tree, never inside a repo. `local.properties` `sdk.dir` is the absolute path of that directory and stays gitignored. A project build sets `ANDROID_HOME` to the same directory. Look there before installing anything. If `$HOME/Android/Sdk` is absent, stop and name the path. Do not `mkdir` it. Do not run `sdkmanager`. Do not download command-line tools or platforms. A missing SDK is normal. `setup.sh` does not download it, and a missing tree is not a verify failure or a vitals fault.
